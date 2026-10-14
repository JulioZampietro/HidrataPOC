import SwiftUI

/// Os botões do jogo das argolas (esquerdo, direito e o jato central, mais baixo, embaixo),
/// que ocupam o lugar dos quatro cartões de ingestão quando a meta do dia é batida. Segurar o botão mantém
/// o jato aberto; soltar fecha.
struct RingGameControls: View {
    let side: RingGameSide
    let isPressed: Bool
    var onPressChange: (Bool) -> Void
    var onAccessibilityPulse: () -> Void

    private var title: String {
        switch side {
        case .left: "Esquerda"
        case .right: "Direita"
        case .center: "Jato central"
        }
    }

    var body: some View {
        // O botão central é largo e baixo: ícone e texto lado a lado.
        let layout = side == .center ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
        layout {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: side == .center ? 30 : 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(AppFont.headline)
        }
        .foregroundStyle(isPressed ? .white : Color.appAccentText)
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
        // `pressing` talvez nem chegue, então o toque completo também solta um jatinho.
        .simultaneousGesture(TapGesture().onEnded(onAccessibilityPulse))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jato de água \(title.lowercased())")
        .accessibilityHint(side == .center ? "Solta uma rajada de água no meio, para soltar argolas presas" : "Empurra as argolas para cima")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onAccessibilityPulse)
    }
}
