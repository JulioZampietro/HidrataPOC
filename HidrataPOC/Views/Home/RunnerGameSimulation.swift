import simd
import SwiftUI

/// Valores da Gota Surfista para ajustar à mão (mesma ideia de `JumpGameTuning`). Distâncias em
/// metros do mundo do jogo; a `RunnerProjection` passa pra pontos na tela.
enum RunnerGameTuning {
    static let startSpeed: Float = 13            // m/s no começo…
    static let maxSpeed: Float = 27              // …o mais rápido que fica…
    static let acceleration: Float = 0.22        // …e quanto ganha por segundo
    static let laneChangeSpeed: Float = 9        // pistas por segundo ao trocar de pista
    static let jumpVelocity: Float = 7.5         // m/s pra cima no pulo
    static let gravity: Float = 22               // m/s²
    static let slideDuration: Float = 0.65       // s abaixada

    static let spawnDistance: Float = 70         // m à frente onde nascem os obstáculos
    static let firstRowDistance: Float = 38      // m à frente da primeira fileira, já na pista ao começar
    static let rowGap: ClosedRange<Float> = 15...23 // m entre fileiras (cresce um pouco com a velocidade)
    static let dropSpacing: Float = 2.6          // m entre as gotinhas de uma fileira
    static let dropScore = 5                     // pontos por gotinha
    static let metersPerPoint: Float = 4         // m percorridos por ponto
    static let rockClearHeight: Float = 0.7      // altura (m) que passa por cima da pedra

    static let deathPause: Float = 1.6           // s da batida antes de recomeçar
    static let crashWaterPush: Float = 5         // agito na superfície ao bater
    static let dropWaterPush: Float = 0.8        // agito ao pegar uma gotinha
}

/// Câmera da Gota Surfista: atrás e acima da gota, olhando pra frente. `z` é a distância à
/// frente da gota (0 = ela), `lane` vai de −1 a 1 (as três pistas) e `height` é a altura em metros.
struct RunnerProjection: Sendable {
    let size: CGSize

    /// Distância (m) da câmera até a gota.
    static let cameraDistance: CGFloat = 5
    /// Até onde a pista aparece.
    static let farZ: CGFloat = 72

    /// Linha do horizonte, abaixo dos botões do cabeçalho do aquário.
    var horizonY: CGFloat { 84 }
    /// Altura do chão onde a gota está.
    var groundY: CGFloat { size.height - 40 }
    /// Distância (pt) entre o meio de duas pistas, na altura da gota.
    var laneSpacing: CGFloat { size.width * 0.27 }
    /// Pontos por metro na altura da gota (as pistas têm 1,6 m).
    var meter: CGFloat { laneSpacing / 1.6 }

    func scale(at z: CGFloat) -> CGFloat {
        Self.cameraDistance / max(0.2, z + Self.cameraDistance)
    }

    func point(lane: CGFloat, height: CGFloat = 0, z: CGFloat) -> CGPoint {
        let s = scale(at: z)
        return CGPoint(x: size.width / 2 + lane * laneSpacing * s,
                       y: horizonY + (groundY - horizonY) * s - height * meter * s)
    }
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct RunnerGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, dying }

    enum Kind: Sendable {
        /// Pedra baixa: pula por cima.
        case rock
        /// Laje de pedra no alto, apoiada em duas colunas: abaixa pra passar por baixo.
        case arch
        /// Pilha alta de pedras: só desviando de pista.
        case pile
    }

    struct Obstacle: Sendable {
        let kind: Kind
        let lane: CGFloat
        let z: CGFloat
        let seed: Int
    }

    struct Drop: Sendable {
        let lane: CGFloat
        let height: CGFloat
        let z: CGFloat
    }

    struct Particle: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    let projection: RunnerProjection
    /// Metros percorridos (pras faixas da pista andarem).
    let travelled: CGFloat
    let playerLane: CGFloat
    let playerHeight: CGFloat
    /// −1 indo pra esquerda, 1 pra direita, 0 parada na pista (pros olhos olharem pro lado).
    let playerFacing: CGFloat
    /// 0…1: quanto a gota está achatada (abaixada).
    let crouch: CGFloat
    let obstacles: [Obstacle]
    let drops: [Drop]
    let particles: [Particle]
    let score: Int
    let phase: Phase
    let phaseProgress: CGFloat  // 0…1 dentro de `dying`
}

/// Corrida sem fim dentro do aquário: a gota surfa numa prancha por três pistas que vêm em
/// direção à tela, cada vez mais rápido. Deslizar pros lados troca de pista, pra cima pula (passa
/// por cima das pedras baixas) e pra baixo abaixa (passa por baixo das lajes); as pilhas altas só
/// desviando. Gotinhas pelo caminho valem pontos extras. Bater acaba a partida, e uma nova espera
/// o próximo deslize.
@MainActor
final class RunnerGameSimulation {
    private struct Obstacle {
        let kind: RunnerGameSnapshot.Kind
        let lane: Int
        var z: Float
        let seed: Int
    }

