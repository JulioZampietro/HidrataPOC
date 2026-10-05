import CoreMotion
import SwiftUI

/// Valores da simulação da água para ajustar à mão. Os do visual (ondas capilares,
/// brilhos, bolhas…) ficam no topo de `Bubble.metal`.
enum WaterTuning {
    // Balanço (equação de onda)
    static let columns = 96                  // resolução do campo de alturas
    static let waveSpeed: Float = 520        // pt/s — período do balanço ≈ 2·largura/c (antigo: 420)
    static let damping: Float = 0.6          // 1/s — menor = balança mais e demora a assentar (antigo: 1.6)
    static let viscosity: Float = 60         // pt²/s — só apaga as ondulações mais finas do campo
    static let tiltResponse: Float = 0.6     // fração da inclinação que vira onda (1 = física plena)
    static let maxTiltSpeed: Float = 4.2     // rad/s — máximo que o referencial da água pode girar por
                                              // segundo. Sem isso, quando o sensor perde a referência
                                              // (aparelho quase na horizontal) e reaparece já virado pro
                                              // lado oposto, a água "teleporta" pra inclinação nova no
                                              // mesmo frame. Com o limite, ela varre os ângulos
                                              // intermediários — um giro de 180° leva ~0,75 s, como
                                              // virar uma garrafa de ponta-cabeça, não um corte seco.
    static let heaveGain: Float = 120        // pt/s por g de variação da gravidade
    static let maxDisplacement: Float = 75   // pt

    // Bolhas (`fizz`: 0 = repouso, 1 = logo após sacudida forte)
    static let fizzDecay: Float = 1.8        // s — quanto tempo as bolhas da sacudida levam para rarear
    static let fizzFromAgitation: Float = 0.35 // bolhas extras só pelo balanço (sem sacudida forte)
    static let fizzPerShake: Float = 0.6     // bolhas por g de sacudida forte

    // Sacudida forte → gotas
    static let shakeThreshold: Float = 0.7   // g de aceleração do aparelho (ou tranco) para soltar gotas (antes: 1.2)
    static let jerkWeight: Float = 0.5       // peso do tranco (variação brusca) frente à aceleração
    static let shakeCooldown: Double = 0.12  // s entre rajadas
    static let dropsPerBurst: Float = 3      // gotas numa sacudida bem no limiar
    static let dropsPerG: Float = 7          // gotas extras por g acima do limiar
    static let maxDroplets = 32              // máximo de gotas no ar (igual a `kMaxDrops` em Bubble.metal)

    // Física das gotas
    static let dropGravity: Float = 1800     // pt/s² ao longo de `down`
    static let dropDrag: Float = 0.35        // 1/s de arrasto…
    static let dropDragSmall: Float = 0.6    // …mais este / raio (as pequenas freiam mais)
    static let dropLaunchSpeed: Float = 320  // pt/s de saída numa sacudida no limiar
    static let dropSpeedPerG: Float = 180    // pt/s extras por g acima do limiar
    static let dropInertiaKick: Float = 160  // pt/s por g: a água é jogada para o lado oposto à aceleração
    static let dropSpread: Float = 0.5       // rad de dispersão em volta de "para cima"
    static let dropMinRadius: Float = 1      // pt
    static let dropMaxRadius: Float = 5      // pt (poucas chegam perto disso)
    static let dropSizeBias: Float = 2.6     // maior = mais gotas pequenas
    static let dropSplitRadius: Float = 3.2  // gotas maiores que isso podem se partir no ar
    static let dropSplitChance: Float = 2.5  // chance por segundo de partir (para as grandes)
    static let dropLife: Float = 2.5         // s até sumir, se não voltar para a água antes
    static let dropWallRestitution: Float = 0.25 // quanto da velocidade sobra ao bater na parede
    static let dropWallFade: Float = 0.35    // s para sumir depois de encostar na parede
    static let dropStretch: Float = 0.0009   // alongamento por pt/s de velocidade
    static let dropMaxStretch: Float = 0.45  // alongamento máximo (0.45 = 45% mais comprida)

