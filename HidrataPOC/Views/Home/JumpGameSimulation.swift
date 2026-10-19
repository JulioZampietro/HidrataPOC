import SwiftUI

/// Valores do jogo da Gota Saltitante para ajustar à mão (mesma ideia de `RingGameTuning`).
enum JumpGameTuning {
    // Gota
    static let dropRadius: Float = 13            // pt
    static let gravity: Float = 1050             // pt/s² — na água, um pouco mais "boiante" que no ar
    static let jumpSpeed: Float = 640            // pt/s pra cima a cada quique numa folha (sobe ~195 pt)
    static let springSpeed: Float = 1000         // pt/s pra cima numa folha com mola (bolha)
    static let moveSpeed: Float = 320            // pt/s de lado com o botão apertado
    static let moveResponse: Float = 12          // 1/s — quão rápido a gota pega/perde velocidade lateral
    static let tiltGain: Float = 520             // pt/s por unidade de inclinação (`down.x`) — inclinar o aparelho também move
    static let tiltDeadZone: Float = 0.08        // inclinação ignorada (aparelho quase em pé)

    // Folhas (plataformas)
    static let leafWidth: Float = 58
    static let leafHeight: Float = 10
    static let leafGapMin: Float = 62            // pt entre uma folha e a próxima acima
    static let leafGapMax: Float = 118           // não passar de ~0.6 × altura do pulo, senão fica impossível
    static let movingChance: Float = 0.22        // chance de a folha andar de lado (cresce com a altura)
    static let fragileChance: Float = 0.12       // chance de a folha rasgar ao pisar (só pula uma vez)
    static let springChance: Float = 0.07        // chance de ter uma bolha-mola em cima
    static let movingSpeed: Float = 60           // pt/s
    static let difficultyHeight: Float = 6000    // pt subidos até as chances acima chegarem ao máximo (×2)

    // Escala: as medidas acima valem pra um aquário de `referenceHeight` pt; em aquários mais
    // baixos (ou mais altos) o pulo e o espaço entre folhas encolhem (ou crescem) junto, pra
    // folha de onde a gota saiu e o topo do pulo caberem sempre na tela.
    static let referenceHeight: Float = 360
    static let minScale: Float = 0.6
    static let maxScale: Float = 1.4

    // Câmera e pontuação
    static let landedLeafMargin: Float = 30      // pt acima do fundo da tela onde a câmera deixa a última folha pisada
    static let cameraFollow: Float = 6           // 1/s — quão rápido a câmera sobe até essa folha
    static let cameraTopLine: Float = 0.3        // fração da altura: a gota nunca passa disso pra cima (ex.: na bolha-mola)
    static let pointsPerPt: Float = 0.1          // pontos por pt subido
    static let gameOverPause: Float = 1.3        // s mostrando "fim de jogo" antes de recomeçar
    static let bounceWaterPush: Float = 6        // agito na superfície a cada quique
}

