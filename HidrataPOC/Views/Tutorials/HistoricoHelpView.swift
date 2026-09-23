import SwiftUI

private let accent = Color(red: 0.286, green: 0.498, blue: 0.714)
private let calBlue = Color(red: 0x3E / 255.0, green: 0x8F / 255.0, blue: 0xC7 / 255.0)

struct HistoricoHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    calendarSection
                    navigationSection
                    detailSection
                    chartSection
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
                Image(systemName: "calendar")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.top, 8)

            Text("Histórico")
                .font(.custom("Nunito", size: 24).weight(.heavy))
                .foregroundStyle(.primary)

            Text("Visualize seu progresso de hidratação ao longo do mês e da semana.")
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Sections

    private var calendarSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Calendário mensal")

            Divider().padding(.horizontal, 18)

            itemRow(icon: "square.fill", color: calBlue,
                    title: "Células de cada dia",
                    body: "Cada quadrado se preenche de baixo para cima proporcionalmente à meta — 100% preenchido significa que você bateu a meta naquele dia.",
                    isLast: false)

            // Legenda visual
            legendPreview

            itemRow(icon: "checkmark.circle.fill", color: .green,
                    title: "Metas batidas",
                    body: "O contador no canto superior direito do card mostra quantas metas foram batidas no mês atual.",
                    isLast: true)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private var legendPreview: some View {
        HStack(spacing: 20) {
            legendItem(fill: 1.0, label: "Meta batida")
            legendItem(fill: 0.5, label: "Parcial")
            legendItem(fill: nil, label: "A vir")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func legendItem(fill: Double?, label: String) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(calBlue.opacity(0.15))
                    if let fill {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(calBlue)
                            .frame(height: geo.size.height * fill)
                    }
                }
            }
            .frame(width: 16, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(label)
                .font(.custom("Nunito", size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var navigationSection: some View {
        helpCard(title: "Navegar entre meses", items: [
            HelpItem(icon: "chevron.left", color: accent,
                     title: "Setas de mês",
                     body: "Use as setas ao lado do nome do mês para ver meses anteriores ou futuros."),
        ])
    }

    private var detailSection: some View {
        helpCard(title: "Detalhe do dia", items: [
            HelpItem(icon: "hand.tap.fill", color: accent,
                     title: "Toque em qualquer dia passado",
                     body: "Abre um painel com o gráfico de consumo por hora e a lista de todos os registros daquele dia."),
            HelpItem(icon: "trash", color: .red,
                     title: "Apagar registros",
                     body: "No detalhe do dia você pode remover um registro lançado por engano — ele é removido do histórico e do Apple Saúde."),
        ])
    }

    private var chartSection: some View {
        helpCard(title: "Gráfico semanal", items: [
            HelpItem(icon: "chevron.right", color: calBlue,
                     title: "Trocar de visualização",
                     body: "Toque na seta no canto do card ou arraste para o lado para ver o gráfico de barras dos últimos 7 dias."),
        ])
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Nunito", size: 15).weight(.heavy))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func helpCard(title: String, items: [HelpItem]) -> some View {
        VStack(spacing: 0) {
            sectionHeader(title)
            Divider().padding(.horizontal, 18)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemRow(icon: item.icon, color: item.color, title: item.title, body: item.body,
                        isLast: index == items.count - 1)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func itemRow(icon: String, color: Color, title: String, body: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("Nunito", size: 14).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(body)
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
    HistoricoHelpView()
}