    // Gota voltando para a água
    static let impactGain: Float = 0.012     // impulso no campo por pt² · (pt/s) de impacto
    static let impactDent: Float = 0.5       // afundamento local (× raio, em pt)
    static let crownSpeed: Float = 380       // pt/s de impacto a partir do qual respinga em coroa

    // Interações externas (arrastar o mascote empurra a água)
    static let dragPushGain: Float = 2.4     // impulso no campo por pt de deslocamento do arrasto
    static let maxDragPush: Float = 260      // pt/s — limite do impulso de um único arrasto
    static let dragPushWidth: Float = 7      // colunas — largura (sigma) do empurrão em torno do ponto
}

extension Notification.Name {
    /// Simula uma sacudida forte na água (disparado pelo Device ▸ Shake do Simulator).
    static let waterDebugShake = Notification.Name("waterDebugShake")
}

#if targetEnvironment(simulator)
extension UIWindow {
    // O Simulator não tem CoreMotion: o Device ▸ Shake (⌃⌘Z) vira uma sacudida forte simulada.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .waterDebugShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

extension View {
    /// Coloca o conteúdo dentro de um "recipiente" de água transparente (shader `water`
    /// em `Bubble.metal`): a água sobe conforme `level` (0…1), acompanha o giroscópio e
    /// passa por trás e por cima do conteúdo, que fica parecendo mergulhado.
    /// `bleedsIntoTopSafeArea` estende o recipiente por baixo da status bar.
    /// `motion`, quando informado, substitui a simulação interna — assim quem chama
    /// (por exemplo, um gesto de arrastar fora do recipiente) pode perturbar a mesma
    /// água que está sendo desenhada aqui.
    func waterContainer<S: Shape>(level: Double, in shape: S, bleedsIntoTopSafeArea: Bool = false, motion: WaterMotion? = nil) -> some View {
        modifier(WaterContainerModifier(level: level, shape: shape, bleedsIntoTopSafeArea: bleedsIntoTopSafeArea, externalMotion: motion))
    }
}

private struct WaterContainerModifier<S: Shape>: ViewModifier {
    let level: Double
    let shape: S
    let bleedsIntoTopSafeArea: Bool
    var externalMotion: WaterMotion?

    @State private var internalMotion = WaterMotion()

    private var motion: WaterMotion { externalMotion ?? internalMotion }

    func body(content: Content) -> some View {
        WaterRefractionView(level: level, motion: motion, content: content)
            .animation(.easeInOut(duration: 1.2), value: level)
            .background(alignment: .bottom) {
                WaterFillView(level: level, layer: .body, motion: motion, bleedsIntoTopSafeArea: bleedsIntoTopSafeArea)
                    .animation(.easeInOut(duration: 1.2), value: level)
            }
            .overlay {
                WaterFillView(level: level, layer: .front, motion: motion, bleedsIntoTopSafeArea: bleedsIntoTopSafeArea)
                    .animation(.easeInOut(duration: 1.2), value: level)
            }
            .clipShape(shape)
            .onAppear { motion.start() }
            .onDisappear { motion.stop() }
            .onReceive(NotificationCenter.default.publisher(for: .waterDebugShake)) { _ in
                motion.simulateShake()
            }
    }
}

/// O conteúdo do recipiente visto através da água: abaixo da superfície ele ondula e
/// ganha uma tintura no azul de destaque (`waterRefraction` em `Bubble.metal`). Usa a mesma simulação
/// e o mesmo nível animado da água desenhada, para a linha d'água coincidir.
private struct WaterRefractionView<Content: View>: View, @preconcurrency Animatable {
    var level: Double
    let motion: WaterMotion
    let content: Content

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let time = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            // Valores copiados aqui porque o closure do visualEffect é @Sendable.
            let waterSize = motion.waterSize
            let down = CGPoint(x: CGFloat(motion.down.x), y: CGFloat(motion.down.y))
            let agitation = motion.agitation
            let field = motion.field
            let level = Float(min(max(level, 0), 1))

