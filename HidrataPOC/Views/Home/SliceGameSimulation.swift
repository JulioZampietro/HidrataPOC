import simd
import SwiftUI

/// Valores do Quebra-Pedras para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum SliceGameTuning {
    static let gravity: Float = 900              // pt/s² num aquário de `referenceHeight`
    static let referenceHeight: Float = 600      // pt — a física escala com a altura do aquário
    static let stoneRadius: ClosedRange<Float> = 20...30
    static let kidneyRadius: Float = 24
    static let minApex: Float = 0.35             // fração da altura que a pedra sobe, no mínimo…
    static let maxApex: Float = 0.75             // …e no máximo (medida a partir do fundo)
    static let spinRange: Float = 4              // rad/s pra cada lado

    // Ondas de pedras
    static let firstWaveDelay: Float = 0.6       // s depois do primeiro deslize
    static let waveInterval: ClosedRange<Float> = 1.0...1.6
    static let minWaveInterval: Float = 0.55     // com a pontuação alta, as ondas vêm mais juntas
    static let maxPerWave = 4
    static let kidneyChance: Float = 0.12        // chance de um objeto da onda ser um rim…
    static let maxKidneyChance: Float = 0.22     // …subindo com a pontuação
    static let difficultyScore = 80              // pontos até as ondas chegarem ao mais difícil
    static let kidneyFreeScore = 3               // sem rim até esses pontos, pra começar com calma

    // Corte
    static let minSwipeSegment: CGFloat = 3      // pt — movimento menor que isso não corta
    static let trailLifetime: Float = 0.18       // s que o rastro do dedo fica na tela
    static let comboWindow: Float = 0.35         // s entre cortes do mesmo deslize pra contar combo
    static let comboMinimum = 3                  // pedras num deslize pra valer combo
    static let strikes = 3                       // pedras que podem cair sem corte

    static let gameOverPause: Float = 1.8        // s mostrando "fim de jogo" antes de recomeçar
    static let sliceWaterPush: Float = 3         // agito na superfície a cada pedra cortada

    /// Cores das pedrinhas, as mesmas das Pedras Coloridas.
    static let colors: [Color] = PebbleGameTuning.colors
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct SliceGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, gameOver }

    struct Thing: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let angle: CGFloat
        let isKidney: Bool
        let colorIndex: Int
        let seed: Int
    }

    /// Metade de uma pedra cortada: a pedra inteira recortada pelo lado `side` da linha do corte.
    struct Half: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let angle: CGFloat
        let cutAngle: CGFloat
        let side: CGFloat       // −1 ou 1
        let colorIndex: Int
        let seed: Int
        let alpha: CGFloat
    }

    struct Particle: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
        let isKidney: Bool      // pedacinho de rim (rosa) ou gotinha d'água (azul)
    }

    struct Popup: Sendable {
        let text: String
        let position: CGPoint
        let alpha: CGFloat
    }

    let things: [Thing]
    let halves: [Half]
    let particles: [Particle]
    let trail: [CGPoint]
    let popups: [Popup]
    let score: Int
    let strikes: Int
    let phase: Phase
}

/// Fruit Ninja dentro do aquário: pedrinhas do rim pulam do fundo e o dedo, deslizando pela água,
/// corta cada uma em duas. No meio delas vem o próprio rim, que é pra proteger: deixar `strikes`
/// pedras caírem inteiras ou cortar o rim é fim de jogo. Cortar várias num deslize só vale combo. A partida começa no
/// primeiro deslize e, depois do fim, volta a esperar o próximo. Física própria em Swift, no mesmo
/// molde de `JumpGameSimulation`.
@MainActor
final class SliceGameSimulation {
    private struct Thing {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var angle: Float
        let spin: Float
        let radius: Float
        let isKidney: Bool
        let colorIndex: Int
        let seed: Int
    }

