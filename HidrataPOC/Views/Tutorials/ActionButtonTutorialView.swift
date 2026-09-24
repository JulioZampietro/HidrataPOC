import SwiftUI
import UIKit

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

struct ActionButtonTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(accentBlue)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentBlue.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "button.angledbottom.horizontal.right")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }
            .padding(.top, 8)

            Text("Botão de Ação")
                .font(.custom("Nunito", size: 24).weight(.heavy))
                .foregroundStyle(.primary)

            Text("Registre água com um toque lateral — sem desbloquear o iPhone.")
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Compatibility Badge

    private var compatibilityBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.custom("Nunito", size: 13))
                .foregroundStyle(accentBlue)
            Text("iPhone 15 Pro, 16 e posteriores · iOS 18+")
                .font(.custom("Nunito", size: 13).weight(.semibold))
                .foregroundStyle(accentBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(accentBlue.opacity(0.1), in: Capsule())
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(
                number: 1,
                icon: "gearshape.fill",
                title: "Abra o app Ajustes",
                description: "Vá até o aplicativo Ajustes no seu iPhone.",
                isLast: false
            )
            stepRow(
                number: 2,
                icon: "button.angledbottom.horizontal.right",
                title: "Toque em \"Botão de Ação\"",
                description: "Role até encontrar a opção Botão de Ação.",
                isLast: false
            )
            stepRow(
                number: 3,
                icon: "slider.horizontal.3",
                title: "Selecione \"Controles\"",
                description: "Deslize as opções até chegar em Controles e toque para selecionar.",
                isLast: false
            )
            stepRow(
                number: 4,
                icon: "plus.circle.fill",
                title: "Adicione os controles do HidrataPOC",
                description: "Em \"Controles disponíveis\", encontre HidrataPOC e adicione os controles de hidratação que quiser.",
                isLast: true
            )
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private func stepRow(number: Int, icon: String, title: String, description: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentBlue)
                        .frame(width: 32, height: 32)
                    Text("\(number)")
                        .font(.custom("Nunito", size: 14).weight(.heavy))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentBlue)
                        Text(title)
                            .font(.custom("Nunito", size: 15).weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    Text(description)
                        .font(.custom("Nunito", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if !isLast {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 10000, y: 0))
                }
                .stroke(
                    Color(red: 0.75, green: 0.78, blue: 0.82).opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
                .frame(height: 1)
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Open Settings Button

    private var openSettingsButton: some View {
        Button(action: openActionButtonSettings) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 16, weight: .semibold))
                Text("Abrir Ajustes")
                    .font(.custom("Nunito", size: 16).weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .tint(accentBlue)
    }

    // MARK: - Actions

    private func openActionButtonSettings() {
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

#Preview {
    ActionButtonTutorialView()
}
