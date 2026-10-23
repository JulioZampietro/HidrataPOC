import SwiftUI

/// Valores do jogo das argolas para ajustar à mão (mesma ideia de `WaterTuning`).
enum RingGameTuning {
    static let ringCount = 6
    static let ringRadius: Float = 17            // pt — raio externo da argola vista de frente
    static let ringHoleFraction: Float = 0.55    // furo ÷ raio externo
    static let ringSpawnInterval: Float = 0.18   // s entre uma argola e a próxima caindo na água

    // Física na água
    static let sinkGravity: Float = 150          // pt/s² ao longo de `down` (gravidade efetiva do sensor, a mesma da água) — quase neutra, afunda devagar
    static let wallRestSpeed: Float = 40         // pt/s — abaixo disso a argola para ao encostar na parede, em vez de quicar
    static let wallFriction: Float = 2.5         // 1/s — atrito ao longo da parede/fundo
    static let drag: Float = 2.6                 // 1/s — arrasto da água
    static let wallRestitution: Float = 0.35
    static let ringBounce: Float = 0.6           // quanto da velocidade relativa vira ricochete entre argolas
    static let turbulence: Float = 220           // pt/s² de ruído lateral dentro do jato
    static let wanderStrength: Float = 105       // pt/s² — força típica da deriva horizontal aleatória de cada argola
    static let wanderMemory: Float = 1.6         // 1/s — quão rápido a deriva muda de rumo (maior = mais nervosa)
    static let jetSideKick: Float = 0.25         // × jetForce: empurrão lateral aleatório que cada argola leva ao entrar no jato

    // Jatos (um por botão): sobem do fundo, levemente inclinados pro meio
    static let nozzleInset: Float = 0.16         // fração da largura, a partir de cada parede
    static let jetForce: Float = 1400            // pt/s² no eixo do jato
    static let jetStrengthFree: Float = 0.8      // × força do jato nas argolas soltas
    static let jetStrengthHooked: Float = 0.3    // × força do jato nas argolas enfiadas num pino
    static let jetInwardTilt: Float = 0.4        // componente horizontal ÷ vertical
    // Rajada central: um estouro curto e forte de água, em todas as direções, a partir de um ponto no meio
    static let burstOriginY: Float = 0.97        // fração da altura (de cima pra baixo) onde a rajada nasce — no fundo, onde as argolas se acumulam
    static let burstRadius: Float = 150          // pt — só argolas soltas a até essa distância voam
    static let burstSpeed: Float = 520           // pt/s dados de uma vez à argola mais perto do centro (cai até 0 na borda)
    static let burstLift: Float = 0.7            // inclinação extra pra cima somada à direção radial: as argolas saem em leque, pra cima e pros lados
    static let burstCooldown: Float = 0.5        // s entre duas rajadas
    static let burstFlashDuration: Float = 0.35  // s do clarão desenhado
    static let jetReach: Float = 0.9             // fração da altura que o jato alcança
    static let jetBaseWidth: Float = 30          // pt, meia-largura junto ao bico
    static let jetSpread: Float = 0.22           // alargamento do jato por pt de altura
    static let jetPull: Float = 140              // pt/s² puxando as argolas de perto pro eixo do jato (arrasto da água)
    static let jetPullRange: Float = 0.5         // fração da largura de onde o jato ainda puxa
    static let jetPulseDuration: Float = 0.45    // s de jato quando acionado por VoiceOver
    static let jetMinimumBurst: Float = 0.4      // s: mesmo um toque rápido solta um jatinho, como no brinquedo
    static let jetWaterPush: Float = -9          // impulso na superfície por frame com o jato aberto

    // Ganchos (dois pinos em pé, no fundo)
    static let postInset: Float = 0.34           // fração da largura, a partir de cada parede
    static let postHeight: Float = 0.235         // fração da altura
    static let postHalfWidth: Float = 3
    static let postLift: Float = 40              // pt: os pinos flutuam acima do fundo, deixando as argolas passarem por baixo
    static let stackStep: Float = 11             // pt de uma argola enfiada pra próxima
    static let postCapacity = 6
    static let postCaptureFraction: Float = 0.85 // fração do furo (menos o pino) em que a argola enfia
    static let postAssist: Float = 30            // pt/s² que a água arrastada puxa a argola pra cima de um pino
    static let postAssistRange: Float = 1.1      // alcance horizontal, em raios de argola
    static let postAssistHeight: Float = 110     // pt acima da ponta onde o puxão age
    static let hookSnap: Float = 25              // 1/s — quão rápido a argola enfiada se centra no pino
    static let postJetWidthScale: Float = 1.9    // × largura do jato pra argolas enfiadas (a água que passa perto do pino também as sobe)
    static let stopperRadius: Float = 6          // pt — esfera na base do pino

