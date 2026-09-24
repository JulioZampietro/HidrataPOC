import SwiftUI
import UIKit

/// Gota de vidro líquido, redonda e translúcida, com todas as bordas
/// visíveis dentro do espaço recebido (nunca encosta nas bordas do
/// container — sempre fica inscrita com uma margem, como uma esfera
/// flutuando). O contorno "respira" continuamente com uma leve
/// deformação orgânica e reage ao toque com um esguicho elástico.
struct LiquidBubbleView: View {
    var tint: Color = .white

    @State private var isPressed = false
    @State private var tapPulse: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let blob = DropletShape(amplitude: 1 + tapPulse, phase: time * 0.9)

                ZStack {
                    // halo suave ao redor, como o brilho ambiente da gota na referência
                    blob
                        .fill(tint.opacity(0.05))
                        .shadow(color: tint.opacity(0.35), radius: size * 0.12, y: size * 0.02)

                    // vidro líquido transparente
                    Color.clear
                        .glassEffect(.clear.tint(tint.opacity(0.12)).interactive(), in: blob)

                    // realce especular no topo, como luz refletindo na água
                    blob
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.0), .white.opacity(0)],
                                center: UnitPoint(x: 0.3, y: 0.24),
                                startRadius: 0,
                                endRadius: size * 0.5
                            )
                        )
                        .blendMode(.plusLighter)

                    // contorno fino, dá o "menisco" da bolha d'água
                    blob
                        .stroke(.white.opacity(0.55), lineWidth: 1.2)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(isPressed ? 0.93 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.35), value: isPressed)
            }
        }
        .contentShape(Circle())
        .onTapGesture { triggerTap() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Gota d'água")
    }

    private func triggerTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        isPressed = true
        withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
            tapPulse = 2.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isPressed = false
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.22).delay(0.12)) {
            tapPulse = 0
        }
    }
}

/// Contorno circular levemente irregular, perturbado por duas ondas
/// senoidais fora de fase, e inscrito com margem (0.82 do raio máximo) para
/// que todas as bordas fiquem visíveis dentro do frame recebido.
private struct DropletShape: Shape {
    var amplitude: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(amplitude, phase) }
        set { amplitude = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 1.5
        let pointCount = 96

        var path = Path()
        for i in 0...pointCount {
            let angle = (Double(i) / Double(pointCount)) * 2 * .pi
            let wobble = amplitude * (0.05 * sin(angle * 3 + phase) + 0.028 * sin(angle * 5 - phase * 1.6))
            let r = baseRadius * (1 + wobble)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.blue.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        LiquidBubbleView(tint: .blue)
            .frame(width: 280, height: 280)
    }
}