/// Para que lado a gota está sendo empurrada pelos botões.
enum JumpGameSide: Int, CaseIterable {
    case left, right
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct JumpGameSnapshot: Sendable {
    enum LeafKind: Sendable { case normal, moving, fragile }

    struct Leaf: Sendable {
        let rect: CGRect
        let kind: LeafKind
        let isTorn: Bool
        let hasSpring: Bool
        /// Semente do formato da pedra (ver `PebbleDrawing`).
        let seed: Int
    }

    struct Bubble: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    let drop: CGPoint
    let dropRadius: CGFloat
    let squash: CGFloat             // > 1 = achatada (acabou de quicar)
    let facing: CGFloat             // −1 esquerda, 1 direita
    let leaves: [Leaf]
    let bubbles: [Bubble]
    let score: Int
    let isGameOver: Bool
}

/// Doodle Jump dentro do aquário: uma gota quica sozinha de folha em folha, e os botões
/// (ou inclinar o aparelho) a levam pros lados. A câmera sobe junto quando ela passa da
/// linha `cameraLine`; cair abaixo do fundo da tela é fim de jogo, e uma nova partida
/// começa sozinha logo depois. Física própria em Swift, no mesmo molde de `RingGameSimulation`.
@MainActor
final class JumpGameSimulation {
    private struct Leaf {
        var position: SIMD2<Float>      // centro do topo da folha, em coordenadas do mundo (y pra baixo)
        let kind: JumpGameSnapshot.LeafKind
        var direction: Float = 1
        var isTorn = false
        var tornFall: Float = 0
        let hasSpring: Bool
        /// Formato da pedra: sorteado uma vez, então a plataforma não muda de cara ao andar.
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
    /// Pontos da partida atual (altura máxima subida).
    private(set) var score = 0
    /// Chamado quando a gota cai — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    private var drop: SIMD2<Float> = .zero
    private var velocity: SIMD2<Float> = .zero
    private var facing: Float = 1
    private var squash: Float = 0
    private var leaves: [Leaf] = []
    private var bubbles: [Bubble] = []
    private var held = [Bool](repeating: false, count: JumpGameSide.allCases.count)
    private var pulse = [Float](repeating: 0, count: JumpGameSide.allCases.count)
    /// Topo da tela em coordenadas do mundo (diminui conforme a câmera sobe).
    private var cameraY: Float = 0
    private var startY: Float = 0
    /// Topo da última folha em que a gota quicou: a câmera sobe até deixá-la perto do fundo
    /// da tela, então a folha de onde ela saiu nunca some do quadro.
    private var landedLeafY: Float = 0
    private var highestLeafY: Float = 0
    private var gameOverTimer: Float = 0
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
        leaves.removeAll()
        bubbles.removeAll()
        held = [Bool](repeating: false, count: JumpGameSide.allCases.count)
        pulse = [Float](repeating: 0, count: JumpGameSide.allCases.count)
        score = 0
        lastFrame = nil
    }

    func setDirection(_ side: JumpGameSide, held isHeld: Bool) {
        held[side.rawValue] = isHeld
    }

    /// Empurrão curto, pra quem aciona o botão sem segurar (VoiceOver, toque rápido).
    func pulseDirection(_ side: JumpGameSide) {
        pulse[side.rawValue] = 0.25
    }

    /// Nova partida: a gota começa parada em cima de uma folha larga no fundo.
    private func reset() {
        let width = Float(size.width), height = Float(size.height)
        needsReset = false
        cameraY = 0
        score = 0
        gameOverTimer = 0
        bubbles.removeAll()
        let floorY = height - 24
        startY = floorY
        leaves = [Leaf(position: SIMD2(width / 2, floorY), kind: .normal, hasSpring: false)]
        highestLeafY = floorY
        landedLeafY = floorY
        drop = SIMD2(width / 2, floorY - JumpGameTuning.dropRadius)
        velocity = SIMD2(0, -JumpGameTuning.jumpSpeed * scale)
        generateLeaves()
    }

    // MARK: Simulação

