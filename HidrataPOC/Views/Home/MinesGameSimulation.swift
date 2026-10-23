import simd
import SwiftUI

/// Valores do Campo Minado para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum MinesGameTuning {
    static let columns = 8                       // casas na largura; as fileiras saem da altura do aquário
    static let maxRows = 11
    static let topMargin: Float = 64             // pt — abaixo dos botões do cabeçalho e do placar
    static let bottomMargin: Float = 14          // pt

    static let mineRatio: Float = 0.13           // fração das casas com pedra
    static let clearBonus = 10                   // pontos por limpar o campo inteiro

    static let longPress: Double = 0.35          // s segurando a casa pra marcar em vez de abrir
    static let wonTapLock: Float = 1.0           // s de confete antes de um toque poder recomeçar
    static let deathPause: Float = 2.2           // s mostrando as pedras antes de recomeçar
    static let revealWaterPush: Float = 1.2      // agito na superfície ao abrir casas
    static let explodeWaterPush: Float = 5       // agito ao achar uma pedra
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct MinesGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, won, dying }

    enum Cell: Sendable, Equatable {
        case hidden
        case flagged
        /// Aberta, com quantas pedras há em volta.
        case revealed(Int)
        /// Pedra à mostra no fim da partida; `exploded` é a que foi aberta.
        case stone(exploded: Bool)
        /// Bandeira numa casa sem pedra, mostrada no fim da partida.
        case wrongFlag
    }

    struct Particle: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
        /// Pó de pedra; senão, respingo de água.
        let isStone: Bool
    }

    let tile: CGFloat
    let board: CGRect
    let columns: Int
    let rows: Int
    /// Casas linha a linha, de cima pra baixo.
    let cells: [Cell]
    let particles: [Particle]
    let score: Int
    let stonesLeft: Int
    let phase: Phase
    let confetti: [Confetto]
    let phaseProgress: CGFloat  // 0…1 dentro de `dying`
}