            content.visualEffect { view, proxy in
                // Antes do primeiro frame a água ainda não mediu o recipiente.
                let size = waterSize.width > 0 ? waterSize : proxy.size
                // O recipiente pode se estender sob a status bar: o conteúdo fica no
                // canto inferior do retângulo da água.
                let origin = CGPoint(x: 0, y: max(0, size.height - proxy.size.height))
                return view.layerEffect(
                    ShaderLibrary.waterRefraction(
                        .float2(size),
                        .float2(origin),
                        .float(time),
                        .float(level),
                        .float2(down),
                        .float(agitation),
                        .floatArray(field),
                        .float2(proxy.size)
                    ),
                    // Cobre o maior deslocamento da refração (`kRefractMax` em Bubble.metal).
                    maxSampleOffset: CGSize(width: 10, height: 10)
                )
            }
        }
    }
}

/// Água desenhada pelo shader `water` (`Bubble.metal`). O nível é animável: quando
/// `level` muda dentro de uma animação, o SwiftUI chama o body a cada frame com o
/// valor interpolado e o shader acompanha a subida/descida.
struct WaterFillView: View, @preconcurrency Animatable {
    enum Layer: Float { case body = 0, front = 1 }

    var level: Double
    let layer: Layer
    let motion: WaterMotion
    var bleedsIntoTopSafeArea = false

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let time = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (a segunda camada cai em dt≈0).
                let level = Float(min(max(level, 0), 1))
                let _ = motion.advance(to: context.date, size: geo.size, level: level)
                Rectangle()
                    .fill(Color.white) // conteúdo de base; o shader ignora essa cor
                    .colorEffect(
                        ShaderLibrary.water(
                            .float2(geo.size),
                            .float(time),
                            .float(level),
                            .float2(CGPoint(x: CGFloat(motion.down.x), y: CGFloat(motion.down.y))),
                            .float(motion.agitation),
                            .float(motion.fizz),
                            .float(layer.rawValue),
                            .floatArray(motion.field),
                            .floatArray(motion.dropletData)
                        )
                    )
            }
            .ignoresSafeArea(edges: bleedsIntoTopSafeArea ? .top : [])
        }
        .allowsHitTesting(false)
    }
}

/// Simulação de líquido em 1D, alimentada pelo CoreMotion.
///
/// A superfície é um campo de alturas (`field`, em pontos, positivo = mais fundo)
/// que obedece à equação de onda da água rasa: as ondas se propagam, batem nas
/// paredes e voltam, perdem energia devagar, e o volume de água se conserva.
///
/// O celular entra assim: a "gravidade efetiva" é a gravidade menos a aceleração
/// do aparelho (a água fica para trás quando você o empurra). O referencial da
/// água gira com essa gravidade; como a água em si não gira junto, cada variação
/// de ângulo deixa a superfície inclinada em relação ao novo referencial
/// (`field += dθ · x`). A equação de onda então a devolve ao equilíbrio, com
/// overshoot, respingos e reflexos — o movimento de um líquido de verdade,
/// não de uma mola. Mudanças de intensidade da gravidade (aceleração vertical)
/// empurram o meio da massa de água para cima/baixo.
///
/// Sacudidas fortes (aceleração ou tranco acima de `WaterTuning.shakeThreshold`)
/// soltam gotas: partículas simuladas aqui e desenhadas pelo shader (`dropletData`).
/// Elas nascem nas cristas, voam contra a gravidade, podem se partir, perdem energia
/// nas paredes e, ao voltar para a água, afundam a superfície no ponto do impacto.
///
/// Sem sensor (Simulator) fica na vertical, só com as ondas ambiente do shader; o
/// Device ▸ Shake do Simulator chama `simulateShake()`.
@MainActor
final class WaterMotion {
    static let columns = WaterTuning.columns

    /// Deslocamento da superfície (pt) de parede a parede, no referencial da água.
    private(set) var field = [Float](repeating: 0, count: WaterMotion.columns)
    private(set) var agitation: Float = 0
    /// Quantidade de bolhas no corpo da água (0 = repouso, ~1 = logo após sacudida forte).
    private(set) var fizz: Float = 0
    /// Gotas para o shader: [minX, minY, maxX, maxY] (área que as contém, com folga)
    /// seguido de 6 floats por gota: x, y, raio, opacidade, alongamento (x, y).
    private(set) var dropletData: [Float] = WaterMotion.noDroplets
    /// Tamanho do recipiente na última medição (inclui a extensão sob a status bar).
    private(set) var waterSize: CGSize = .zero
    /// Vetor unitário "para baixo" em coordenadas de tela (y para baixo).
    var down: SIMD2<Float> { SIMD2(sin(angle), cos(angle)) }

