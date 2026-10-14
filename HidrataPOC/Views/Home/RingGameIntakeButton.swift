import SwiftUI

/// Botão do minigame que volta para os botões de ingestão de água ("Beber água"). Usa o
/// mesmo cartão do "Gole" (gota grande à esquerda), então ele fica igual aos botões de
/// ingestão que o usuário já conhece.
struct RingGameIntakeButton: View {
    let height: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            IntakeCardContent(
                icon: .symbol("drop.fill"),
                title: "Beber\nágua",
                subtitle: nil,
                height: height
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Volta para os botões de registrar água")
    }
}
