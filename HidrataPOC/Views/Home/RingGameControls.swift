import SwiftUI

/// Os botões do jogo das argolas (seta pra esquerda, seta pra direita e a rajada central), que
/// ocupam o lugar dos cartões de ingestão quando a meta do dia é batida. Segurar o botão mantém
/// o jato aberto; soltar fecha.
struct RingGameControls: View {
    let side: RingGameSide
    let isPressed: Bool
    var onPressChange: (Bool) -> Void
    var onAccessibilityPulse: () -> Void

    private var symbol: String {
        switch side {
        case .left: "arrow.left.circle.fill"
        case .right: "arrow.right.circle.fill"
        case .center: "arrow.clockwise.circle.fill"
        }
    }

    private var title: String {
        switch side {
        case .left: "Esquerda"
        case .right: "Direita"
        case .center: "Rajada central"
        }
    }

    var body: some View {
        GameHoldButton(
            symbol: symbol,
            icon: RingGameButtonIcon(side: side, isPressed: isPressed),
            accessibilityLabel: "Jato de água \(title.lowercased())",
            accessibilityHint: side == .center ? "Solta uma rajada de água no meio, para soltar argolas presas" : "Empurra as argolas para cima",
            isPressed: isPressed,
            onPressChange: onPressChange,
            onAccessibilityPulse: onAccessibilityPulse
        )
    }
}

/// Botão de minijogo que ocupa o lugar de um cartão de ingestão: branco como os cartões,
/// com o ícone azul do app. Só o ícone aparece; o nome fica no rótulo de acessibilidade.
/// Segurar mantém a ação ligada (`onPressChange(true)`), soltar desliga.
struct GameHoldButton: View {
    let symbol: String
    /// Ícone próprio (desenhado) no lugar do símbolo do sistema.
    var icon: RingGameButtonIcon? = nil
    let accessibilityLabel: String
    let accessibilityHint: String
    let isPressed: Bool
    var onPressChange: (Bool) -> Void
    var onAccessibilityPulse: () -> Void

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            icon
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .symbolRenderingMode(.palette)
                .foregroundStyle(isPressed ? Color.appAccent : .white, isPressed ? .white : Color.appAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var body: some View {
        // Ícone grande, no tamanho dos desenhos dos cartões de ingestão: seta branca sobre o
        // círculo azul do app; apertado, as cores se invertem.
        iconView
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isPressed ? AnyShapeStyle(RingGameButtonIcon.buttonGradient) : AnyShapeStyle(Color(UIColor.secondarySystemBackground)))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: onPressChange, perform: {})
        // O ScrollView da Home pode atrasar o início do toque: num toque rápido o
        // `pressing` talvez nem chegue, então o toque completo também dispara um pulso.
        .simultaneousGesture(TapGesture().onEnded(onAccessibilityPulse))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onAccessibilityPulse)
    }
}


/// Ícones dos três jatos do jogo das argolas: círculo azul em degradê e o bico com os
/// jatos em branco (desenhados em vetor, no quadro 68×68 dos desenhos originais). Apertado,
/// as cores se invertem, como nos outros botões do jogo.
struct RingGameButtonIcon: View {
    let side: RingGameSide
    let isPressed: Bool

    private static let gradientColors = [Color(red: 0x1B / 255, green: 0x3A / 255, blue: 0x9E / 255),
                                          Color(red: 0x52 / 255, green: 0xA8 / 255, blue: 0xFF / 255)]
    private static let canvasGradient = Gradient(colors: gradientColors)

    /// O mesmo degradê do círculo do ícone, também usado no fundo do botão apertado.
    static let buttonGradient = LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / 68
            ctx.scaleBy(x: scale, y: scale)

            let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 68, height: 68))
            if isPressed {
                ctx.fill(circle, with: .color(.white))
            } else {
                ctx.fill(circle, with: .linearGradient(Self.canvasGradient, startPoint: .zero, endPoint: CGPoint(x: 68, y: 68)))
            }

            let glyph: Color = isPressed ? .appAccent : .white
            ctx.translateBy(x: 34, y: 34)
            switch side {
            case .left, .right:
                ctx.rotate(by: .degrees(side == .right ? 45 : 135))
                ctx.fill(Path(roundedRect: CGRect(x: 9, y: -8, width: 10, height: 16), cornerRadius: 3), with: .color(glyph))
                Self.strokeJets(in: &ctx, color: glyph, dash: [7, 6], lines: [(4, 0, -20, 0), (4, -5, -16, -12), (4, 5, -16, 12)])
            case .center:
                ctx.fill(Path(roundedRect: CGRect(x: -8, y: 11, width: 16, height: 9), cornerRadius: 3), with: .color(glyph))
                Self.strokeJets(in: &ctx, color: glyph, dash: [6, 6],
                                lines: [(0, 6, 0, -21), (-3, 6, -12, -18), (3, 6, 12, -18), (-5, 7, -21, -8), (5, 7, 21, -8)])
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func strokeJets(in ctx: inout GraphicsContext, color: Color, dash: [CGFloat], lines: [(CGFloat, CGFloat, CGFloat, CGFloat)]) {
        var path = Path()
        for (x1, y1, x2, y2) in lines {
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: dash))
    }
}