    private struct Half {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var angle: Float
        let spin: Float
        let radius: Float
        let cutAngle: Float
        let side: Float
        let colorIndex: Int
        let seed: Int
        var life: Float
    }

    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        let radius: Float
        var life: Float
        let lifetime: Float
        let isKidney: Bool
    }

    private struct TrailPoint {
        let position: CGPoint
        var age: Float
    }

    private struct Popup {
        let text: String
        var position: SIMD2<Float>
        var life: Float
    }

    private(set) var isRunning = false
    /// Pontos da partida atual.
    private(set) var score = 0
    /// Chamado no fim da partida — com os pontos dela.
    var onGameOver: ((Int) -> Void)?

    private var phase: SliceGameSnapshot.Phase = .ready
    private var things: [Thing] = []
    private var halves: [Half] = []
    private var particles: [Particle] = []
    private var trail: [TrailPoint] = []
    private var popups: [Popup] = []
    private var strikes = 0
    private var waveTimer: Float = 0
    private var gameOverTimer: Float = 0
    /// Ponto anterior do dedo no deslize atual (nil = dedo fora da água).
    private var lastTouch: CGPoint?
    /// Cortes do deslize atual que ainda contam pro combo, e quando foi o último.
    private var comboCount = 0
    private var comboClock: Float = 0
    private var clock: Float = 0
    private var pendingWaterPush: Float?
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero

    // MARK: Ciclo de vida

    func start() {
        guard !isRunning else { return }
        isRunning = true
        needsReset = true
        lastFrame = nil
    }

    func stop() {
        isRunning = false
        things.removeAll()
        halves.removeAll()
        particles.removeAll()
        trail.removeAll()
        popups.removeAll()
        lastTouch = nil
        score = 0
        lastFrame = nil
    }

    /// Dedo arrastando na água (coordenadas do jogo): corta o que o trecho desde o último ponto
    /// atravessar. Na tela de espera, o primeiro toque começa a partida.
    func swipe(to point: CGPoint) {
        guard isRunning, !needsReset else { return }
        defer { lastTouch = point }
        trail.append(TrailPoint(position: point, age: 0))
        // Na tela de espera o toque (sem precisar deslizar) já começa a partida.
        if phase == .ready {
            phase = .playing
            waveTimer = SliceGameTuning.firstWaveDelay
        }
        guard let last = lastTouch, hypot(point.x - last.x, point.y - last.y) >= SliceGameTuning.minSwipeSegment else { return }
        switch phase {
        case .ready:
            break
        case .playing:
            cut(from: SIMD2(Float(last.x), Float(last.y)), to: SIMD2(Float(point.x), Float(point.y)))
        case .gameOver:
            break
        }
    }

    /// Dedo saiu da água: fecha o deslize (e o combo dele).
    func endSwipe() {
        lastTouch = nil
        finishCombo()
    }

    private func reset() {
        needsReset = false
        phase = .ready
        score = 0
        strikes = 0
        gameOverTimer = 0
        things.removeAll()
        halves.removeAll()
        popups.removeAll()
        comboCount = 0
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito de cada corte.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        if needsReset { reset() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date
        clock += dt

        if let push = pendingWaterPush {
            pendingWaterPush = nil
            water.disturb(atU: 0.5, strength: push)
        }
        updateEffects(dt: dt)

        switch phase {
        case .ready:
            return
        case .playing:
            waveTimer -= dt
            if waveTimer <= 0 { spawnWave() }
            updateThings(dt: dt)
            if comboCount > 0, clock - comboClock > SliceGameTuning.comboWindow { finishCombo() }
        case .gameOver:
            updateThings(dt: dt)
            gameOverTimer -= dt
            if gameOverTimer <= 0 { reset() }
        }
    }

    private var gravity: Float { SliceGameTuning.gravity * Float(size.height) / SliceGameTuning.referenceHeight }

    /// 0 no começo, 1 com `difficultyScore` pontos.
    private var difficulty: Float { min(1, Float(score) / Float(SliceGameTuning.difficultyScore)) }

    /// Joga de 1 a `maxPerWave` objetos pra cima, a partir do fundo, cada um com seu arco.
    private func spawnWave() {
        let width = Float(size.width), height = Float(size.height)
        let count = Int.random(in: 1...max(1, Int(1 + difficulty * Float(SliceGameTuning.maxPerWave - 1) + 0.5)))
        let kidneyChance = SliceGameTuning.kidneyChance + (SliceGameTuning.maxKidneyChance - SliceGameTuning.kidneyChance) * difficulty
        for _ in 0..<count {
            let isKidney = score >= SliceGameTuning.kidneyFreeScore && Float.random(in: 0...1) < kidneyChance
            let radius = isKidney ? SliceGameTuning.kidneyRadius : Float.random(in: SliceGameTuning.stoneRadius)
            let x = Float.random(in: (width * 0.15)...(width * 0.85))
            let apex = height * Float.random(in: SliceGameTuning.minApex...SliceGameTuning.maxApex)
            let vy = -(2 * gravity * apex).squareRoot()
            let flightTime = 2 * -vy / gravity
            // Puxa pro meio do aquário, pra não sair pelos lados.
            let vx = (width / 2 - x) / flightTime * Float.random(in: 0.3...1.2)
            things.append(Thing(
                position: SIMD2(x, height + radius),
                velocity: SIMD2(vx, vy),
                angle: Float.random(in: 0...(2 * .pi)),
                spin: Float.random(in: -SliceGameTuning.spinRange...SliceGameTuning.spinRange),
                radius: radius,
                isKidney: isKidney,
                colorIndex: Int.random(in: 0..<min(5, SliceGameTuning.colors.count)),
                seed: Int.random(in: 0..<1_000_000)
            ))
        }
        // Um som por onda, mesmo se vier mais de um rim nela.
        if things.suffix(count).contains(where: \.isKidney) { MiniGameSound.kidneyFlying.play() }
        let interval = Float.random(in: SliceGameTuning.waveInterval)
        waveTimer = interval - (interval - SliceGameTuning.minWaveInterval) * difficulty
    }

    private func updateThings(dt: Float) {
        let height = Float(size.height)
        var fell = 0
        things.removeAll { thing in
            let gone = thing.velocity.y > 0 && thing.position.y - thing.radius > height
            if gone, !thing.isKidney { fell += 1 }
            return gone
        }
        for i in things.indices {
            things[i].velocity.y += gravity * dt
            things[i].position += things[i].velocity * dt
            things[i].angle += things[i].spin * dt
        }
        guard fell > 0, phase == .playing else { return }
        strikes += fell
        Haptic.warning.play()
        if strikes >= SliceGameTuning.strikes { endGame() }
    }

    // MARK: Corte

    private func cut(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        let direction = b - a
        let cutAngle = atan2(direction.y, direction.x)
        var cutKidney = false
        things.removeAll { thing in
            guard distance(from: thing.position, toSegment: a, b) < thing.radius else { return false }
            if thing.isKidney {
                cutKidney = true
                spawnParticles(at: thing.position, count: 24, kidney: true)
            } else {
                split(thing, cutAngle: cutAngle)
            }
            return true
        }
        if cutKidney {
            pendingWaterPush = SliceGameTuning.sliceWaterPush * 3
            endGame()
        }
    }

    /// Pedra cortada: vira duas metades que se afastam pros lados do corte, com respingos.
    private func split(_ thing: Thing, cutAngle: Float) {
        let normal = SIMD2(-sin(cutAngle), cos(cutAngle))
        for side: Float in [-1, 1] {
            halves.append(Half(
                position: thing.position,
                velocity: thing.velocity * 0.4 + normal * side * Float.random(in: 90...150),
                angle: thing.angle,
                spin: thing.spin + side * Float.random(in: 1...3),
                radius: thing.radius,
                cutAngle: cutAngle - thing.angle, // no referencial da pedra, que gira
                side: side,
                colorIndex: thing.colorIndex,
                seed: thing.seed,
                life: 1.5
            ))
        }
        spawnParticles(at: thing.position, count: 10, kidney: false)
        score += 1
        comboCount += 1
        comboClock = clock
        pendingWaterPush = SliceGameTuning.sliceWaterPush
        Haptic.primary.play()
    }

    private func finishCombo() {
        defer { comboCount = 0 }
        guard comboCount >= SliceGameTuning.comboMinimum, phase == .playing else { return }
        score += comboCount
        let anchor = trail.last?.position ?? CGPoint(x: size.width / 2, y: size.height / 2)
        popups.append(Popup(text: "Combo x\(comboCount)!", position: SIMD2(Float(anchor.x), Float(anchor.y) - 20), life: 1))
        Haptic.success.play()
    }

    private func endGame() {
        guard phase == .playing else { return }
        phase = .gameOver
        gameOverTimer = SliceGameTuning.gameOverPause
        comboCount = 0
        if pendingWaterPush == nil { pendingWaterPush = SliceGameTuning.sliceWaterPush * 2 }
        onGameOver?(score)
    }

    private func distance(from p: SIMD2<Float>, toSegment a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > 1e-6 else { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / lengthSquared))
        return simd_distance(p, a + ab * t)
    }

    // MARK: Efeitos

    private func spawnParticles(at point: SIMD2<Float>, count: Int, kidney: Bool) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let speed = Float.random(in: 60...(kidney ? 300 : 220))
            let lifetime = Float.random(in: 0.4...0.9)
            particles.append(Particle(
                position: point,
                velocity: SIMD2(cos(angle), sin(angle)) * speed + SIMD2(0, -60),
                radius: kidney ? Float.random(in: 2...3.5) : Float.random(in: 2...4.5),
                life: lifetime,
                lifetime: lifetime,
                isKidney: kidney
            ))
        }
        if particles.count > 200 { particles.removeFirst(particles.count - 200) }
    }

    private func updateEffects(dt: Float) {
        let height = Float(size.height)
        for i in halves.indices {
            halves[i].velocity.y += gravity * dt
            halves[i].position += halves[i].velocity * dt
            halves[i].angle += halves[i].spin * dt
            halves[i].life -= dt
        }
        halves.removeAll { $0.life <= 0 || $0.position.y - $0.radius > height }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].velocity *= exp(-1.5 * dt)
            particles[i].velocity.y += 500 * dt
            particles[i].position += particles[i].velocity * dt
        }
        particles.removeAll { $0.life <= 0 }
        for i in trail.indices { trail[i].age += dt }
        trail.removeAll { $0.age > SliceGameTuning.trailLifetime }
        for i in popups.indices {
            popups[i].life -= dt
            popups[i].position.y -= 30 * dt
        }
        popups.removeAll { $0.life <= 0 }
    }

    // MARK: Foto pra desenhar

    func snapshot() -> SliceGameSnapshot {
        func point(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }
        return SliceGameSnapshot(
            things: things.map {
                SliceGameSnapshot.Thing(position: point($0.position), radius: CGFloat($0.radius), angle: CGFloat($0.angle),
                                        isKidney: $0.isKidney, colorIndex: $0.colorIndex, seed: $0.seed)
            },
            halves: halves.map {
                SliceGameSnapshot.Half(position: point($0.position), radius: CGFloat($0.radius), angle: CGFloat($0.angle),
                                       cutAngle: CGFloat($0.cutAngle), side: CGFloat($0.side), colorIndex: $0.colorIndex,
                                       seed: $0.seed, alpha: CGFloat(min(1, $0.life * 2)))
            },
            particles: particles.map {
                SliceGameSnapshot.Particle(position: point($0.position), radius: CGFloat($0.radius),
                                           alpha: CGFloat($0.life / $0.lifetime), isKidney: $0.isKidney)
            },
            trail: trail.map(\.position),
            popups: popups.map { SliceGameSnapshot.Popup(text: $0.text, position: point($0.position), alpha: CGFloat($0.life)) },
            score: score,
            strikes: strikes,
            phase: phase
        )
    }
}