    // Rodada completa
    static let celebrationDelay: Float = 2.0     // s com tudo enfiado (a última argola assenta) antes do confete e do aviso de recomeçar
    static let releaseKick: Float = 90           // pt/s para os lados ao soltar (nunca pra cima)
}

/// Lado do jato, igual ao botão que o aciona.
enum RingGameSide: Int, CaseIterable {
    case left, right, center
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela, sem tocar no
/// objeto isolado ao main actor.
struct RingGameSnapshot: Sendable {
    struct Ring: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let hole: CGFloat
        let tilt: CGFloat           // rotação no plano da tela
        let openness: CGFloat       // 0…1: quanto a argola "encara" a tela (giro em 3D)
        let colorIndex: Int
        let isHooked: Bool
        let slot: Int
    }

    struct Bubble: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    let rings: [Ring]
    let bubbles: [Bubble]
    let posts: [CGRect]             // pinos, já em coordenadas do recipiente
    let nozzles: [CGPoint]
    let jetsOpen: [Bool]
    let jetHeight: CGFloat
    let burstOrigin: CGPoint
    /// Todas as argolas enfiadas: confete e "Parabéns!" até o próximo toque.
    let isCelebrating: Bool
    let confetti: [Confetto]
    /// Esperando o primeiro toque: as argolas ainda não caíram.
    let isReady: Bool
}

/// Brinquedo de argolas na água: dois botões abrem jatos que empurram as argolas
/// pra cima, e elas caem — às vezes — num dos dois pinos. Física própria em Swift,
/// no mesmo molde de `WaterMotion` (que cuida da água e das pedrinhas): a gravidade
/// efetiva (`down`) vem do mesmo sensor, então inclinar o aparelho também move as
/// argolas, e os jatos agitam a mesma superfície desenhada pelo shader.
@MainActor
final class RingGameSimulation {
    private struct Ring {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float> = .zero
        var phase: Float = 0                 // giro em 3D (só visual)
        var wander: SIMD2<Float> = .zero     // deriva aleatória própria (corrente de água)
        var wasInJet = false
        var spawnDelay: Float
        var hook: (post: Int, slot: Int)?
        let colorIndex: Int
        var isWaiting: Bool { spawnDelay > 0 }
    }

    private struct Bubble {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var radius: Float
        var life: Float
        let lifetime: Float
    }

    private(set) var isRunning = false
    /// Antes do primeiro toque (na água ou num botão) nada se mexe: as argolas só começam a cair depois.
    private(set) var isReady = true
    /// Chamado quando todas as argolas estão enfiadas (uma rodada completa).
    var onRoundComplete: (() -> Void)?

    private var rings: [Ring] = []
    private var bubbles: [Bubble] = []
    private var jetHeld = [Bool](repeating: false, count: RingGameSide.allCases.count)
    private var jetPulse = [Float](repeating: 0, count: RingGameSide.allCases.count)
    private var celebration: Float = 0
    /// Todas as argolas enfiadas: o jogo espera um toque para soltá-las e recomeçar.
    private var isVictory = false
    private var confetti = ConfettiShower()
    private var burstFlash: Float = 0
    private var burstCooldown: Float = 0
    private var lastFrame: Date?
    private var size: CGSize = .zero

    // MARK: Ciclo de vida

