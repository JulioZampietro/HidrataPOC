import CoreMotion
import SwiftUI

extension View {
    /// Coloca o conteúdo dentro de um "recipiente" de água transparente (shader `water`
    /// em `Bubble.metal`): a água sobe conforme `level` (0…1), acompanha o giroscópio e
    /// passa por trás e por cima do conteúdo, que fica parecendo mergulhado.
    /// `bleedsIntoTopSafeArea` estende o recipiente por baixo da status bar.
    func waterContainer<S: Shape>(level: Double, in shape: S, bleedsIntoTopSafeArea: Bool = false) -> some View {
        modifier(WaterContainerModifier(level: level, shape: shape, bleedsIntoTopSafeArea: bleedsIntoTopSafeArea))
    }
}

private struct WaterContainerModifier<S: Shape>: ViewModifier {
    let level: Double
    let shape: S
    let bleedsIntoTopSafeArea: Bool

    @State private var motion = WaterMotion()

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
    }
}

/// O conteúdo do recipiente visto através da água: abaixo da superfície ele ondula e
/// ganha uma tintura fria (`waterRefraction` em `Bubble.metal`). Usa a mesma simulação
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
                        .floatArray(field)
                    ),
                    maxSampleOffset: CGSize(width: 8, height: 8)
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
                let _ = motion.advance(to: context.date, size: geo.size)
                Rectangle()
                    .fill(Color.white) // conteúdo de base; o shader ignora essa cor
                    .colorEffect(
                        ShaderLibrary.water(
                            .float2(geo.size),
                            .float(time),
                            .float(Float(min(max(level, 0), 1))),
                            .float2(CGPoint(x: CGFloat(motion.down.x), y: CGFloat(motion.down.y))),
                            .float(motion.agitation),
                            .float(layer.rawValue),
                            .floatArray(motion.field)
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
/// Sem sensor (Simulator) fica na vertical, só com as ondas ambiente do shader.
@MainActor
final class WaterMotion {
    static let columns = 64

    /// Deslocamento da superfície (pt) de parede a parede, no referencial da água.
    private(set) var field = [Float](repeating: 0, count: WaterMotion.columns)
    private(set) var agitation: Float = 0
    /// Tamanho do recipiente na última medição (inclui a extensão sob a status bar).
    private(set) var waterSize: CGSize = .zero
    /// Vetor unitário "para baixo" em coordenadas de tela (y para baixo).
    var down: SIMD2<Float> { SIMD2(sin(angle), cos(angle)) }

    private var velocity = [Float](repeating: 0, count: WaterMotion.columns)
    private var angle: Float = 0
    private var sensorAngle: Float = 0
    private var sensorMagnitude: Float = 1
    private var smoothedMagnitude: Float = 1
    private var lastFrame: Date?
    private let manager = CMMotionManager()

    // Parâmetros da água
    private let waveSpeed: Float = 420        // pt/s — período do balanço ≈ 2·largura/c
    private let damping: Float = 1.6          // 1/s — quanto maior, mais rápido assenta
    private let followRate: Float = 25        // 1/s — suavização mínima do sensor
    private let heaveGain: Float = 120        // pt/s por g de variação da gravidade
    private let maxDisplacement: Float = 90   // pt
    private let tiltResponse: Float = 0.6    // fração da inclinação que vira onda (1 = física plena)

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
    }

    /// Avança a simulação até `date`. `size` é o tamanho do recipiente em pontos.
    func advance(to date: Date, size: CGSize) {
        waterSize = size
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
        let dAngle = diff * min(1, dt * followRate)
        angle += dAngle
        let surfaceLength = abs(cos(angle)) * width + abs(sin(angle)) * height
        for i in 0..<count {
            let u = Float(i) / Float(count - 1) - 0.5
            // Rampa da inclinação com uma pitada de modos mais altos: a onda que sai daí
            // é em "S" e não uma reta, como num balanço de verdade.
            let ramp = u * surfaceLength + 0.10 * surfaceLength * sin(3 * .pi * u)
            field[i] += dAngle * ramp * tiltResponse
        }

        // 2. Gravidade mais forte/fraca: o meio da massa sobe ou desce.
        let dMagnitude = sensorMagnitude - smoothedMagnitude
        smoothedMagnitude += dMagnitude * min(1, dt * 10)
        for i in 0..<count {
            let u = Float(i) / Float(count - 1)
            velocity[i] -= dMagnitude * heaveGain * cos(2 * .pi * u)
        }

        // 3. Equação de onda (leapfrog, vários passos para estabilidade).
        let dx = max(width, 1) / Float(count - 1)
        let steps = max(1, Int((dt / (1.0 / 240.0)).rounded(.up)))
        let h = dt / Float(steps)
        let k = waveSpeed * waveSpeed / (dx * dx)
        for _ in 0..<steps {
            for i in 0..<count {
                let left = field[max(i - 1, 0)]
                let right = field[min(i + 1, count - 1)]
                let laplacian = left - 2 * field[i] + right
                velocity[i] += (k * laplacian - damping * velocity[i]) * h
            }
            for i in 0..<count {
                field[i] += velocity[i] * h
            }
        }

        // 4. Volume conservado: a média do deslocamento é sempre zero.
        let mean = field.reduce(0, +) / Float(count)
        var energy: Float = 0
        for i in 0..<count {
            field[i] = min(max(field[i] - mean, -maxDisplacement), maxDisplacement)
            energy += velocity[i] * velocity[i]
        }
        let target = min((energy / Float(count)).squareRoot() / 200, 1.0)
        agitation += (target - agitation) * min(1, dt * 4)
    }
}
