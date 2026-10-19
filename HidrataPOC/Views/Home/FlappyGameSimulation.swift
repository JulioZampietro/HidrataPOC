import SwiftUI

/// Valores da Gota Voadora para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum FlappyGameTuning {
    // Gota
    static let dropRadius: Float = 12            // pt
    static let dropXFraction: Float = 0.3        // posição fixa da gota, em fração da largura
    static let gravity: Float = 1250             // pt/s²
    static let flapSpeed: Float = 400            // pt/s pra cima a cada toque
    static let maxFallSpeed: Float = 560         // pt/s
    static let flapCooldown: Float = 0.08        // s — o toque rápido no botão também manda um pulso
    static let hitForgiveness: Float = 0.75      // fração do raio que conta na batida (as pedras são irregulares)

    // Colunas de pedras
    static let columnWidth: Float = 44           // pt
    static let columnSpacing: Float = 200        // pt entre uma coluna e a próxima
    static let gapFraction: Float = 0.28         // vão, em fração da altura do aquário, no começo…
    static let minGapFraction: Float = 0.21      // …e o menor que ele fica com a pontuação alta
    static let minGap: Float = 105               // pt — nunca menor que isso, mesmo em aquário baixo
    static let gapTopMargin: Float = 70          // pt — o vão não encosta nos botões do cabeçalho
    static let gapBottomMargin: Float = 30       // pt
    static let scrollSpeed: Float = 140          // pt/s no começo…
    static let maxScrollSpeed: Float = 220       // …e no máximo
    static let difficultyScore = 40              // pontos até o vão e a velocidade chegarem ao limite

    static let gameOverPause: Float = 1.3        // s mostrando "fim de jogo" antes de voltar ao início
    static let flapWaterPush: Float = 3          // agito na superfície a cada braçada
    static let burstWaterPush: Float = 8         // agito na superfície quando a gota explode
    static let burstDroplets = 18                // gotinhas que voam quando ela bate
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct FlappyGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, gameOver }

    struct Column: Sendable {
        let x: CGFloat          // centro da coluna
        let width: CGFloat
        let gapTop: CGFloat
        let gapBottom: CGFloat
        let seed: Int
    }

    struct Bubble: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    /// A gota sempre de pé (ponta pra cima); some quando explode, no `gameOver`.
    let drop: CGPoint
    let dropRadius: CGFloat
    let columns: [Column]
    let bubbles: [Bubble]
    /// Gotinhas da explosão, voando pra fora e caindo.
    let droplets: [Bubble]
    let score: Int
    let phase: Phase
}

/// Flappy Bird dentro do aquário: a gota fica parada na horizontal enquanto colunas de pedras
/// vêm da direita; a água a puxa pra baixo e cada toque (no aquário ou no botão) a faz nadar pra
/// cima. Passar pelo vão de uma coluna vale um ponto; bater numa pedra ou no fundo é fim de jogo.
/// A partida começa no primeiro toque e, depois do fim, volta a esperar o próximo. Física própria
/// em Swift, no mesmo molde de `JumpGameSimulation`.
@MainActor
final class FlappyGameSimulation {
    private struct Column {
        var x: Float
        let gapCenter: Float
        let gap: Float
        var scored = false
        let seed = Int.random(in: 0..<1_000_000)
    }

    private struct Bubble {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var radius: Float
        var life: Float
        let lifetime: Float
    }

