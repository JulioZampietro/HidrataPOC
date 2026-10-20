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

/// Joystick virtual dos minijogos, no lugar dos botões: um círculo onde o polegar arrasta a
/// bolinha do meio, que segue o dedo até a borda e volta pro centro ao soltar. Ocupa um cartão
/// branco igual aos botões. `onChange` recebe a inclinação de −1 a 1 em cada eixo (só x com
/// `horizontalOnly`) a cada movimento, e (0, 0) ao soltar.
struct GameJoystick: View {
    let horizontalOnly: Bool
    let accessibilityLabel: String
    /// Ações do VoiceOver no lugar do arrasto (ex.: "Esquerda", "Direita").
    let accessibilityActions: [(name: String, perform: () -> Void)]
    var onChange: (CGVector) -> Void

    @State private var knobOffset: CGSize = .zero
    @State private var isTouching = false

    var body: some View {
        GeometryReader { geo in
            let baseRadius = max(min(geo.size.width, geo.size.height) / 2 - 12, 10)
            let knobRadius = baseRadius * 0.44
            // Até onde o centro da bolinha vai: ela pode passar um pouco da borda da base.
            let reach = baseRadius - knobRadius * 0.4
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.12))
                    .overlay(Circle().strokeBorder(Color.appAccent.opacity(0.35), lineWidth: 2))
                    .frame(width: baseRadius * 2, height: baseRadius * 2)
                directionMarks(radius: baseRadius)
                Circle()
                    .fill(Color.appAccent)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .frame(width: knobRadius * 2, height: knobRadius * 2)
                    .scaleEffect(isTouching ? 0.94 : 1)
                    .offset(knobOffset)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isTouching { Haptic.tap.play() }
                        isTouching = true
                        var dx = value.location.x - center.x
                        var dy = horizontalOnly ? 0 : value.location.y - center.y
                        let length = hypot(dx, dy)
                        if length > reach {
                            dx *= reach / length
                            dy *= reach / length
                        }
                        knobOffset = CGSize(width: dx, height: dy)
                        onChange(CGVector(dx: dx / reach, dy: dy / reach))
                    }
                    .onEnded { _ in
                        isTouching = false
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { knobOffset = .zero }
                        onChange(.zero)
                    }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            ForEach(accessibilityActions.indices, id: \.self) { index in
                Button(accessibilityActions[index].name, action: accessibilityActions[index].perform)
            }
        }
    }

    /// Setinhas na borda da base mostrando pra onde dá pra arrastar.
    private func directionMarks(radius: CGFloat) -> some View {
        let symbols: [(String, CGSize)] = horizontalOnly
            ? [("chevron.left", CGSize(width: -1, height: 0)), ("chevron.right", CGSize(width: 1, height: 0))]
            : [("chevron.left", CGSize(width: -1, height: 0)), ("chevron.right", CGSize(width: 1, height: 0)),
               ("chevron.up", CGSize(width: 0, height: -1)), ("chevron.down", CGSize(width: 0, height: 1))]
        return ZStack {
            ForEach(symbols.indices, id: \.self) { index in
                Image(systemName: symbols[index].0)
                    .font(.system(size: max(radius * 0.18, 9), weight: .bold))
                    .foregroundStyle(Color.appAccent.opacity(0.55))
                    .offset(x: symbols[index].1.width * radius * 0.8, y: symbols[index].1.height * radius * 0.8)
            }
        }
    }
}