    private static let noDroplets: [Float] = [0, 0, -1, -1]

    private struct Droplet {
        var position: SIMD2<Float>   // pt, no retângulo da água (y para baixo)
        var velocity: SIMD2<Float>   // pt/s
        var radius: Float            // pt
        var canSplit: Bool
        var age: Float = 0           // s
        var fade: Float = 1          // cai até 0 depois de encostar numa parede
        var touchedWall = false
    }

    /// Referencial da superfície no frame atual (mesmas contas de `waterGeometry` no shader).
    private struct SurfaceFrame {
        let n: SIMD2<Float>          // para baixo
        let t: SIMD2<Float>          // ao longo da superfície
        let center: SIMD2<Float>
        let length: Float            // comprimento da superfície de parede a parede
        let baseH: Float             // profundidade da superfície em repouso
    }

    private var velocity = [Float](repeating: 0, count: WaterMotion.columns)
    private var viscousScratch = [Float](repeating: 0, count: WaterMotion.columns)
    private var droplets: [Droplet] = []
    private var level: Float = 0
    private var angle: Float = 0
    private var sensorAngle: Float = 0
    private var sensorMagnitude: Float = 1
    private var smoothedMagnitude: Float = 1
    private var lastUserAcceleration = SIMD3<Float>(repeating: 0)
    private var lastBurstTimestamp: TimeInterval = -.infinity
    /// Sacudida forte ainda não transformada em gotas: g acima do limiar, direção para
    /// onde a água é jogada (em g, na tela) e atraso até soltar as gotas.
    private var pendingShake: Float?
    private var pendingInertia = SIMD2<Float>(repeating: 0)
    private var pendingShakeDelay: Float = 0
    private var lastFrame: Date?
    private let manager = CMMotionManager()

    private let followRate: Float = 25        // 1/s — suavização mínima do sensor

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.receive(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lastFrame = nil
        droplets.removeAll()
        dropletData = Self.noDroplets
        pendingShake = nil
    }

    /// Sacudida forte sem aparelho (Simulator ▸ Device ▸ Shake): joga a água para um lado,
    /// como o balanço de uma sacudida faria, e solta as gotas quando a onda sobe na parede.
    func simulateShake(strength: Float = 1.6) {
        let side: Float = Bool.random() ? 1 : -1
        let count = Self.columns
        for i in 0..<count {
            let u = Float(i) / Float(count - 1) - 0.5
            velocity[i] += strength * (side * 250 * u + 60 * sin(5 * .pi * u))
        }
        queueShake(strength: strength, inertia: SIMD2(side * 1.2, -0.3), delay: 0.15)
    }

    /// Empurra a superfície perto de `u` (0...1, de parede a parede) — usado por
    /// interações externas ao shader, como arrastar o mascote dentro da água.
    /// `strength` > 0 afunda a superfície (empurra para baixo); < 0 levanta.
    func disturb(atU u: Float, strength: Float) {
        let count = Self.columns
        let clamped = max(-WaterTuning.maxDragPush, min(WaterTuning.maxDragPush, strength))
        guard abs(clamped) > 0.01 else { return }
        let x = min(max(u, 0), 1) * Float(count - 1)
        let sigma = WaterTuning.dragPushWidth
        let lower = max(0, Int((x - 3 * sigma).rounded(.down)))
        let upper = min(count - 1, Int((x + 3 * sigma).rounded(.up)))
        guard lower <= upper else { return }
        for j in lower...upper {
            let offset = Float(j) - x
            let weight = exp(-offset * offset / (2 * sigma * sigma))
            velocity[j] += clamped * weight
        }
    }

