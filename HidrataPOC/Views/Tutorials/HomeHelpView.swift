import SwiftUI

private let accent = Color(red: 0.286, green: 0.498, blue: 0.714)

struct HomeHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    progressSection
                    buttonsSection
                    streakSection
                    mascotSection
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
                        .foregroundStyle(accent)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "house.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.top, 8)

            Text("Tela inicial")
                .font(.custom("Nunito", size: 24).weight(.heavy))
                .foregroundStyle(.primary)

            Text("Registre sua ingestão de água e acompanhe o progresso do dia.")
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Sections

    private var progressSection: some View {
        helpCard(title: "Barra de progresso", items: [
            HelpItem(icon: "drop.fill", color: accent,
                     title: "Consumo do dia",
                     body: "Mostra quantos mL você bebeu hoje versus a sua meta diária."),
            HelpItem(icon: "target", color: .orange,
                     title: "Meta ajustada pela temperatura",
                     body: "Nos dias mais quentes a meta aumenta automaticamente — você verá \"+X mL\" em laranja ao lado do total."),
        ])
    }

    private var buttonsSection: some View {
        helpCard(title: "Botões de registro", items: [
            HelpItem(icon: "drop.fill", color: accent,
                     title: "Gole · Copo · Garrafa",
                     body: "Toque em qualquer um para registrar 40 mL, 250 mL ou 500 mL instantaneamente."),
            HelpItem(icon: "plus", color: accent,
                     title: "Outro (personalizado)",
                     body: "Registra o volume que você configurou. Toque no lápis no canto do cartão para alterar o valor."),
        ])
    }

    private var streakSection: some View {
        helpCard(title: "Sequência de dias", items: [
            HelpItem(icon: "drop.fill", color: accent,
                     title: "Contador no canto superior direito",
                     body: "Quantos dias consecutivos você bateu a meta de hidratação. Não perca o ritmo!"),
        ])
    }

    private var mascotSection: some View {
        helpCard(title: "Mascote", items: [
            HelpItem(icon: "face.smiling", color: .green,
                     title: "Reage ao seu progresso",
                     body: "O monstro fica feliz quando você está hidratado e irritado quando está atrás da meta — use-o como guia visual rápido."),
        ])
    }

    // MARK: - Helpers

    private func helpCard(title: String, items: [HelpItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.custom("Nunito", size: 15).weight(.heavy))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 18)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemRow(item: item, isLast: index == items.count - 1)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func itemRow(item: HelpItem, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.color.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.color)
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.custom("Nunito", size: 14).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(item.body)
                        .font(.custom("Nunito", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !isLast { Divider().padding(.leading, 70) }
        }
    }
}

private struct HelpItem {
    let icon: String
    let color: Color
    let title: String
    let body: String
}

#Preview {
    HomeHelpView()
}
