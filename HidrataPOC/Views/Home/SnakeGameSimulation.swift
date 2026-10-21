import simd
import SwiftUI

/// Valores da Cobrinha para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum SnakeGameTuning {
    static let columns = 15                      // casas na largura; as fileiras saem da altura do aquário
    static let topMargin: Float = 58             // pt — abaixo dos botões do cabeçalho do aquário
    static let bottomMargin: Float = 14          // pt
    static let startLength = 4

    static let stepInterval: Float = 0.17        // s por casa no começo…
    static let minStepInterval: Float = 0.085    // …e o mais rápido que ela fica
    static let speedUpPerDrop: Float = 0.004     // s a menos por casa a cada pedrinha comida
    static let maxQueuedTurns = 2                // viradas guardadas pra próximas casas (toques rápidos)

    static let deathPause: Float = 1.5           // s da cobrinha estourando antes de recomeçar
    static let eatWaterPush: Float = 3           // agito na superfície a cada pedrinha comida
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct SnakeGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, dying }

    struct Particle: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    struct Stone: Sendable, Equatable {
        let colorIndex: Int
        let seed: Int

        static func random() -> Stone {
            Stone(colorIndex: Int.random(in: 0..<BubbleGameTuning.colors.count), seed: Int.random(in: 0..<1_000_000))
        }
    }

    let tile: CGFloat
    let board: CGRect
    /// Centros dos gomos, da cabeça pro rabo, já deslizando entre uma casa e a próxima.
    let segments: [CGPoint]
    /// Cor (índice em `BubbleGameTuning.colors`) e semente do formato de cada gomo, alinhados com
    /// `segments`; o primeiro é a cabeça, que tem cor própria.
    let segmentStones: [Stone]
    let heading: MazeDirection
    let food: CGPoint
    let foodStone: Stone
    let particles: [Particle]
    let score: Int
    let phase: Phase
    let phaseProgress: CGFloat  // 0…1 dentro de `dying`
}