    private struct Drop {
        let lane: Int
        let height: Float
        var z: Float
    }

    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        let radius: Float
        var life: Float
        let lifetime: Float
    }

    private(set) var isRunning = false
    private(set) var score = 0
    /// Chamado quando a gota bate — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    private var phase: RunnerGameSnapshot.Phase = .ready
    private var phaseTimer: Float = 0
    private var speed = RunnerGameTuning.startSpeed
    private var travelled: Float = 0
    private var dropsCollected = 0
    private var targetLane = 0
    private var laneX: Float = 0
    private var height: Float = 0
    private var verticalSpeed: Float = 0
    private var slideTimer: Float = 0
    private var obstacles: [Obstacle] = []
    private var drops: [Drop] = []
    /// Metros até a próxima fileira de obstáculos.
    private var untilNextRow: Float = 0
    private var particles: [Particle] = []
    private var pendingWaterPush: (u: Float, strength: Float)?
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero

    private var projection: RunnerProjection { RunnerProjection(size: size) }

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
        score = 0
        lastFrame = nil
    }

    /// Deslize no aquário (um por arrasto, ver `RunnerGameView`): pros lados troca uma pista, pra
    /// cima pula, pra baixo abaixa (no ar, desce rápido e já chega abaixada). Na tela de espera,
    /// também começa a partida.
    func swipe(_ direction: MazeDirection) {
        guard isRunning, !needsReset, phase != .dying else { return }
        if phase == .ready { phase = .playing }
        switch direction {
        case .left, .right:
            let lane = max(-1, min(1, targetLane + direction.delta.x))
            guard lane != targetLane else { return }
            targetLane = lane
            Haptic.selection.play()
        case .up:
            guard height <= 0.01 else { return }
            verticalSpeed = RunnerGameTuning.jumpVelocity
            slideTimer = 0
            Haptic.tap.play()
        case .down:
            if height > 0.01 { verticalSpeed = -RunnerGameTuning.jumpVelocity * 1.4 }
            slideTimer = RunnerGameTuning.slideDuration
            Haptic.tap.play()
        }
    }

    /// Partida nova: gota parada na pista do meio, com a pista vazia por um trecho.
    private func reset() {
        needsReset = false
        phase = .ready
        phaseTimer = 0
        speed = RunnerGameTuning.startSpeed
        travelled = 0
        dropsCollected = 0
        score = 0
        targetLane = 0
        laneX = 0
        height = 0
        verticalSpeed = 0
        slideTimer = 0
        obstacles.removeAll()
        drops.removeAll()
        // A pista já começa com fileiras perto (a primeira chega em ~3 s), em vez de vazia até a
        // primeira fileira vir lá do fundo.
        var z = RunnerGameTuning.firstRowDistance
        while z < RunnerGameTuning.spawnDistance {
            spawnRow(at: z)
            z += Float.random(in: RunnerGameTuning.rowGap)
        }
        untilNextRow = z - RunnerGameTuning.spawnDistance
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito das gotinhas pegas e das batidas.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        if needsReset { reset() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        if let push = pendingWaterPush {
            pendingWaterPush = nil
            water.disturb(atU: push.u, strength: push.strength)
        }
        updateParticles(dt: dt)

        switch phase {
        case .ready:
            return
        case .playing:
            step(dt: dt)
        case .dying:
            phaseTimer += dt
            if phaseTimer >= RunnerGameTuning.deathPause { reset() }
        }
    }

    private func step(dt: Float) {
        speed = min(RunnerGameTuning.maxSpeed, speed + RunnerGameTuning.acceleration * dt)
        let distance = speed * dt
        travelled += distance

        // Gota: desliza até a pista escolhida, pula e cai, e levanta depois de abaixar.
        let maxLaneStep = RunnerGameTuning.laneChangeSpeed * dt
        laneX += max(-maxLaneStep, min(maxLaneStep, Float(targetLane) - laneX))
        if height > 0 || verticalSpeed > 0 {
            verticalSpeed -= RunnerGameTuning.gravity * dt
            height = max(0, height + verticalSpeed * dt)
            if height == 0 { verticalSpeed = 0 }
        }
        slideTimer = max(0, slideTimer - dt)

        for i in obstacles.indices { obstacles[i].z -= distance }
        for i in drops.indices { drops[i].z -= distance }
        obstacles.removeAll { $0.z < -4 }
        drops.removeAll { $0.z < -4 }

        untilNextRow -= distance
        if untilNextRow <= 0 {
            spawnRow(at: RunnerGameTuning.spawnDistance)
            untilNextRow = Float.random(in: RunnerGameTuning.rowGap) * (speed / RunnerGameTuning.startSpeed).squareRoot()
        }

        collectDrops()
        if let hit = obstacles.first(where: isHitting) {
            crash(into: hit)
            return
        }
        score = Int(travelled / RunnerGameTuning.metersPerPoint) + dropsCollected * RunnerGameTuning.dropScore
    }

    /// Uma fileira nova `z` metros à frente: obstáculos em uma ou duas pistas (sempre sobra uma
    /// livre) e, às vezes, uma fileira de gotinhas — numa pista livre, ou em arco por cima de uma pedra.
    private func spawnRow(at z: Float) {
        let blocked = Array([-1, 0, 1].shuffled().prefix(Bool.random() ? 1 : 2))
        for lane in blocked {
            let roll = Float.random(in: 0..<1)
            let kind: RunnerGameSnapshot.Kind = roll < 0.4 ? .pile : (roll < 0.75 ? .rock : .arch)
            obstacles.append(Obstacle(kind: kind, lane: lane, z: z, seed: Int.random(in: 0..<1_000_000)))
        }
        guard Float.random(in: 0..<1) < 0.65 else { return }
        if let rock = obstacles.last(where: { $0.z == z && $0.kind == .rock }), Bool.random() {
            for (offset, lift) in [(-1, 0.9), (0, 1.5), (1, 0.9)] as [(Float, Float)] {
                drops.append(Drop(lane: rock.lane, height: lift, z: z + offset * RunnerGameTuning.dropSpacing))
            }
        } else if let free = [-1, 0, 1].filter({ !blocked.contains($0) }).randomElement() {
            for k in 0..<5 {
                drops.append(Drop(lane: free, height: 0.35, z: z - 6 + Float(k) * RunnerGameTuning.dropSpacing))
            }
        }
    }

    private func isHitting(_ obstacle: Obstacle) -> Bool {
        let depth: Float = obstacle.kind == .pile ? 0.9 : 0.6
        guard abs(obstacle.z) < depth, abs(Float(obstacle.lane) - laneX) < 0.55 else { return false }
        switch obstacle.kind {
        case .rock: return height < RunnerGameTuning.rockClearHeight
        case .arch: return slideTimer <= 0
        case .pile: return true
        }
    }

    private func collectDrops() {
        let projection = projection
        drops.removeAll { drop in
            guard abs(drop.z) < 0.8, abs(Float(drop.lane) - laneX) < 0.5, abs(drop.height - (height + 0.35)) < 0.9 else { return false }
            dropsCollected += 1
            let p = projection.point(lane: CGFloat(drop.lane), height: CGFloat(drop.height), z: 0)
            spawnParticles(at: SIMD2(Float(p.x), Float(p.y)), count: 5, speed: 40...110)
            pendingWaterPush = (Float(p.x / max(1, size.width)), RunnerGameTuning.dropWaterPush)
            Haptic.ripple.play()
            return true
        }
    }

    private func crash(into obstacle: Obstacle) {
        phase = .dying
        phaseTimer = 0
        let p = projection.point(lane: CGFloat(laneX), height: CGFloat(height) + 0.5, z: 0)
        spawnParticles(at: SIMD2(Float(p.x), Float(p.y)), count: 18, speed: 60...220)
        pendingWaterPush = (Float(p.x / max(1, size.width)), RunnerGameTuning.crashWaterPush)
        Haptic.warning.play()
        onGameOver?(score)
    }

    // MARK: Efeitos

    private func spawnParticles(at point: SIMD2<Float>, count: Int, speed: ClosedRange<Float>) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let lifetime = Float.random(in: 0.4...0.9)
            particles.append(Particle(
                position: point,
                velocity: SIMD2(cos(angle), sin(angle)) * Float.random(in: speed),
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

    func snapshot() -> RunnerGameSnapshot {
        let toTarget = Float(targetLane) - laneX
        // Levanta suave no finzinho do tempo abaixada.
        let crouchAmount = min(1, slideTimer / 0.1)
        return RunnerGameSnapshot(
            projection: projection,
            travelled: CGFloat(travelled),
            playerLane: CGFloat(laneX),
            playerHeight: CGFloat(height),
            playerFacing: abs(toTarget) > 0.05 ? (toTarget > 0 ? 1 : -1) : 0,
            crouch: CGFloat(crouchAmount),
            obstacles: obstacles.map { RunnerGameSnapshot.Obstacle(kind: $0.kind, lane: CGFloat($0.lane), z: CGFloat($0.z), seed: $0.seed) },
            drops: drops.map { RunnerGameSnapshot.Drop(lane: CGFloat($0.lane), height: CGFloat($0.height), z: CGFloat($0.z)) },
            particles: particles.map {
                RunnerGameSnapshot.Particle(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)),
                                            radius: CGFloat($0.radius), alpha: CGFloat($0.life / $0.lifetime))
            },
            score: score,
            phase: phase,
            phaseProgress: phase == .dying ? CGFloat(min(1, phaseTimer / RunnerGameTuning.deathPause)) : 0
        )
    }
}
