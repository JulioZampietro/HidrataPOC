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
    let accessibilityLabel: String
    let accessibilityHint: String
    let isPressed: Bool
    var onPressChange: (Bool) -> Void
    var onAccessibilityPulse: () -> Void

    var body: some View {
        // Ícone grande, no tamanho dos desenhos dos cartões de ingestão: seta branca sobre o
        // círculo azul do app; apertado, as cores se invertem.
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isPressed ? Color.appAccent : .white, isPressed ? .white : Color.appAccent)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isPressed ? Color.appAccent : Color(UIColor.secondarySystemBackground))
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