/// Jogo da cobrinha dentro do aquário: uma fileira de pedrinhas coloridas (a da frente com olhos)
/// anda pela grade, e cada pedrinha que ela come entra no corpo e a deixa mais comprida e mais
/// rápida. Bater na borda ou
/// no próprio corpo desmancha a cobrinha, e uma nova partida espera o próximo deslize.
/// Anda de casa em casa, mas o desenho desliza entre elas (`segments`), então o movimento fica
/// contínuo. Vira pelo deslize no aquário. Usa `MazeDirection`, as mesmas quatro direções do
/// Rim Comilão.
@MainActor
final class SnakeGameSimulation {
    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        let radius: Float
        var life: Float
        let lifetime: Float
    }

    private(set) var isRunning = false
    /// Pedrinhas comidas na partida atual.
    private(set) var score = 0
    /// Chamado quando a cobrinha bate — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    private var phase: SnakeGameSnapshot.Phase = .ready
    private var phaseTimer: Float = 0
    /// Gomos da cabeça pro rabo, e como estavam antes do último passo (pro desenho deslizar).
    private var body: [Cell] = []
    private var previousBody: [Cell] = []
    private var heading: MazeDirection = .right
    private var queuedTurns: [MazeDirection] = []
    private var food = Cell(x: 0, y: 0)
    private var foodStone = SnakeGameSnapshot.Stone.random()
    /// Pedrinha de cada gomo, alinhada com `body` (a do índice 0, a cabeça, não é usada).
    private var stones: [SnakeGameSnapshot.Stone] = []
    private var stepClock: Float = 0
    private var particles: [Particle] = []
    private var pendingWaterPush = false
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero

    // Grade pro tamanho atual do aquário (medida no `reset`).
    private var rows = 10
    private var tile: Float = 20
    private var origin: SIMD2<Float> = .zero
    private var layoutSize: CGSize = .zero

    private var stepInterval: Float {
        max(SnakeGameTuning.minStepInterval, SnakeGameTuning.stepInterval - Float(score) * SnakeGameTuning.speedUpPerDrop)
    }

    // MARK: Ciclo de vida

    func start() {
        guard !isRunning else { return }
        isRunning = true
        needsReset = true
        lastFrame = nil
    }

    func stop() {
        isRunning = false
        particles.removeAll()
        queuedTurns.removeAll()
        score = 0
        lastFrame = nil
    }

    /// Direção escolhida (deslize no aquário); `alternate` é a outra metade de uma
    /// diagonal. Vale a que for curva em relação à última direção (seguir reto já é o padrão, e
    /// dar meia-volta mataria a cobrinha). Na tela de espera, também começa a partida.
    func setDirection(_ direction: MazeDirection, alternate: MazeDirection? = nil) {
        guard isRunning, !needsReset, phase != .dying else { return }
        if phase == .ready { phase = .playing }
        let last = queuedTurns.last ?? heading
        let turn = [direction, alternate].compactMap { $0 }.first { $0 != last && $0 != last.opposite }
        guard let turn, queuedTurns.count < SnakeGameTuning.maxQueuedTurns else { return }
        queuedTurns.append(turn)
    }

    /// Cobrinha nova no meio da grade, virada pra direita, esperando o primeiro comando.
    private func reset() {
        needsReset = false
        layoutSize = size
        let width = Float(size.width), height = Float(size.height)
        let available = height - SnakeGameTuning.topMargin - SnakeGameTuning.bottomMargin
        tile = max(1, width / Float(SnakeGameTuning.columns))
        rows = max(6, Int(available / tile))
        tile = min(tile, available / Float(rows))
        origin = SIMD2((width - tile * Float(SnakeGameTuning.columns)) / 2,
                       SnakeGameTuning.topMargin + (available - tile * Float(rows)) / 2)

        phase = .ready
        score = 0
        heading = .right
        queuedTurns.removeAll()
        stepClock = 0
        let middle = Cell(x: SnakeGameTuning.columns / 2, y: rows / 2)
        body = (0..<SnakeGameTuning.startLength).map { Cell(x: middle.x - $0, y: middle.y) }
        stones = body.map { _ in .random() }
        previousBody = body
        placeFood()
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito de cada pedrinha comida.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        // O aquário estica pra tela do jogo depois que ele já começou: só remede a grade na
        // tela de espera, pra não bagunçar uma partida em andamento.
        if needsReset || (size != layoutSize && phase == .ready) { reset() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        if pendingWaterPush {
            pendingWaterPush = false
            water.disturb(atU: (origin.x + (Float(body.first?.x ?? 0) + 0.5) * tile) / Float(size.width),
                          strength: SnakeGameTuning.eatWaterPush)
        }
        updateParticles(dt: dt)

        switch phase {
        case .ready:
            return
        case .playing:
            stepClock += dt
            while stepClock >= stepInterval, phase == .playing {
                stepClock -= stepInterval
                step()
            }
        case .dying:
            phaseTimer += dt
            if phaseTimer >= SnakeGameTuning.deathPause { reset() }
        }
    }

    /// Uma casa pra frente: come, cresce, ou bate.
    private func step() {
        if !queuedTurns.isEmpty { heading = queuedTurns.removeFirst() }
        guard let head = body.first else { return }
        let next = Cell(x: head.x + heading.delta.x, y: head.y + heading.delta.y)
        let eats = next == food
        // O rabo sai do lugar no mesmo passo (se não estiver crescendo), então dá pra ir atrás dele.
        let blocking = eats ? body : Array(body.dropLast())
        if next.x < 0 || next.x >= SnakeGameTuning.columns || next.y < 0 || next.y >= rows || blocking.contains(next) {
            die()
            return
        }
        previousBody = body
        body.insert(next, at: 0)
        // Comendo, a pedrinha comida entra logo atrás da cabeça (no lugar onde a cabeça estava);
        // senão cada gomo leva a sua pedrinha junto e o rabo sai.
        if eats { stones.insert(foodStone, at: 1) }
        if eats {
            score += 1
            spawnParticles(at: center(of: next), count: 8)
            pendingWaterPush = true
            Haptic.primary.play()
            placeFood()
        } else {
            body.removeLast()
        }
    }

    private func die() {
        phase = .dying
        phaseTimer = 0
        stepClock = 0
        previousBody = body
        for cell in body { spawnParticles(at: center(of: cell), count: 3) }
        Haptic.warning.play()
        onGameOver?(score)
    }

    private func placeFood() {
        let occupied = Set(body)
        var free: [Cell] = []
        for y in 0..<rows {
            for x in 0..<SnakeGameTuning.columns where !occupied.contains(Cell(x: x, y: y)) {
                free.append(Cell(x: x, y: y))
            }
        }
        food = free.randomElement() ?? Cell(x: 0, y: 0)
        foodStone = .random()
    }

    // MARK: Efeitos

    private func spawnParticles(at point: SIMD2<Float>, count: Int) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let lifetime = Float.random(in: 0.4...0.9)
            particles.append(Particle(
                position: point,
                velocity: SIMD2(cos(angle), sin(angle)) * Float.random(in: 50...170),
                radius: Float.random(in: 1.5...3.5),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        if particles.count > 220 { particles.removeFirst(particles.count - 220) }
    }

    private func updateParticles(dt: Float) {
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].velocity *= exp(-2 * dt)
            particles[i].velocity.y += 260 * dt
            particles[i].position += particles[i].velocity * dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: Foto pra desenhar

    private func center(of cell: Cell) -> SIMD2<Float> {
        SIMD2(origin.x + (Float(cell.x) + 0.5) * tile, origin.y + (Float(cell.y) + 0.5) * tile)
    }

    func snapshot() -> SnakeGameSnapshot {
        // Fração do caminho entre a casa de antes e a de agora (a cobrinha desliza entre elas).
        let progress = phase == .playing ? min(1, stepClock / stepInterval) : 1
        let segments: [CGPoint] = body.indices.map { i in
            let now = center(of: body[i])
            let before = i < previousBody.count ? center(of: previousBody[i]) : now
            let p = before + (now - before) * progress
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }
        let foodCenter = center(of: food)
        return SnakeGameSnapshot(
            tile: CGFloat(tile),
            board: CGRect(x: CGFloat(origin.x), y: CGFloat(origin.y),
                          width: CGFloat(tile) * CGFloat(SnakeGameTuning.columns), height: CGFloat(tile) * CGFloat(rows)),
            segments: segments,
            segmentStones: stones,
            heading: heading,
            food: CGPoint(x: CGFloat(foodCenter.x), y: CGFloat(foodCenter.y)),
            foodStone: foodStone,
            particles: particles.map {
                SnakeGameSnapshot.Particle(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)),
                                           radius: CGFloat($0.radius), alpha: CGFloat($0.life / $0.lifetime))
            },
            score: score,
            phase: phase,
            phaseProgress: phase == .dying ? CGFloat(min(1, phaseTimer / SnakeGameTuning.deathPause)) : 0
        )
    }
}
