import SwiftUI
import UIKit

struct ActionButtonTutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    VStack(spacing: 10) {
                        Image(systemName: "button.angledbottom.horizontal.right")
                            .font(.system(size: 52))
                            .foregroundStyle(.orange)
                            .padding(.top, 24)

                        Text("Botão de Ação")
                            .font(.title2.bold())

                        Text("Pressione o botão lateral para registrar água em um toque — sem desbloquear o iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    compatibilityBadge

                    howItWorksCard

                    setupSteps

                    Button(action: openSettings) {
                        Label("Abrir Ajustes", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var compatibilityBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .foregroundStyle(.orange)
            Text("iPhone 15 Pro, 16 e modelos posteriores · iOS 18+")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1), in: Capsule())
    }

    private var howItWorksCard: some View {
        VStack(spacing: 12) {
            Text("Como funciona")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 0) {
                ActionStepPill(icon: "button.angledbottom.horizontal.right", label: "Pressiona\no botão")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                ActionStepPill(icon: "square.grid.2x2", label: "Central de\nControle abre")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                ActionStepPill(icon: "drop.fill", label: "Toca o\ntipo de água")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                ActionStepPill(icon: "checkmark.circle.fill", label: "Registrado\nsem abrir app")
            }
        }
        .padding()
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var setupSteps: some View {
        VStack(spacing: 0) {
            ActionTutorialStep(
                number: "1",
                title: "Ajustes → Botão de Ação",
                desc: "Selecione \"Central de Controle\"."
            )

            Divider().padding(.leading, 56)

            ActionTutorialStep(
                number: "2",
                title: "Adicione os controles de água",
                desc: "Em Central de Controle → Personalizar, busque \"HidrataPOC\" e adicione os controles de Copo, Garrafa e Galão."
            )

            Divider().padding(.leading, 56)

            ActionTutorialStep(
                number: "3",
                title: "Pressione o botão",
                desc: "A Central de Controle abre como overlay. Toque no controle desejado e a água é registrada na hora."
            )
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Componentes

struct ActionStepPill: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionTutorialStep: View {
    let number: String
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(.orange).frame(width: 28, height: 28)
                Text(number).font(.caption.bold()).foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

#Preview {
    ActionButtonTutorialView()
}