/// Campo minado dentro do aquário: as minas são pedras escondidas embaixo das casas. Tocar abre
/// a casa (a primeira nunca tem pedra) e mostra quantas pedras há em volta; segurar, ou tocar com
/// o modo de marcar ligado (`flagMode`, o botão na Home), põe uma bandeira. Abrir uma pedra
/// acaba a partida; abrir todas as casas sem pedra limpa o campo, soma um bônus e termina o jogo
/// com confete e "Parabéns!" (um toque recomeça).
@MainActor
final class MinesGameSimulation {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        let radius: Float
        var life: Float
        let lifetime: Float
        let isStone: Bool
    }

    private(set) var isRunning = false
    /// Casas abertas na partida, mais os bônus dos campos limpos.
    private(set) var score = 0
    /// Tocar marca bandeira em vez de abrir (botão na Home).
    var flagMode = false
    /// Chamado quando uma pedra é aberta — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    private var phase: MinesGameSnapshot.Phase = .ready
    private var phaseTimer: Float = 0
    private var stones: Set<Int> = []
    /// Pedras em volta de cada casa (só vale depois de `placeStones`).
    private var counts: [Int] = []
    private var revealed: Set<Int> = []
    private var flagged: Set<Int> = []
    private var exploded: Int?
    /// As pedras só são sorteadas no primeiro toque, longe dele.
    private var stonesPlaced = false
    private var confetti = ConfettiShower()
    private var particles: [Particle] = []
    private var pendingWaterPush: (u: Float, strength: Float)?
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero

    // Grade pro tamanho atual do aquário (medida no `reset`).
    private var rows = 8
    private var tile: Float = 20
    private var origin: SIMD2<Float> = .zero
    private var layoutSize: CGSize = .zero

    private var cellCount: Int { MinesGameTuning.columns * rows }

    private var stoneCount: Int {
        max(1, Int((MinesGameTuning.mineRatio * Float(cellCount)).rounded()))
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
        confetti.clear()
        score = 0
        lastFrame = nil
    }

    /// Toque numa casa (`point` no espaço do aquário). `longPress` inverte o modo: segurar marca
    /// quando o toque abre, e abre quando o toque marca.
    func tap(at point: CGPoint, longPress: Bool) {
        guard isRunning, !needsReset else { return }
        // Depois do "Parabéns!", um toque (passado o tempo do confete) começa um campo novo.
        if phase == .won {
            guard phaseTimer >= MinesGameTuning.wonTapLock else { return }
            reset()
            phase = .playing
            return
        }
        guard phase == .ready || phase == .playing else { return }
        // O primeiro toque (em qualquer lugar) só tira o aviso de início; a jogada vem no seguinte.
        if phase == .ready {
            phase = .playing
            return
        }
        guard let index = cellIndex(at: point) else { return }
        if flagMode != longPress {
            toggleFlag(index)
        } else {
            reveal(index)
        }
    }

    /// Partida nova (pontos zerados) esperando o primeiro toque.
    private func reset() {
        needsReset = false
        layoutSize = size
        let width = Float(size.width), height = Float(size.height)
        let available = height - MinesGameTuning.topMargin - MinesGameTuning.bottomMargin
        tile = max(1, width / Float(MinesGameTuning.columns))
        rows = min(MinesGameTuning.maxRows, max(5, Int(available / tile)))
        tile = min(tile, available / Float(rows))
        origin = SIMD2((width - tile * Float(MinesGameTuning.columns)) / 2,
                       MinesGameTuning.topMargin + (available - tile * Float(rows)) / 2)
        score = 0
        confetti.clear()
        newBoard()
        phase = .ready
    }

    /// Campo novo, todo fechado; as pedras saem no primeiro toque.
    private func newBoard() {
        stones.removeAll()
        revealed.removeAll()
        flagged.removeAll()
        counts = Array(repeating: 0, count: cellCount)
        exploded = nil
        stonesPlaced = false
        phaseTimer = 0
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito das casas abertas e das pedras achadas.
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
        confetti.update(dt: dt)

        if let push = pendingWaterPush {
            pendingWaterPush = nil
            water.disturb(atU: push.u, strength: push.strength)
        }
        updateParticles(dt: dt)

        switch phase {
        case .ready, .playing:
            return
        case .won:
            phaseTimer += dt
        case .dying:
            phaseTimer += dt
            if phaseTimer >= MinesGameTuning.deathPause { reset() }
        }
    }

    private func toggleFlag(_ index: Int) {
        guard !revealed.contains(index) else { return }
        if flagged.remove(index) == nil { flagged.insert(index) }
        Haptic.selection.play()
    }

    /// Abre a casa; sem pedras em volta, abre as vizinhas também (e assim por diante).
    private func reveal(_ index: Int) {
        guard !flagged.contains(index), !revealed.contains(index) else { return }
        if !stonesPlaced { placeStones(avoiding: index) }
        if stones.contains(index) {
            explode(at: index)
            return
        }

        var queue = [index]
        var opened = 0
        revealed.insert(index)
        while let current = queue.popLast() {
            opened += 1
            guard counts[current] == 0 else { continue }
            for neighbor in neighbors(of: current)
            where !revealed.contains(neighbor) && !flagged.contains(neighbor) && !stones.contains(neighbor) {
                revealed.insert(neighbor)
                queue.append(neighbor)
            }
        }
        score += opened
        pendingWaterPush = (u(of: index), MinesGameTuning.revealWaterPush * min(3, Float(opened)))
        if opened > 1 { spawnParticles(at: center(of: index), count: 6, stone: false) }

        if revealed.count == cellCount - stones.count {
            score += MinesGameTuning.clearBonus
            phase = .won
            phaseTimer = 0
            flagged = stones
            for cell in stones { spawnParticles(at: center(of: cell), count: 4, stone: true) }
            confetti.burst(in: size, colorCount: PebbleGameTuning.colors.count)
        } else {
            Haptic.tap.play()
        }
    }

    private func explode(at index: Int) {
        exploded = index
        phase = .dying
        phaseTimer = 0
        spawnParticles(at: center(of: index), count: 16, stone: true)
        pendingWaterPush = (u(of: index), MinesGameTuning.explodeWaterPush)
        Haptic.warning.play()
        onGameOver?(score)
    }

    /// Sorteia as pedras fora da casa tocada e das vizinhas dela, então o primeiro toque sempre
    /// abre um pedaço do campo.
    private func placeStones(avoiding index: Int) {
        stonesPlaced = true
        let safe = Set(neighbors(of: index)).union([index])
        var free = (0..<cellCount).filter { !safe.contains($0) }
        free.shuffle()
        stones = Set(free.prefix(min(stoneCount, free.count)))
        counts = (0..<cellCount).map { cell in neighbors(of: cell).filter { stones.contains($0) }.count }
    }

    private func neighbors(of index: Int) -> [Int] {
        let x = index % MinesGameTuning.columns, y = index / MinesGameTuning.columns
        var result: [Int] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < MinesGameTuning.columns, ny >= 0, ny < rows {
                    result.append(ny * MinesGameTuning.columns + nx)
                }
            }
        }
        return result
    }

    private func cellIndex(at point: CGPoint) -> Int? {
        let x = Int(floor((Float(point.x) - origin.x) / tile))
        let y = Int(floor((Float(point.y) - origin.y) / tile))
        guard x >= 0, x < MinesGameTuning.columns, y >= 0, y < rows else { return nil }
        return y * MinesGameTuning.columns + x
    }

    // MARK: Efeitos

    /// `stone`: pó de pedra (pedra achada ou campo limpo); senão, respingos de água.
    private func spawnParticles(at point: SIMD2<Float>, count: Int, stone: Bool) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let lifetime = Float.random(in: 0.4...0.9)
            particles.append(Particle(
                position: point,
                velocity: SIMD2(cos(angle), sin(angle)) * Float.random(in: 50...(stone ? 200 : 120)),
                radius: Float.random(in: 1.5...3.5),
                life: lifetime,
                lifetime: lifetime,
                isStone: stone
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

    private func center(of index: Int) -> SIMD2<Float> {
        let x = index % MinesGameTuning.columns, y = index / MinesGameTuning.columns
        return SIMD2(origin.x + (Float(x) + 0.5) * tile, origin.y + (Float(y) + 0.5) * tile)
    }

    private func u(of index: Int) -> Float {
        center(of: index).x / max(1, Float(size.width))
    }

    func snapshot() -> MinesGameSnapshot {
        let showsStones = phase == .dying
        let cells: [MinesGameSnapshot.Cell] = (0..<cellCount).map { i in
            if showsStones {
                if stones.contains(i) { return .stone(exploded: i == exploded) }
                if flagged.contains(i) { return .wrongFlag }
            }
            if revealed.contains(i) { return .revealed(counts[i]) }
            if flagged.contains(i) { return .flagged }
            return .hidden
        }
        return MinesGameSnapshot(
            tile: CGFloat(tile),
            board: CGRect(x: CGFloat(origin.x), y: CGFloat(origin.y),
                          width: CGFloat(tile) * CGFloat(MinesGameTuning.columns), height: CGFloat(tile) * CGFloat(rows)),
            columns: MinesGameTuning.columns,
            rows: rows,
            cells: cells,
            particles: particles.map {
                MinesGameSnapshot.Particle(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)),
                                           radius: CGFloat($0.radius), alpha: CGFloat($0.life / $0.lifetime), isStone: $0.isStone)
            },
            score: score,
            stonesLeft: max(0, stoneCount - flagged.count),
            phase: phase,
            confetti: confetti.snapshot(),
            phaseProgress: phase == .dying ? CGFloat(min(1, phaseTimer / MinesGameTuning.deathPause)) : 0
        )
    }
}
