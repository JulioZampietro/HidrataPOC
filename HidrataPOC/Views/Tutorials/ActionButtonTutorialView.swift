import SwiftUI
import UIKit


struct ActionButtonTutorialView: View {
    var body: some View {
<<<<<<< HEAD
        TankSheet {
            VStack(spacing: 20) {
                ActionButtonStepsContent(showsMascotLine: false)
                openSettingsButton
                    .padding(.horizontal, 20)
=======
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    compatibilityBadge
                    stepsCard
                    openSettingsButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .appScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                        .foregroundStyle(Color.appAccentText)
                }
>>>>>>> main
            }
            .padding(.bottom, 40)
        }
    }

    private var openSettingsButton: some View {
        Button(action: openActionButtonSettings) {
            Text("Abrir Ajustes")
                .font(AppFont.calloutStrong)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.gradientProminent)
    }

    private func openActionButtonSettings() {
        Haptic.tap.play()
        // App-Prefs: (sem caminho) abre o Ajustes na raiz.
        // Fallback para a página do próprio app se não funcionar.
        if let url = URL(string: "App-Prefs:") {
            UIApplication.shared.open(url) { success in
                if !success, let fallback = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(fallback)
                }
            }
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Conteúdo compartilhado entre a sheet de tutorial (esta, mais o botão "Abrir
/// Ajustes") e a página equivalente do onboarding de primeiro uso
/// (`FeatureOnboardingView`) — mesma cópia nos dois lugares, um único lugar pra editar.
struct ActionButtonStepsContent: View {
    /// A sheet standalone (acessada pelo Perfil) não mostra a fala do mascote —
    /// só o onboarding de primeiro uso, onde ele ainda está "se apresentando".
    var showsMascotLine: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            CurrentMascotTankHeader(
                title: "Botão de Ação",
                subtitle: "Registre água com um toque lateral — sem desbloquear o iPhone.",
                mascotLine: showsMascotLine ? "Um toque e já era? Isso não é justo." : nil
            )

            stepsCard
                .padding(.horizontal, 20)
        }
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(number: 1,
                    title: "Abra o app Ajustes",
                    detail: "Vá até o aplicativo Ajustes no seu iPhone.",
                    isLast: false)
            stepRow(number: 2,
                    title: "Toque em \"Botão de Ação\"",
                    detail: "Role até encontrar a opção Botão de Ação.",
                    isLast: false)
            stepRow(number: 3,
                    title: "Selecione \"Controles\"",
                    detail: "Deslize as opções até chegar em Controles e toque para selecionar.",
                    isLast: false)
            stepRow(number: 4,
                    title: "Adicione os controles do Gole",
                    detail: "Em \"Controles disponíveis\", encontre Gole e adicione os controles de hidratação que quiser.",
                    isLast: true)
        }
        .panelBackground()
    }

    private func stepRow(number: Int, title: String, detail: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                DropBadge(number: number)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !isLast {
                Divider().padding(.leading, 18 + 26 + 14)
            }
        }
    }
}

#Preview {
    ActionButtonTutorialView()
}
