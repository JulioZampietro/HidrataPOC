import SwiftUI

/// Rins pulando e comemorando quando o usuário bate a meta do dia: os dois nos cantos de baixo
/// do recipiente (ver `HomeView.topSection`) ou um só, no lugar do mascote no cartão da meta
/// das Configurações.
struct KidneyCheerView: View {
    enum Layout {
        /// Os dois rins nos cantos de baixo, virados pro centro.
        case pair
        /// Um rim só, no meio e esticado pra caber na moldura.
        case single
    }

    var layout: Layout = .pair
    /// `false` congela o rim no alto do pulo, de braços pra cima — pra imagens geradas com
    /// `ImageRenderer` (o cartão de compartilhar), que pegariam um quadro qualquer da animação.
    var isAnimated = true

    /// Com "Reduzir Movimento", os rins aparecem parados em vez de pular sem fim.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isAnimated)) { timeline in
            // 0,15 do ciclo é o alto do pulo (ver `bounce`).
            let t = isAnimated ? timeline.date.timeIntervalSinceReferenceDate : 0.15 / 0.9
            Canvas { context, size in
                switch layout {
                case .pair:
                    for (x, mirrored, phase) in [(size.width * 0.11, false, 0.0), (size.width * 0.89, true, 0.45)] {
                        let (hop, squash) = Self.bounce(t, phase: phase)
                        drawKidney(in: &context, at: CGPoint(x: x, y: size.height - 26 - CGFloat(hop) * 10),
                                   mirrored: mirrored, squash: squash, armsUp: hop > 0.3)
                    }
                case .single:
                    // Rim com os braços pra cima ocupa ~44×60 pt (contando o pulo); escala pra caber.
                    let scale = min(size.width / 44, size.height / 60)
                    let (hop, squash) = Self.bounce(t, phase: 0)
                    drawKidney(in: &context, at: CGPoint(x: size.width / 2, y: size.height - 20 * scale - CGFloat(hop) * 10 * scale),
                               mirrored: false, squash: squash, armsUp: hop > 0.3, scale: scale)
                }
            }
        }
    }

    /// Pulinho: sobe rápido, cai devagar, e fica parado um tempinho. Devolve a altura (0…1) e
    /// o quanto achata ao tocar o chão.
    private static func bounce(_ t: Double, phase: Double) -> (hop: Double, squash: Double) {
        let cycle = (t * 0.9 + phase).truncatingRemainder(dividingBy: 1)
        let hop = cycle < 0.35 ? sin(cycle / 0.35 * .pi) : 0
        let squash = cycle > 0.35 && cycle < 0.45 ? 0.08 * sin((cycle - 0.35) / 0.1 * .pi) : 0
        return (hop, squash)
    }

    /// Contorno do rim em feijão, com a reentrância à direita (x positivo), centrado na origem e
    /// com ~36 pt de altura. Também é o corpo do personagem do Rim Comilão.
    static let beanPath: Path = {
        var bean = Path()
        bean.move(to: CGPoint(x: 2, y: -18))
        bean.addCurve(to: CGPoint(x: 2, y: 18), control1: CGPoint(x: -26, y: -24), control2: CGPoint(x: -26, y: 24))
        bean.addCurve(to: CGPoint(x: 10, y: 4), control1: CGPoint(x: 12, y: 18), control2: CGPoint(x: 14, y: 10))
        bean.addQuadCurve(to: CGPoint(x: 10, y: -4), control: CGPoint(x: 5, y: 0))
        bean.addCurve(to: CGPoint(x: 2, y: -18), control1: CGPoint(x: 14, y: -10), control2: CGPoint(x: 12, y: -18))
        bean.closeSubpath()
        return bean
    }()

    private func drawKidney(in context: inout GraphicsContext, at center: CGPoint, mirrored: Bool, squash: Double, armsUp: Bool, scale: CGFloat = 1) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: (mirrored ? -1 : 1) * CGFloat(1 + squash) * scale, y: CGFloat(1 - squash) * scale)

        let skin = Color(red: 0.90, green: 0.45, blue: 0.47)
        let outline = Color(red: 0.62, green: 0.24, blue: 0.27)
        let ink = Color(red: 0.32, green: 0.12, blue: 0.14)

        // Bracinhos (atrás do corpo).
        var arms = Path()
        let armY: CGFloat = armsUp ? -20 : -2
        arms.move(to: CGPoint(x: -12, y: -4)); arms.addLine(to: CGPoint(x: -21, y: armY))
        arms.move(to: CGPoint(x: 10, y: -4)); arms.addLine(to: CGPoint(x: 19, y: armY))
        ctx.stroke(arms, with: .color(outline), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        // Corpo em feijão: a reentrância fica do lado de dentro (virado pro centro).
        let bean = Self.beanPath
        ctx.fill(bean, with: .linearGradient(
            Gradient(colors: [Color(red: 0.97, green: 0.60, blue: 0.60), skin]),
            startPoint: CGPoint(x: -10, y: -18), endPoint: CGPoint(x: 6, y: 18)
        ))
        ctx.stroke(bean, with: .color(outline), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: -14, y: -13, width: 5, height: 7)), with: .color(.white.opacity(0.45)))

        // Rosto (olhos fechadinhos de alegria + sorrisão + bochechas).
        var face = Path()
        for dx in [-8.0, 0.0] {
            face.addArc(center: CGPoint(x: dx, y: -4), radius: 2.2, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        }
        ctx.stroke(face, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: -8, y: 2))
        mouth.addQuadCurve(to: CGPoint(x: 0, y: 2), control: CGPoint(x: -4, y: 8))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(ink))
        for dx in [-12.0, 3.5] {
            ctx.fill(Path(ellipseIn: CGRect(x: dx, y: 0, width: 4, height: 2.5)), with: .color(Color(red: 1.0, green: 0.42, blue: 0.48).opacity(0.7)))
        }
    }
}

#Preview {
    RoundedRectangle(cornerRadius: 32)
        .fill(Color(red: 0.75, green: 0.88, blue: 1.0))
        .overlay { KidneyCheerView().frame(height: 80).frame(maxHeight: .infinity, alignment: .bottom) }
        .frame(height: 300)
        .padding()
}