    private func receive(_ motion: CMDeviceMotion) {
        // CoreMotion: x para a direita, y para cima. Tela: y para baixo.
        // Gravidade efetiva = gravidade − aceleração do aparelho.
        let ex = Float(motion.gravity.x - motion.userAcceleration.x)
        let ey = Float(-motion.gravity.y + motion.userAcceleration.y)
        let magnitude = (ex * ex + ey * ey).squareRoot()
        // Celular quase deitado: a gravidade sai do plano da tela, mantém a última direção.
        if magnitude > 0.2 {
            sensorAngle = atan2(ex, ey)
            sensorMagnitude = min(magnitude, 2)
        }

        // Sacudida forte: aceleração do aparelho alta, ou uma variação brusca dela (tranco).
        // Mexidas suaves ficam abaixo do limiar e geram só ondas.
        let user = SIMD3<Float>(Float(motion.userAcceleration.x), Float(motion.userAcceleration.y), Float(motion.userAcceleration.z))
        let jerk = Self.length(user - lastUserAcceleration)
        lastUserAcceleration = user
        let strength = max(Self.length(user), WaterTuning.jerkWeight * jerk)
        if strength > WaterTuning.shakeThreshold,
           motion.timestamp - lastBurstTimestamp > WaterTuning.shakeCooldown {
            lastBurstTimestamp = motion.timestamp
            // A água fica para trás: é jogada para o lado oposto à aceleração (tela: y para baixo).
            queueShake(strength: strength - WaterTuning.shakeThreshold,
                       inertia: SIMD2(-user.x, user.y), delay: 0)
        }
    }

    private func queueShake(strength: Float, inertia: SIMD2<Float>, delay: Float) {
        if let pending = pendingShake, pending >= strength { return }
        pendingShake = strength
        pendingInertia = inertia
        pendingShakeDelay = delay
    }

    /// Avança a simulação até `date`. `size` é o tamanho do recipiente em pontos e
    /// `level` o nível de água desenhado neste frame (0…1).
    func advance(to date: Date, size: CGSize, level: Float) {
        waterSize = size
        self.level = level
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        let count = Self.columns
        let width = Float(size.width), height = Float(size.height)

        // 1. Referencial da água gira com a gravidade; a superfície fica para trás.
        var diff = sensorAngle - angle
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        let desired = diff * min(1, dt * followRate)
        let maxAngleStep = WaterTuning.maxTiltSpeed * dt
        let dAngle = max(-maxAngleStep, min(maxAngleStep, desired))
        angle += dAngle
        let surfaceLength = abs(cos(angle)) * width + abs(sin(angle)) * height
        for i in 0..<count {
            let u = Float(i) / Float(count - 1) - 0.5
            // Rampa da inclinação com uma pitada de modos mais altos: a onda que sai daí
            // é em "S" e não uma reta, como num balanço de verdade.
            let ramp = u * surfaceLength
                + 0.10 * surfaceLength * sin(3 * .pi * u)
                + 0.03 * surfaceLength * sin(7 * .pi * u)
            field[i] += dAngle * ramp * WaterTuning.tiltResponse
        }

        // 2. Gravidade mais forte/fraca: o meio da massa sobe ou desce.
        let dMagnitude = sensorMagnitude - smoothedMagnitude
        smoothedMagnitude += dMagnitude * min(1, dt * 10)
        for i in 0..<count {
            let u = Float(i) / Float(count - 1)
            velocity[i] -= dMagnitude * WaterTuning.heaveGain * cos(2 * .pi * u)
        }

        // Gotas: soltam numa sacudida forte, voam e, ao cair, empurram a superfície
        // (antes da equação de onda, que espalha o impacto em ondulações).
        let frame = surfaceFrame(width: width, height: height)
        if let strength = pendingShake {
            pendingShakeDelay -= dt
            if pendingShakeDelay <= 0 {
                pendingShake = nil
                fizz = min(1.2, fizz + WaterTuning.fizzPerShake * (0.5 + strength))
                spawnBurst(strength: strength, inertia: pendingInertia, frame: frame, width: width, height: height)
            }
        }
        updateDroplets(dt: dt, frame: frame, width: width, height: height)

        // 3. Equação de onda (leapfrog). O amortecimento uniforme é baixo, para o balanço
        //    ter overshoot e assentar aos poucos; a viscosidade (laplaciano da velocidade)
        //    age quase só nas ondulações mais finas, que somem rápido como na água de verdade.
        //    Passos de no máximo 1/240 s e metade do limite de estabilidade (CFL).
        let dx = max(width, 1) / Float(count - 1)
        let maxStep = min(1.0 / 240.0, 0.5 * dx / WaterTuning.waveSpeed)
        let steps = max(1, Int((dt / maxStep).rounded(.up)))
        let h = dt / Float(steps)
        let k = WaterTuning.waveSpeed * WaterTuning.waveSpeed / (dx * dx)
        let nu = WaterTuning.viscosity / (dx * dx)
        for _ in 0..<steps {
            for i in 0..<count {
                viscousScratch[i] = velocity[max(i - 1, 0)] - 2 * velocity[i] + velocity[min(i + 1, count - 1)]
            }
            for i in 0..<count {
                let left = field[max(i - 1, 0)]
                let right = field[min(i + 1, count - 1)]
                let laplacian = left - 2 * field[i] + right
                velocity[i] += (k * laplacian + nu * viscousScratch[i] - WaterTuning.damping * velocity[i]) * h
            }
            for i in 0..<count {
                field[i] += velocity[i] * h
            }
        }

        // 4. Volume conservado: a média do deslocamento é sempre zero.
        let mean = field.reduce(0, +) / Float(count)
        var energy: Float = 0
        for i in 0..<count {
            field[i] = min(max(field[i] - mean, -WaterTuning.maxDisplacement), WaterTuning.maxDisplacement)
            energy += velocity[i] * velocity[i]
        }
        let target = min((energy / Float(count)).squareRoot() / 200, 1.0)
        agitation += (target - agitation) * min(1, dt * 4)
        fizz = max(fizz * exp(-dt / WaterTuning.fizzDecay), WaterTuning.fizzFromAgitation * agitation)

        dropletData = packDroplets()
    }

