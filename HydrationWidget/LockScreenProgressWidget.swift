import SwiftUI
import WidgetKit

/// Widget da tela de bloqueio: a porcentagem da meta de hoje no centro, com um anel
/// em volta enchendo conforme o progresso. Usa o mesmo provider do `WaterTankWidget`
/// (consumo de hoje do SwiftData compartilhado e a meta efetiva salva pelo app), então
/// é recarregado junto com ele por `WidgetSync.reloadWaterTank()`.
struct LockScreenProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSync.lockScreenProgressKind, provider: WaterTankProvider()) { entry in
            LockScreenProgressView(entry: entry)
        }
        .configurationDisplayName("Progresso de hoje")
        .description("A porcentagem da sua meta de água de hoje.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenProgressView: View {
    let entry: WaterTankEntry

    /// Porcentagem de verdade no texto, sem teto: quem passa da meta vê 110%, 120%…
    /// O anel (`entry.progress`) é que para em 100%.
    private var percent: Int {
        guard entry.goalML > 0 else { return 0 }
        return Int((Double(entry.consumedML) / Double(entry.goalML) * 100).rounded())
    }

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(percent)%")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Água de hoje: \(percent)% da meta")
        .accessibilityValue("\(entry.consumedML) de \(entry.goalML) mililitros")
    }
}

/// Variante da tela de bloqueio: o próprio círculo do widget é um copo visto de frente,
/// enchendo de baixo pra cima conforme o progresso de hoje, com a superfície ondulada.
struct LockScreenWaterLevelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSync.lockScreenWaterLevelKind, provider: WaterTankProvider()) { entry in
            LockScreenWaterLevelView(entry: entry)
        }
        .configurationDisplayName("Nível de água")
        .description("Um círculo que enche conforme você bebe água hoje.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenWaterLevelView: View {
    let entry: WaterTankEntry

    var body: some View {
        ZStack {
            // Fundo translúcido padrão da tela de bloqueio: é o "vazio" do círculo.
            AccessoryWidgetBackground()
            ZStack {
                WavyWaterShape(level: entry.progress)
                    .fill(.white)
                // Meta batida: a sombra do rim feliz aparece recortada na água.
                if entry.progress >= 1 {
                    HappyKidneyShadow()
                }
            }
            .compositingGroup()
            .widgetAccentable()
        }
        .clipShape(Circle())
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Água de hoje: \(Int((entry.progress * 100).rounded()))% da meta")
        .accessibilityValue("\(entry.consumedML) de \(entry.goalML) mililitros")
    }
}

/// Silhueta do rim comemorando (o mesmo `KidneyCheerView.beanPath` da Home, de braços pra
/// cima) recortada na água: corpo e braços furam a água (`destinationOut`) e deixam ver o
/// fundo do widget; olhos fechadinhos e sorriso ficam em água, desenhados por cima do furo.
/// Tem de ficar dentro de um `compositingGroup()` com a água, senão o recorte fura o widget todo.
private struct HappyKidneyShadow: View {
    var body: some View {
        ZStack {
            // O recorte tem de ser um modo de mistura da view, não do `Canvas`: dentro dele o
            // `destinationOut` só apagaria o próprio canvas, não a água por baixo.
            Canvas { context, size in
                Self.placeKidney(&context, in: size)
                var arms = Path()
                arms.move(to: CGPoint(x: -12, y: -4)); arms.addLine(to: CGPoint(x: -21, y: -20))
                arms.move(to: CGPoint(x: 10, y: -4)); arms.addLine(to: CGPoint(x: 19, y: -20))
                context.stroke(arms, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                context.fill(KidneyCheerView.beanPath, with: .color(.black))
            }
            .blendMode(.destinationOut)

            Canvas { context, size in
                Self.placeKidney(&context, in: size)
                Self.drawFace(&context)
            }
        }
    }

    /// Rim de braços pra cima ocupa ~42×39 pt em volta de (-1, -1,5); ocupa 62% do círculo.
    private static func placeKidney(_ context: inout GraphicsContext, in size: CGSize) {
        let scale = min(size.width, size.height) * 0.62 / 42
        context.translateBy(x: size.width / 2 + scale, y: size.height / 2 + 1.5 * scale)
        context.scaleBy(x: scale, y: scale)
    }

    /// Olhos fechadinhos de alegria e sorrisão, em água, por cima do furo.
    private static func drawFace(_ context: inout GraphicsContext) {
        var eyes = Path()
        for dx in [-8.0, 0.0] {
            eyes.addArc(center: CGPoint(x: dx, y: -4), radius: 2.4, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        }
        context.stroke(eyes, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: -8.5, y: 2))
        mouth.addQuadCurve(to: CGPoint(x: 0.5, y: 2), control: CGPoint(x: -4, y: 9))
        mouth.closeSubpath()
        context.fill(mouth, with: .color(.white))
    }
}

/// Água subindo até `level` (0…1) da altura, com a superfície em ondinhas (uma senoide
/// de duas cristas). As ondas somem perto do fundo e do topo, pra o círculo vazio ficar
/// vazio de verdade e o cheio fechar sem um recorte ondulado na borda.
private struct WavyWaterShape: Shape {
    let level: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        guard level < 1 else { return Path(rect) }

        let surfaceY = rect.maxY - rect.height * level
        // Amplitude cheia no meio, diminuindo nos 8% de cada ponta.
        let edgeFade = min(1, min(level, 1 - level) / 0.08)
        let amplitude = rect.height * 0.035 * edgeFade
        let waves = 2.0
        let steps = 48

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let x = rect.minX + rect.width * fraction
            let y = surfaceY + amplitude * sin(fraction * waves * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Nível de água", as: .accessoryCircular) {
    LockScreenWaterLevelWidget()
} timeline: {
    WaterTankEntry(date: .now, consumedML: 0, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 600, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 1800, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 2500, goalML: 2500)
}

#Preview("Progresso", as: .accessoryCircular) {
    LockScreenProgressWidget()
} timeline: {
    WaterTankEntry(date: .now, consumedML: 0, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 1800, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 2500, goalML: 2500)
    WaterTankEntry(date: .now, consumedML: 3000, goalML: 2500)
}