    /// Começa uma rodada: as argolas caem na água uma depois da outra.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        isReady = true
        lastFrame = nil
        celebration = 0
        isVictory = false
        confetti.clear()
        bubbles.removeAll()
        rings = (0..<RingGameTuning.ringCount).map { index in
            Ring(position: SIMD2(0, -60), spawnDelay: Float(index) * RingGameTuning.ringSpawnInterval + 0.05, colorIndex: index)
        }
    }

    func stop() {
        isRunning = false
        rings.removeAll()
        bubbles.removeAll()
        confetti.clear()
        isVictory = false
        celebration = 0
        jetHeld = [Bool](repeating: false, count: RingGameSide.allCases.count)
        jetPulse = [Float](repeating: 0, count: RingGameSide.allCases.count)
        lastFrame = nil
    }

    /// Toque na tela de espera: as argolas começam a cair. Depois da vitória, solta as argolas do
    /// pino para uma nova rodada (e só vale quando o aviso de recomeçar já está na tela).
    func begin() {
        if isVictory {
            guard isReady else { return }
            isVictory = false
            confetti.clear()
            releaseRings()
        }
        isReady = false
    }

    func setJet(_ side: RingGameSide, open: Bool) {
        if open { begin() }
        // A rajada central é um estouro único ao apertar; segurar não faz mais nada.
        if side == .center {
            if open { triggerBurst() }
            return
        }
        jetHeld[side.rawValue] = open
        // Toque rápido: o jato continua aberto por um tempo mínimo depois de soltar.
        if open { jetPulse[side.rawValue] = max(jetPulse[side.rawValue], RingGameTuning.jetMinimumBurst) }
    }

    /// Jato curto, para quem aciona o botão sem poder segurá-lo (VoiceOver, Switch Control).
    func pulseJet(_ side: RingGameSide) {
        begin()
        if side == .center { triggerBurst(); return }
        jetPulse[side.rawValue] = RingGameTuning.jetPulseDuration
    }

    // MARK: Geometria (derivada do tamanho do recipiente)

    private func isJetOpen(_ index: Int) -> Bool { jetHeld[index] || jetPulse[index] > 0 }
    private static let jetIndices = 0..<RingGameSide.allCases.count

    /// Para que lado o jato se inclina: esquerdo pro meio (+1), direito pro meio (−1), central reto (0).
    private static func inwardDirection(of jet: Int) -> Float {
        switch RingGameSide(rawValue: jet) {
        case .left: return 1
        case .right: return -1
        default: return 0
        }
    }

    private func nozzleX(_ index: Int) -> Float {
        let width = Float(size.width)
        let inset = RingGameTuning.nozzleInset * width
        switch RingGameSide(rawValue: index) {
        case .left: return inset
        case .right: return width - inset
        default: return width / 2
        }
    }

    private var nozzleY: Float { Float(size.height) - 4 }

    private func postX(_ index: Int) -> Float {
        let width = Float(size.width)
        let inset = RingGameTuning.postInset * width
        return index == 0 ? inset : width - inset
    }

    private var postBaseY: Float { Float(size.height) - 4 - RingGameTuning.postLift }
    private var postTipY: Float { postBaseY - RingGameTuning.postHeight * Float(size.height) }

    // MARK: Simulação

    /// Avança até `date`. `down` é a gravidade efetiva da água; `water` recebe o agito
    /// dos jatos.
    func advance(to date: Date, size: CGSize, down: SIMD2<Float>, water: WaterMotion) {
        let oldHeight = self.size.height
        self.size = size
        // O recipiente estica/encolhe na troca entre o minijogo e a Home: as argolas enfiadas
        // acompanham o pino em vez de ficarem pra trás (ou saírem pela ponta).
        if oldHeight > 0, size.height > 0, oldHeight != size.height { reanchorHookedRings(oldHeight: Float(oldHeight)) }
        guard isRunning, size.width > 0, size.height > 0 else { return }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date
        confetti.update(dt: dt)
        guard !isReady else { return }

        for index in Self.jetIndices { jetPulse[index] = max(0, jetPulse[index] - dt) }
        burstFlash = max(0, burstFlash - dt)
        burstCooldown = max(0, burstCooldown - dt)

        for index in Self.jetIndices where isJetOpen(index) {
            spawnBubbles(from: index)
            water.disturb(atU: nozzleX(index) / Float(size.width), strength: RingGameTuning.jetWaterPush)
        }
        updateBubbles(dt: dt)
        updateRings(dt: dt, down: down)
        resolvePostStacks()
        resolveCollisions()
        updateRound(dt: dt)
    }

    /// Mantém cada argola enfiada à mesma distância da base do pino quando a altura do recipiente
    /// muda (limitada ao comprimento do pino, que também muda, pra ela nunca sair por causa disso).
    private func reanchorHookedRings(oldHeight: Float) {
        let oldBase = oldHeight - 4 - RingGameTuning.postLift
        let maxOffset = postBaseY - postTipY - 3
        for i in rings.indices where rings[i].hook != nil {
            rings[i].position.y = postBaseY - min(max(oldBase - rings[i].position.y, 0), maxOffset)
        }
    }

    private func updateRings(dt: Float, down: SIMD2<Float>) {
        let width = Float(size.width), height = Float(size.height)
        let radius = RingGameTuning.ringRadius
        let hole = radius * RingGameTuning.ringHoleFraction

        for i in rings.indices {
            if rings[i].isWaiting {
                rings[i].spawnDelay -= dt
                guard rings[i].spawnDelay <= 0 else { continue }
                // Entra por cima, num ponto sorteado, já com um pouco de velocidade.
                rings[i].position = SIMD2(Float.random(in: (0.22 * width)...(0.78 * width)), radius)
                rings[i].velocity = SIMD2(Float.random(in: -40...40), 160)
                rings[i].phase = Float.random(in: 0...(2 * .pi))
                continue
            }

            // Argola enfiada: só desliza ao longo do pino (x preso nele), movida pela gravidade
            // efetiva, pelos jatos e pela rajada. Subindo além da ponta, sai do pino; embaixo,
            // para na esfera (`resolvePostStacks`).
            if let hook = rings[i].hook {
                var accelY = down.y * RingGameTuning.sinkGravity
                for jet in Self.jetIndices where isJetOpen(jet) {
                    accelY += jetAcceleration(at: rings[i].position, jet: jet, widthScale: RingGameTuning.postJetWidthScale, strength: RingGameTuning.jetStrengthHooked).y
                }
                rings[i].velocity.y += accelY * dt
                rings[i].velocity.y *= exp(-RingGameTuning.drag * dt)
                rings[i].velocity.x = 0
                rings[i].position.y += rings[i].velocity.y * dt
                rings[i].position.x += (postX(hook.post) - rings[i].position.x) * min(1, RingGameTuning.hookSnap * dt)
                rings[i].phase += 0.6 * dt
                if rings[i].position.y < postTipY - 2 {
                    // Passou da ponta: solta do pino, com um empurrãozinho pro lado.
                    rings[i].hook = nil
                    rings[i].velocity.x = Float.random(in: -30...30)
                }
                continue
            }

            // Deriva: ruído que muda de rumo aos poucos (processo de Ornstein-Uhlenbeck),
            // diferente pra cada argola, sempre perpendicular à gravidade (na tela em pé, é a
            // horizontal) — nada sobe ou desce sozinho; subir é coisa dos jatos.
            let memory = RingGameTuning.wanderMemory
            let kick = RingGameTuning.wanderStrength * (2 * memory).squareRoot()
            rings[i].wander += SIMD2(Float.random(in: -1...1), 0) * (kick * dt.squareRoot())
                - rings[i].wander * (memory * dt)
            // Gravidade de verdade: a mesma direção que inclina a água (`WaterMotion.down`, do
            // giroscópio). Inclinando ou virando o aparelho, as argolas caem pro lado de baixo dele.
            let tangent = SIMD2<Float>(down.y, -down.x)
            var accel = down * RingGameTuning.sinkGravity + tangent * rings[i].wander.x
            var inJet = false
            for jet in Self.jetIndices where isJetOpen(jet) {
                let jetAccel = jetAcceleration(at: rings[i].position, jet: jet, strength: RingGameTuning.jetStrengthFree)
                if jetAccel != .zero { inJet = true }
                accel += jetAccel
            }
            // Ao entrar no jato, cada argola leva um tranco lateral sorteado.
            if inJet, !rings[i].wasInJet {
                rings[i].velocity.x += Float.random(in: -1...1) * RingGameTuning.jetForce * RingGameTuning.jetSideKick * 0.12
                rings[i].wander.x += Float.random(in: -1...1) * RingGameTuning.wanderStrength
            }
            rings[i].wasInJet = inJet
            accel += postAssistAcceleration(at: rings[i].position, velocity: rings[i].velocity)
            rings[i].velocity += accel * dt
            rings[i].velocity *= exp(-RingGameTuning.drag * dt)
            let previousY = rings[i].position.y
            rings[i].position += rings[i].velocity * dt
            rings[i].phase += (Self.length(rings[i].velocity) * 0.02 + 0.6) * dt

            // Paredes: as quatro valem igual (a gravidade pode apontar pra qualquer lado). Bate
            // com pouco ricochete, assenta por atrito e, devagar, para de quicar.
            var p = rings[i].position, v = rings[i].velocity
            let restitution = RingGameTuning.wallRestitution
            let rest = RingGameTuning.wallRestSpeed
            let friction = max(0, 1 - RingGameTuning.wallFriction * dt)
            let bottomLimit = height - radius * 0.5 // o fundo deixa a argola afundar um pouco entre as pedrinhas
            if p.x < radius { p.x = radius; v.x = abs(v.x) > rest ? abs(v.x) * restitution : 0; v.y *= friction }
            if p.x > width - radius { p.x = width - radius; v.x = abs(v.x) > rest ? -abs(v.x) * restitution : 0; v.y *= friction }
            if p.y < radius { p.y = radius; v.y = abs(v.y) > rest ? abs(v.y) * restitution : 0; v.x *= friction }
            if p.y > bottomLimit { p.y = bottomLimit; v.y = abs(v.y) > rest ? -abs(v.y) * restitution : 0; v.x *= friction }

            // Pinos: cruzar a ponta de cima pra baixo, com o pino dentro do furo, enfia; fora
            // disso o pino é uma parede (a argola desliza pra fora).
            var hooked = false
            for post in 0..<2 {
                let dx = p.x - postX(post)
                let slot = rings.filter { $0.hook?.post == post }.count
                if previousY < postTipY, p.y >= postTipY, v.y > 0,
                   abs(dx) < (hole - RingGameTuning.postHalfWidth) * RingGameTuning.postCaptureFraction + 2, slot < RingGameTuning.postCapacity {
                    rings[i].hook = (post, slot)
                    hooked = true
                    break
                }
                if p.y > postTipY + 2, p.y < postBaseY, abs(dx) < radius * 0.9 {
                    p.x = postX(post) + (dx >= 0 ? 1 : -1) * radius * 0.9
                    v.x = (dx >= 0 ? 1 : -1) * max(abs(v.x), 30) * restitution
                }
            }
            rings[i].position = p
            rings[i].velocity = hooked ? SIMD2(0, v.y * 0.6) : v
        }
    }

    /// Ajuda de jogabilidade: uma argola que está caindo logo acima de um pino é levada
    /// de leve pela água pra cima dele — sem isso, acertar um furo de poucos pontos é sorte demais.
    private func postAssistAcceleration(at position: SIMD2<Float>, velocity: SIMD2<Float>) -> SIMD2<Float> {
        guard velocity.y > 0 else { return .zero }
        let heightAbove = postTipY - position.y
        guard heightAbove > 0, heightAbove < RingGameTuning.postAssistHeight else { return .zero }
        let range = RingGameTuning.postAssistRange * RingGameTuning.ringRadius
        var best = SIMD2<Float>.zero
        var bestOffset = range
        for post in 0..<2 {
            let dx = postX(post) - position.x
            if abs(dx) < bestOffset {
                bestOffset = abs(dx)
                best = SIMD2(dx >= 0 ? 1 : -1, 0) * (RingGameTuning.postAssist * min(1, abs(dx) / 6))
            }
        }
        return best
    }

    private var burstOrigin: SIMD2<Float> {
        SIMD2(Float(size.width) / 2, RingGameTuning.burstOriginY * Float(size.height))
    }

    /// Rajada central: um impulso único em todas as argolas soltas perto do ponto de origem, pra
    /// longe dele e em qualquer direção. Argolas enfiadas também sentem a rajada, mas só deslizam pelo pino. A parte
    /// que a rajada tem de subida é limitada, então ela abre as argolas em leque em vez de lançá-las nos pinos.
    private func triggerBurst() {
        guard isRunning, size.width > 0, burstCooldown <= 0 else { return }
        burstCooldown = RingGameTuning.burstCooldown
        burstFlash = RingGameTuning.burstFlashDuration

        for i in rings.indices where !rings[i].isWaiting {
            let delta = rings[i].position - burstOrigin
            let distance = Self.length(delta)
            guard distance < RingGameTuning.burstRadius else { continue }
            // Bem no centro não há direção: sorteia uma. Um pouco de desvio em cada argola.
            var direction = distance > 1 ? delta / distance : SIMD2(Float.random(in: -1...1), Float.random(in: -1...1))
            direction = Self.rotate(direction, by: Float.random(in: -0.25...0.25))
            direction.y -= RingGameTuning.burstLift
            direction /= max(Self.length(direction), 0.001)
            let falloff = 1 - distance / RingGameTuning.burstRadius
            rings[i].velocity += direction * (RingGameTuning.burstSpeed * falloff * Float.random(in: 0.85...1.15))
            rings[i].wander.x += Float.random(in: -1...1) * RingGameTuning.wanderStrength
        }

        // Bolhas saindo do ponto em todas as direções.
        for _ in 0..<36 {
            let angle = Float.random(in: 0...(2 * .pi))
            let lifetime = Float.random(in: 0.3...0.6)
            bubbles.append(Bubble(
                position: burstOrigin + SIMD2(cos(angle), sin(angle)) * Float.random(in: 0...12),
                velocity: SIMD2(cos(angle), sin(angle)) * Float.random(in: 160...420),
                radius: Float.random(in: 1.4...3.6),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        if bubbles.count > 160 { bubbles.removeFirst(bubbles.count - 160) }
    }

    /// `widthScale` alarga o núcleo do jato: uma argola enfiada num pino também sobe com a água que passa perto.
    private func jetAcceleration(at position: SIMD2<Float>, jet: Int, widthScale: Float = 1, strength: Float = 1) -> SIMD2<Float> {
        let height = Float(size.height)
        let above = nozzleY - position.y
        let reach = RingGameTuning.jetReach * height
        guard above > -8, above < reach else { return .zero }
        let inward = Self.inwardDirection(of: jet)
        let halfWidth = (RingGameTuning.jetBaseWidth + max(above, 0) * RingGameTuning.jetSpread) * widthScale
        // O eixo do jato anda pra dentro conforme sobe.
        let axisX = nozzleX(jet) + inward * max(above, 0) * RingGameTuning.jetInwardTilt
        let offset = abs(position.x - axisX)
        // Fora do núcleo do jato, a água arrastada ainda traz a argola pra perto dele.
        let pullRange = RingGameTuning.jetPullRange * Float(size.width)
        let pull = offset < pullRange ? (1 - offset / pullRange) * RingGameTuning.jetPull : 0
        let pullAcceleration = SIMD2<Float>(position.x < axisX ? pull : -pull, 0)
        guard offset < halfWidth else { return pullAcceleration }
        let falloff = (1 - offset / halfWidth) * (1 - max(above, 0) / reach)
        let direction = SIMD2<Float>(inward * RingGameTuning.jetInwardTilt, -1)
        let noise = Float.random(in: -1...1) * RingGameTuning.turbulence
        return (direction * (RingGameTuning.jetForce * falloff) + SIMD2(noise * falloff, 0)) * strength + pullAcceleration
    }

    /// Argolas enfiadas no mesmo pino empilham: a de baixo pára na esfera da base, cada uma
    /// empurra a de cima, e nenhuma atravessa a outra. `slot` passa a ser a ordem de baixo pra cima.
    private func resolvePostStacks() {
        let step = RingGameTuning.stackStep
        for post in 0..<2 {
            let stack = rings.indices.filter { rings[$0].hook?.post == post }.sorted { rings[$0].position.y > rings[$1].position.y }
            var previousY = postBaseY - step / 2 - 2 + step // chão = esfera da base
            var previousVelocity: Float = 0
            for (slot, index) in stack.enumerated() {
                let limit = previousY - step
                if rings[index].position.y > limit {
                    rings[index].position.y = limit
                    rings[index].velocity.y = min(rings[index].velocity.y, previousVelocity)
                }
                rings[index].hook = (post, slot)
                previousY = rings[index].position.y
                previousVelocity = rings[index].velocity.y
            }
        }
    }

    /// Argolas livres se empurram (círculos); as enfiadas não participam.
    private func resolveCollisions() {
        let minDistance = RingGameTuning.ringRadius * 1.5
        for i in rings.indices where rings[i].hook == nil && !rings[i].isWaiting {
            for j in rings.indices where j > i && rings[j].hook == nil && !rings[j].isWaiting {
                let delta = rings[j].position - rings[i].position
                let distance = Self.length(delta)
                guard distance > 1e-3, distance < minDistance else { continue }
                let normal = delta / distance
                let overlap = minDistance - distance
                rings[i].position -= normal * (overlap * 0.5)
                rings[j].position += normal * (overlap * 0.5)
                let closing = Self.dot(rings[j].velocity - rings[i].velocity, normal)
                if closing < 0 {
                    let impulse = normal * (closing * RingGameTuning.ringBounce)
                    rings[i].velocity += impulse
                    rings[j].velocity -= impulse
                }
            }
        }
    }

    private func updateRound(dt: Float) {
        if isVictory {
            // Deixa a última argola assentar; depois solta o confete, congela e mostra o aviso de recomeçar.
            if celebration > 0 {
                celebration -= dt
                if celebration <= 0 {
                    confetti.burst(in: size, colorCount: RingGameTuning.ringCount)
                    isReady = true
                }
            }
            return
        }
        guard !rings.isEmpty, rings.allSatisfy({ $0.hook != nil }) else { return }
        isVictory = true
        celebration = RingGameTuning.celebrationDelay
        onRoundComplete?()
    }

    /// Toque depois da comemoração: as argolas se soltam do pino e caem, pra uma nova rodada.
    private func releaseRings() {
        for i in rings.indices {
            rings[i].hook = nil
            rings[i].velocity = SIMD2(Float.random(in: -RingGameTuning.releaseKick...RingGameTuning.releaseKick), 0)
        }
    }

    // MARK: Bolhas dos jatos

    private func spawnBubbles(from jet: Int) {
        let inward = Self.inwardDirection(of: jet)
        for _ in 0..<2 {
            let lifetime = Float.random(in: 0.45...0.9)
            bubbles.append(Bubble(
                position: SIMD2(nozzleX(jet) + Float.random(in: -6...6), nozzleY),
                velocity: SIMD2(inward * RingGameTuning.jetInwardTilt * 320 + Float.random(in: -25...25), -Float.random(in: 260...420)),
                radius: Float.random(in: 1.4...3.4),
                life: lifetime,
                lifetime: lifetime
            ))
        }
        if bubbles.count > 160 { bubbles.removeFirst(bubbles.count - 160) }
    }

    private func updateBubbles(dt: Float) {
        for i in bubbles.indices {
            bubbles[i].life -= dt
            bubbles[i].velocity *= exp(-1.2 * dt)
            bubbles[i].position += bubbles[i].velocity * dt
        }
        bubbles.removeAll { $0.life <= 0 }
    }

    // MARK: Foto pra desenhar

    func snapshot() -> RingGameSnapshot {
        let radius = CGFloat(RingGameTuning.ringRadius)
        let posts = (0..<2).map { index in
            CGRect(x: CGFloat(postX(index) - RingGameTuning.postHalfWidth), y: CGFloat(postTipY),
                   width: CGFloat(RingGameTuning.postHalfWidth * 2), height: CGFloat(postBaseY - postTipY))
        }
        let ringSnapshots: [RingGameSnapshot.Ring] = rings.compactMap { ring in
            guard !ring.isWaiting else { return nil }
            let hooked = ring.hook != nil
            return RingGameSnapshot.Ring(
                position: CGPoint(x: CGFloat(ring.position.x), y: CGFloat(ring.position.y)),
                radius: radius,
                hole: radius * CGFloat(RingGameTuning.ringHoleFraction),
                tilt: hooked ? 0 : CGFloat(max(-0.5, min(0.5, ring.velocity.x * 0.003))),
                openness: hooked ? 0.42 : CGFloat(0.4 + 0.25 * abs(cos(ring.phase))),
                colorIndex: ring.colorIndex,
                isHooked: hooked,
                slot: ring.hook?.slot ?? 0
            )
        }
        return RingGameSnapshot(
            rings: ringSnapshots,
            bubbles: bubbles.map {
                RingGameSnapshot.Bubble(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)),
                                        radius: CGFloat($0.radius), alpha: CGFloat($0.life / $0.lifetime) * 0.6)
            },
            posts: posts,
            nozzles: Self.jetIndices.map { CGPoint(x: CGFloat(nozzleX($0)), y: CGFloat(nozzleY)) },
            jetsOpen: Self.jetIndices.map { RingGameSide(rawValue: $0) == .center ? burstFlash > 0 : isJetOpen($0) },
            jetHeight: CGFloat(RingGameTuning.jetReach) * size.height,
            burstOrigin: CGPoint(x: CGFloat(burstOrigin.x), y: CGFloat(burstOrigin.y)),
            isCelebrating: isVictory,
            confetti: confetti.snapshot(),
            isReady: isReady
        )
    }

    private static func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a * b).sum() }
    private static func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }
    private static func rotate(_ v: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle), s = sin(angle)
        return SIMD2(v.x * c - v.y * s, v.x * s + v.y * c)
    }
}