    // MARK: - Gotas

    private func surfaceFrame(width: Float, height: Float) -> SurfaceFrame {
        let n = down
        let t = SIMD2(n.y, -n.x)
        let length = abs(t.x) * width + abs(t.y) * height
        // Mesma margem (20 pt) e mesmo mapeamento do nível que `waterGeometry` no shader.
        let halfExtent = 0.5 * (abs(n.x) * width + abs(n.y) * height) + 20
        return SurfaceFrame(n: n, t: t, center: SIMD2(width / 2, height / 2),
                            length: max(length, 1), baseH: halfExtent * (1 - 2 * level))
    }

    /// Deslocamento da superfície em `u` (0…1, de parede a parede), interpolado.
    private func fieldValue(at u: Float) -> Float {
        let x = min(max(u, 0), 1) * Float(Self.columns - 1)
        let i0 = Int(x)
        let i1 = min(i0 + 1, Self.columns - 1)
        return field[i0] + (field[i1] - field[i0]) * (x - Float(i0))
    }

    private func columnIndex(at u: Float) -> Int {
        min(max(Int((u * Float(Self.columns - 1)).rounded()), 0), Self.columns - 1)
    }

    private func surfacePoint(at u: Float, frame: SurfaceFrame) -> SIMD2<Float> {
        frame.center + frame.t * ((u - 0.5) * frame.length) + frame.n * (frame.baseH + fieldValue(at: u))
    }

    /// Distância à superfície (> 0 dentro da água) e posição `u` ao longo dela.
    private func depth(of p: SIMD2<Float>, frame: SurfaceFrame) -> (d: Float, u: Float) {
        let rel = p - frame.center
        let u = Self.dot(rel, frame.t) / frame.length + 0.5
        return (Self.dot(rel, frame.n) - (frame.baseH + fieldValue(at: u)), u)
    }