    private(set) var isRunning = false
    /// Pontos da partida atual (colunas passadas).
    private(set) var score = 0
    /// Chamado quando a gota bate — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    private var phase: FlappyGameSnapshot.Phase = .ready
    private var dropY: Float = 0
    private var velocity: Float = 0
    private var columns: [Column] = []
    private var bubbles: [Bubble] = []
    /// Gotinhas da explosão (mesma estrutura das bolhas, mas caem em vez de subir).
    private var droplets: [Bubble] = []
    /// Explosão que ainda não agitou a água (o próximo frame agita, como `pendingSplash`).
    private var pendingBurst = false
    private var flapCooldown: Float = 0
    /// Braçada que ainda não agitou a água (o `flap()` não tem a `WaterMotion`; o próximo frame agita).
    private var pendingSplash = false
    private var gameOverTimer: Float = 0
    /// Relógio da espera antes do primeiro toque (a gota boia pra cima e pra baixo).
    private var idleTime: Float = 0
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
        columns.removeAll()
        bubbles.removeAll()
        droplets.removeAll()
        score = 0
        lastFrame = nil
    }

    /// Braçada pra cima. Na tela de espera, também começa a partida.
    func flap() {
        guard isRunning, !needsReset, flapCooldown <= 0 else { return }
        switch phase {
        case .gameOver:
            return
        case .ready:
            phase = .playing
        case .playing:
            break
        }
        velocity = -FlappyGameTuning.flapSpeed
        flapCooldown = FlappyGameTuning.flapCooldown
        pendingSplash = true
        spawnTrail()
        Haptic.tap.play()
    }

    /// Volta pra tela de espera: gota no meio, sem colunas.
    private func reset() {
        needsReset = false
        phase = .ready
        score = 0
        dropY = Float(size.height) * 0.45
        velocity = 0
        idleTime = 0
        gameOverTimer = 0
        columns.removeAll()
        bubbles.removeAll()
        droplets.removeAll()
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito de cada braçada.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        let resized = size != self.size
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        if needsReset { reset() }
        // O aquário estica e encolhe entre a tela do jogo e a de ingestão: a gota não pode
        // ficar fora da água nova.
        if resized { dropY = min(dropY, Float(size.height) - FlappyGameTuning.dropRadius) }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        flapCooldown = max(0, flapCooldown - dt)
        updateBubbles(dt: dt)
        updateDroplets(dt: dt)
        if pendingSplash {
            pendingSplash = false
            water.disturb(atU: dropX / Float(size.width), strength: FlappyGameTuning.flapWaterPush)
        }
        if pendingBurst {
            pendingBurst = false
            water.disturb(atU: dropX / Float(size.width), strength: FlappyGameTuning.burstWaterPush)
        }

        switch phase {
        case .ready:
            idleTime += dt
            dropY = Float(size.height) * 0.45 + sin(idleTime * 3) * 6
        case .playing:
            updateDrop(dt: dt)
            updateColumns(dt: dt)
            checkCollisions()
        case .gameOver:
            // A gota já explodiu: só as gotinhas voam enquanto o "fim de jogo" aparece.
            gameOverTimer -= dt
            if gameOverTimer <= 0 { reset() }
        }
    }

    private var dropX: Float { Float(size.width) * FlappyGameTuning.dropXFraction }

    /// 0 no começo, 1 com `difficultyScore` pontos.
    private var difficulty: Float { min(1, Float(score) / Float(FlappyGameTuning.difficultyScore)) }

    private func updateDrop(dt: Float) {
        velocity = min(velocity + FlappyGameTuning.gravity * dt, FlappyGameTuning.maxFallSpeed)
        dropY += velocity * dt
        // O teto não mata: a gota só para nele.
        let radius = FlappyGameTuning.dropRadius
        if dropY < radius * 2 {
            dropY = radius * 2
            velocity = max(velocity, 0)
        }
    }

    private func updateColumns(dt: Float) {
        let speed = FlappyGameTuning.scrollSpeed + (FlappyGameTuning.maxScrollSpeed - FlappyGameTuning.scrollSpeed) * difficulty
        for i in columns.indices {
            columns[i].x -= speed * dt
            if !columns[i].scored, columns[i].x + FlappyGameTuning.columnWidth / 2 < dropX - FlappyGameTuning.dropRadius {
                columns[i].scored = true
                score += 1
                Haptic.ripple.play()
            }
        }
        columns.removeAll { $0.x < -FlappyGameTuning.columnWidth }

        // Coluna nova logo fora da tela, à direita, quando a última já andou `columnSpacing`.
        let spawnX = Float(size.width) + FlappyGameTuning.columnWidth
        if let last = columns.last {
            if last.x <= spawnX - FlappyGameTuning.columnSpacing {
                columns.append(makeColumn(at: last.x + FlappyGameTuning.columnSpacing))
            }
        } else {
            columns.append(makeColumn(at: spawnX))
        }
    }

    private func makeColumn(at x: Float) -> Column {
        let height = Float(size.height)
        let fraction = FlappyGameTuning.gapFraction + (FlappyGameTuning.minGapFraction - FlappyGameTuning.gapFraction) * difficulty
        let gap = max(FlappyGameTuning.minGap, height * fraction)
        let low = FlappyGameTuning.gapTopMargin + gap / 2
        let high = max(low, height - FlappyGameTuning.gapBottomMargin - gap / 2)
        return Column(x: x, gapCenter: Float.random(in: low...high), gap: gap)
    }

    private func checkCollisions() {
        let radius = FlappyGameTuning.dropRadius * FlappyGameTuning.hitForgiveness
        let hitsColumn = columns.contains { column in
            abs(column.x - dropX) < FlappyGameTuning.columnWidth / 2 + radius
                && (dropY - radius < column.gapCenter - column.gap / 2 || dropY + radius > column.gapCenter + column.gap / 2)
        }
        let hitsFloor = dropY + FlappyGameTuning.dropRadius >= Float(size.height)
        guard hitsColumn || hitsFloor else { return }
        phase = .gameOver
        gameOverTimer = FlappyGameTuning.gameOverPause
        velocity = 0
        spawnBurst()
        onGameOver?(score)
    }

    // MARK: Bolhas

    /// Bolhinhas saindo de trás da gota a cada braçada.
    private func spawnTrail(count: Int = 6) {
        for _ in 0..<count {
            let lifetime = Float.random(in: 0.35...0.7)
            bubbles.append(Bubble(
                position: SIMD2(dropX - FlappyGameTuning.dropRadius * 0.6, dropY + FlappyGameTuning.dropRadius * 0.3),
                velocity: SIMD2(Float.random(in: -140 ... -40), Float.random(in: 20...110)),
                radius: Float.random(in: 1.2...3),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        if bubbles.count > 120 { bubbles.removeFirst(bubbles.count - 120) }
    }

    /// A gota explode: gotinhas voam pra todo lado (mais pra cima) e caem, com bolhas no meio.
    private func spawnBurst() {
        let center = SIMD2(dropX, dropY - FlappyGameTuning.dropRadius * 0.4)
        for i in 0..<FlappyGameTuning.burstDroplets {
            let angle = Float(i) / Float(FlappyGameTuning.burstDroplets) * 2 * .pi + Float.random(in: -0.2...0.2)
            let speed = Float.random(in: 120...320)
            let lifetime = Float.random(in: 0.6...1.1)
            droplets.append(Bubble(
                position: center,
                velocity: SIMD2(cos(angle) * speed, sin(angle) * speed - 120),
                radius: Float.random(in: 2.5...5),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        spawnTrail(count: 12)
        pendingBurst = true
    }

    private func updateDroplets(dt: Float) {
        for i in droplets.indices {
            droplets[i].life -= dt
            droplets[i].velocity *= exp(-1.2 * dt)
            droplets[i].velocity.y += 700 * dt // cai, ao contrário das bolhas
            droplets[i].position += droplets[i].velocity * dt
        }
        droplets.removeAll { $0.life <= 0 }
    }

    private func updateBubbles(dt: Float) {
        for i in bubbles.indices {
            bubbles[i].life -= dt
            bubbles[i].velocity *= exp(-2.5 * dt)
            bubbles[i].velocity.y -= 140 * dt // bolha sobe
            bubbles[i].position += bubbles[i].velocity * dt
        }
        bubbles.removeAll { $0.life <= 0 }
    }

    // MARK: Foto pra desenhar

    func snapshot() -> FlappyGameSnapshot {
        func bubble(_ b: Bubble, alpha: Float) -> FlappyGameSnapshot.Bubble {
            FlappyGameSnapshot.Bubble(position: CGPoint(x: CGFloat(b.position.x), y: CGFloat(b.position.y)),
                                      radius: CGFloat(b.radius), alpha: CGFloat(b.life / b.lifetime * alpha))
        }
        return FlappyGameSnapshot(
            drop: CGPoint(x: CGFloat(dropX), y: CGFloat(dropY)),
            dropRadius: CGFloat(FlappyGameTuning.dropRadius),
            columns: columns.map {
                FlappyGameSnapshot.Column(
                    x: CGFloat($0.x),
                    width: CGFloat(FlappyGameTuning.columnWidth),
                    gapTop: CGFloat($0.gapCenter - $0.gap / 2),
                    gapBottom: CGFloat($0.gapCenter + $0.gap / 2),
                    seed: $0.seed
                )
            },
            bubbles: bubbles.map { bubble($0, alpha: 0.7) },
            droplets: droplets.map { bubble($0, alpha: 1) },
            score: score,
            phase: phase
        )
    }
}