    /// Avança até `date`. `down` é a gravidade do sensor (inclinar o aparelho move a gota);
    /// `water` recebe o agito de cada quique.
    func advance(to date: Date, size: CGSize, down: SIMD2<Float>, water: WaterMotion) {
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        if needsReset { reset() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        for i in pulse.indices { pulse[i] = max(0, pulse[i] - dt) }
        updateBubbles(dt: dt)
        updateLeaves(dt: dt)

        if gameOverTimer > 0 {
            gameOverTimer -= dt
            if gameOverTimer <= 0 { reset() }
            return
        }

        updateDrop(dt: dt, down: down, water: water)
        updateCamera(dt: dt)
        generateLeaves()

        // Caiu abaixo do fundo: fim de jogo.
        if drop.y - cameraY > Float(size.height) + JumpGameTuning.dropRadius * 2 {
            gameOverTimer = JumpGameTuning.gameOverPause
            onGameOver?(score)
        }
    }

    private func inputDirection(down: SIMD2<Float>) -> Float {
        var direction: Float = 0
        if held[JumpGameSide.left.rawValue] || pulse[JumpGameSide.left.rawValue] > 0 { direction -= 1 }
        if held[JumpGameSide.right.rawValue] || pulse[JumpGameSide.right.rawValue] > 0 { direction += 1 }
        var target = direction * JumpGameTuning.moveSpeed
        // Inclinar o aparelho pro lado também leva a gota (como no Doodle Jump original).
        let tilt = down.x
        if abs(tilt) > JumpGameTuning.tiltDeadZone {
            target += (tilt - (tilt > 0 ? 1 : -1) * JumpGameTuning.tiltDeadZone) * JumpGameTuning.tiltGain
        }
        return max(-JumpGameTuning.moveSpeed * 1.4, min(JumpGameTuning.moveSpeed * 1.4, target))
    }

    private func updateDrop(dt: Float, down: SIMD2<Float>, water: WaterMotion) {
        let width = Float(size.width)
        let radius = JumpGameTuning.dropRadius
        let targetVX = inputDirection(down: down)
        velocity.x += (targetVX - velocity.x) * min(1, JumpGameTuning.moveResponse * dt)
        if abs(velocity.x) > 20 { facing = velocity.x > 0 ? 1 : -1 }
        velocity.y += JumpGameTuning.gravity * scale * dt
        squash = max(0, squash - dt * 5)

        let previousBottom = drop.y + radius
        drop += velocity * dt

        // Sai por um lado, entra pelo outro.
        if drop.x < -radius { drop.x += width + radius * 2 }
        if drop.x > width + radius { drop.x -= width + radius * 2 }

        // Quique: só caindo, com o pé cruzando o topo de uma folha.
        guard velocity.y > 0 else { return }
        let bottom = drop.y + radius
        let halfLeaf = JumpGameTuning.leafWidth / 2
        let screenBottom = cameraY + Float(size.height)
        for i in leaves.indices where !leaves[i].isTorn {
            let top = leaves[i].position.y
            // Só quica em folha que está à vista: abaixo do fundo da tela já é queda.
            guard top < screenBottom - 4, previousBottom <= top + 2, bottom >= top,
                  abs(drop.x - leaves[i].position.x) < halfLeaf + radius * 0.6 else { continue }
            drop.y = top - radius
            let onSpring = leaves[i].hasSpring && abs(drop.x - leaves[i].position.x) < halfLeaf * 0.6
            velocity.y = -(onSpring ? JumpGameTuning.springSpeed : JumpGameTuning.jumpSpeed) * scale
            landedLeafY = top
            squash = onSpring ? 1 : 0.7
            if leaves[i].kind == .fragile { leaves[i].isTorn = true }
            spawnSplash(at: SIMD2(drop.x, top), count: onSpring ? 18 : 8)
            water.disturb(atU: drop.x / width, strength: JumpGameTuning.bounceWaterPush * (onSpring ? 2 : 1))
            (onSpring ? Haptic.primary : Haptic.ripple).play()
            break
        }
    }

    /// A câmera só sobe. Ela vai suavemente até a última folha pisada ficar a
    /// `landedLeafMargin` do fundo — com o pulo escalado (`scale`), o topo do pulo cabe
    /// acima dela — e, se a gota subir além de `cameraTopLine` (bolha-mola), acompanha a gota.
    private func updateCamera(dt: Float) {
        let height = Float(size.height)
        let leafTarget = landedLeafY - (height - JumpGameTuning.landedLeafMargin)
        if leafTarget < cameraY { cameraY += (leafTarget - cameraY) * min(1, JumpGameTuning.cameraFollow * dt) }
        let dropTarget = drop.y - JumpGameTuning.cameraTopLine * height
        if dropTarget < cameraY { cameraY = dropTarget }
        score = max(score, Int((startY - drop.y) * JumpGameTuning.pointsPerPt))
    }

    private func updateLeaves(dt: Float) {
        let width = Float(size.width)
        let halfLeaf = JumpGameTuning.leafWidth / 2
        for i in leaves.indices {
            if leaves[i].isTorn {
                leaves[i].tornFall += dt
                leaves[i].position.y += 260 * dt
                continue
            }
            guard leaves[i].kind == .moving else { continue }
            leaves[i].position.x += leaves[i].direction * JumpGameTuning.movingSpeed * dt
            if leaves[i].position.x < halfLeaf { leaves[i].position.x = halfLeaf; leaves[i].direction = 1 }
            if leaves[i].position.x > width - halfLeaf { leaves[i].position.x = width - halfLeaf; leaves[i].direction = -1 }
        }
        // Folhas que já saíram por baixo da tela (ou rasgaram e caíram) somem.
        let bottom = cameraY + Float(size.height) + 40
        leaves.removeAll { $0.position.y > bottom || $0.tornFall > 1.2 }
    }

    /// Cria folhas acima do topo da tela, até uma tela e meia de folga.
    private func generateLeaves() {
        let width = Float(size.width)
        let halfLeaf = JumpGameTuning.leafWidth / 2
        let limit = cameraY - Float(size.height) * 0.5
        while highestLeafY > limit {
            let climbed = startY - highestLeafY
            let difficulty = 1 + min(1, climbed / JumpGameTuning.difficultyHeight)
            highestLeafY -= Float.random(in: JumpGameTuning.leafGapMin...JumpGameTuning.leafGapMax) * scale
            let roll = Float.random(in: 0...1)
            let kind: JumpGameSnapshot.LeafKind
            if roll < JumpGameTuning.fragileChance * difficulty {
                kind = .fragile
            } else if roll < (JumpGameTuning.fragileChance + JumpGameTuning.movingChance) * difficulty {
                kind = .moving
            } else {
                kind = .normal
            }
            leaves.append(Leaf(
                position: SIMD2(Float.random(in: halfLeaf...(width - halfLeaf)), highestLeafY),
                kind: kind,
                direction: Bool.random() ? 1 : -1,
                hasSpring: kind == .normal && Float.random(in: 0...1) < JumpGameTuning.springChance
            ))
            // Uma folha que rasga nunca pode ser a única saída: põe uma firme por perto.
            if kind == .fragile {
                highestLeafY -= Float.random(in: 10...30) * scale
                leaves.append(Leaf(
                    position: SIMD2(Float.random(in: halfLeaf...(width - halfLeaf)), highestLeafY),
                    kind: .normal,
                    hasSpring: false
                ))
            }
        }
    }

    /// Quanto o pulo e o espaço entre folhas encolhem/crescem pra caber no aquário.
    private var scale: Float {
        max(JumpGameTuning.minScale, min(JumpGameTuning.maxScale, Float(size.height) / JumpGameTuning.referenceHeight))
    }

    // MARK: Bolhas

    private func spawnSplash(at point: SIMD2<Float>, count: Int) {
        for _ in 0..<count {
            let angle = Float.random(in: (.pi * 0.15)...(.pi * 0.85))
            let lifetime = Float.random(in: 0.3...0.6)
            bubbles.append(Bubble(
                position: point,
                velocity: SIMD2(cos(angle) * Float.random(in: -1...1) * 160, sin(angle) * 120),
                radius: Float.random(in: 1.2...3),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        if bubbles.count > 120 { bubbles.removeFirst(bubbles.count - 120) }
    }

    private func updateBubbles(dt: Float) {
        for i in bubbles.indices {
            bubbles[i].life -= dt
            bubbles[i].velocity *= exp(-2 * dt)
            bubbles[i].velocity.y -= 120 * dt // bolha sobe
            bubbles[i].position += bubbles[i].velocity * dt
        }
        bubbles.removeAll { $0.life <= 0 }
    }

    // MARK: Foto pra desenhar

    func snapshot() -> JumpGameSnapshot {
        let w = CGFloat(JumpGameTuning.leafWidth), h = CGFloat(JumpGameTuning.leafHeight)
        let offset = CGFloat(cameraY)
        return JumpGameSnapshot(
            drop: CGPoint(x: CGFloat(drop.x), y: CGFloat(drop.y) - offset),
            dropRadius: CGFloat(JumpGameTuning.dropRadius),
            squash: CGFloat(squash),
            facing: CGFloat(facing),
            leaves: leaves.map { leaf in
                JumpGameSnapshot.Leaf(
                    rect: CGRect(x: CGFloat(leaf.position.x) - w / 2, y: CGFloat(leaf.position.y) - offset, width: w, height: h),
                    kind: leaf.kind,
                    isTorn: leaf.isTorn,
                    hasSpring: leaf.hasSpring,
                    seed: leaf.seed
                )
            },
            bubbles: bubbles.map {
                JumpGameSnapshot.Bubble(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y) - offset),
                                        radius: CGFloat($0.radius), alpha: CGFloat($0.life / $0.lifetime) * 0.7)
            },
            score: score,
            isGameOver: gameOverTimer > 0
        )
    }
}