    private func spawnBurst(strength: Float, inertia: SIMD2<Float>, frame: SurfaceFrame, width: Float, height: Float) {
        let wanted = Int((WaterTuning.dropsPerBurst + strength * WaterTuning.dropsPerG).rounded())
        let amount = min(wanted, WaterTuning.maxDroplets - droplets.count)
        guard amount > 0 else { return }
        let up = -frame.n
        let count = Self.columns

        for _ in 0..<amount {
            // Entre alguns pontos sorteados, fica o mais propício: crista (superfície mais
            // alta), onda íngreme ou superfície subindo rápido.
            var bestU: Float = 0.5
            var bestScore = -Float.infinity
            for _ in 0..<5 {
                let u = Float.random(in: 0.03...0.97)
                let i = min(max(columnIndex(at: u), 1), count - 2)
                let score = max(0, -field[i]) * 0.05
                    + abs(field[i + 1] - field[i - 1]) * 0.15
                    + max(0, -velocity[i]) * 0.004
                    + Float.random(in: 0...0.3)
                if score > bestScore { bestScore = score; bestU = u }
            }

            let radius = WaterTuning.dropMinRadius
                + (WaterTuning.dropMaxRadius - WaterTuning.dropMinRadius) * pow(Float.random(in: 0...1), WaterTuning.dropSizeBias)
            let position = surfacePoint(at: bestU, frame: frame) + up * (radius + 1)
            // Superfície fora do retângulo (água inclinada ou quase cheia): não há onde voar.
            guard position.x > radius, position.x < width - radius,
                  position.y > radius, position.y < height - radius else { continue }

            let speed = (WaterTuning.dropLaunchSpeed + strength * WaterTuning.dropSpeedPerG) * Float.random(in: 0.65...1.2)
            var v = Self.rotate(up, by: Float.random(in: -WaterTuning.dropSpread...WaterTuning.dropSpread)) * speed
            v += inertia * (WaterTuning.dropInertiaKick * Float.random(in: 0.5...1))
            v += up * (max(0, -velocity[columnIndex(at: bestU)]) * 0.8)
            // Sempre sai da água, por mais forte que seja o empurrão lateral.
            let outward = Self.dot(v, up)
            if outward < 0.4 * speed { v += up * (0.4 * speed - outward) }

            droplets.append(Droplet(position: position, velocity: v, radius: radius, canSplit: true))
        }
    }

    private func updateDroplets(dt: Float, frame: SurfaceFrame, width: Float, height: Float) {
        guard !droplets.isEmpty else { return }
        let gravity = frame.n * WaterTuning.dropGravity
        var spawned: [Droplet] = []
        var index = 0

        while index < droplets.count {
            var drop = droplets[index]
            drop.age += dt
            drop.velocity += gravity * dt
            drop.velocity *= exp(-(WaterTuning.dropDrag + WaterTuning.dropDragSmall / drop.radius) * dt)
            drop.position += drop.velocity * dt

            // Paredes: quica pouco, perde o deslize e some aos poucos.
            let r = drop.radius
            let restitution = WaterTuning.dropWallRestitution
            if drop.position.x < r {
                drop.position.x = r
                drop.velocity.x = abs(drop.velocity.x) * restitution
                drop.velocity.y *= 0.5
                drop.touchedWall = true
            } else if drop.position.x > width - r {
                drop.position.x = width - r
                drop.velocity.x = -abs(drop.velocity.x) * restitution
                drop.velocity.y *= 0.5
                drop.touchedWall = true
            }
            if drop.position.y < r {
                drop.position.y = r
                drop.velocity.y = abs(drop.velocity.y) * restitution
                drop.velocity.x *= 0.5
                drop.touchedWall = true
            }
            if drop.touchedWall { drop.fade -= dt / WaterTuning.dropWallFade }

            // Gotas grandes podem se partir em duas no ar (mesmo volume: raio × 0,79).
            if drop.canSplit, drop.radius > WaterTuning.dropSplitRadius, drop.age > 0.06,
               droplets.count + spawned.count < WaterTuning.maxDroplets,
               Float.random(in: 0...1) < WaterTuning.dropSplitChance * dt {
                let speed = max(Self.length(drop.velocity), 1)
                let side = SIMD2(-drop.velocity.y, drop.velocity.x) / speed * Float.random(in: 30...70)
                drop.radius *= 0.794
                var twin = drop
                twin.velocity -= side
                drop.velocity += side
                spawned.append(twin)
            }

            // Voltou para a água: some e deixa a marca do impacto na superfície.
            let (d, u) = depth(of: drop.position, frame: frame)
            let speedIn = Self.dot(drop.velocity, frame.n)
            if drop.age > 0.05, speedIn > 0, d > -0.3 * drop.radius {
                splash(drop, at: u, speedIn: speedIn, frame: frame, width: width, into: &spawned)
                droplets.remove(at: index)
                continue
            }
            if drop.fade <= 0 || drop.age > WaterTuning.dropLife {
                droplets.remove(at: index)
                continue
            }
            droplets[index] = drop
            index += 1
        }

        droplets.append(contentsOf: spawned.prefix(max(0, WaterTuning.maxDroplets - droplets.count)))
    }

    /// Impacto de uma gota: pequena depressão e impulso para baixo no campo (a equação
    /// de onda transforma isso em ondulação), e, se for rápida, uma ou duas gotinhas
    /// de volta para cima (coroa).
    private func splash(_ drop: Droplet, at u: Float, speedIn: Float, frame: SurfaceFrame,
                        width: Float, into spawned: inout [Droplet]) {
        let count = Self.columns
        let x = min(max(u, 0), 1) * Float(count - 1)
        let cellWidth = max(width, 1) / Float(count - 1)
        let sigma = max(0.8, drop.radius / cellWidth)
        let push = WaterTuning.impactGain * drop.radius * drop.radius * speedIn
        let dent = WaterTuning.impactDent * drop.radius
        let lower = max(0, Int((x - 3 * sigma).rounded(.down)))
        let upper = min(count - 1, Int((x + 3 * sigma).rounded(.up)))
        if lower <= upper {
            for j in lower...upper {
                let offset = Float(j) - x
                let weight = exp(-offset * offset / (2 * sigma * sigma))
                velocity[j] += push * weight
                field[j] += dent * weight
            }
        }
        fizz = min(1.2, fizz + 0.02 * drop.radius)

        guard speedIn > WaterTuning.crownSpeed, drop.radius > 1.6 else { return }
        let up = -frame.n
        let sides: [Float] = speedIn > 1.6 * WaterTuning.crownSpeed ? [-1, 1] : [Bool.random() ? -1 : 1]
        let origin = surfacePoint(at: u, frame: frame)
        for side in sides where droplets.count + spawned.count < WaterTuning.maxDroplets {
            let radius = max(0.8, drop.radius * Float.random(in: 0.3...0.45))
            let v = up * (speedIn * Float.random(in: 0.25...0.4)) + frame.t * (side * Float.random(in: 50...110))
            spawned.append(Droplet(position: origin + up * (radius + 1), velocity: v, radius: radius, canSplit: false))
        }
    }

    private func packDroplets() -> [Float] {
        guard !droplets.isEmpty else { return Self.noDroplets }
        var data: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude,
                             -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        data.reserveCapacity(4 + droplets.count * 6)
        let life = WaterTuning.dropLife
        for drop in droplets {
            let fadeIn = min(1, drop.age / 0.04)
            let fadeOut = 1 - min(max((drop.age - (life - 0.4)) / 0.4, 0), 1)
            let alpha = fadeIn * fadeOut * max(0, drop.fade)
            // Gotas rápidas ficam levemente alongadas na direção da velocidade.
            let speed = Self.length(drop.velocity)
            let stretchAmount = min(speed * WaterTuning.dropStretch, WaterTuning.dropMaxStretch)
            let stretch = speed > 1 ? drop.velocity / speed * stretchAmount : SIMD2<Float>(repeating: 0)
            data += [drop.position.x, drop.position.y, drop.radius, alpha, stretch.x, stretch.y]
            // Folga: alongamento, aro e a sombra deslocada da camada de trás.
            let reach = drop.radius * (1 + stretchAmount) + 6
            data[0] = min(data[0], drop.position.x - reach)
            data[1] = min(data[1], drop.position.y - reach)
            data[2] = max(data[2], drop.position.x + reach)
            data[3] = max(data[3], drop.position.y + reach)
        }
        return data
    }

    private static func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a * b).sum() }
    private static func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }
    private static func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
    private static func rotate(_ v: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle), s = sin(angle)
        return SIMD2(v.x * c - v.y * s, v.x * s + v.y * c)
    }
}
