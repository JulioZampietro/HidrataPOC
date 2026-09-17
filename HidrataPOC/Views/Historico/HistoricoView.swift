import SwiftUI

/// Azul de marca usado no calendário do histórico (preenchimento, anel do dia
/// atual e contador de metas batidas).
private let calendarBlue = Color(red: 0x3E / 255.0, green: 0x8F / 255.0, blue: 0xC7 / 255.0)

private extension Font {
    static func baloo2ExtraBold(_ size: CGFloat) -> Font {
        .custom("Baloo2-ExtraBold", size: size)
    }

    static func nunitoExtraBold(_ size: CGFloat) -> Font {
        .custom("Nunito-ExtraBold", size: size)
    }

    static func nunitoBold(_ size: CGFloat) -> Font {
        .custom("Nunito-Bold", size: size)
    }
}

struct DiaHistorico: Identifiable {
    let id = UUID()
    let date: Date
    /// Percentual da meta diária de hidratação atingido nesse dia (1.0 = 100%).
    /// `nil` quando o dia ainda não aconteceu — não há o que mostrar.
    let percentualMeta: Double?

    var isFuturo: Bool { percentualMeta == nil }
    var bateuMeta: Bool { (percentualMeta ?? 0) >= 1.0 }
}

/// Gera dados mockados de histórico por mês. Sem integração com banco de dados
/// ainda — isto existe só para popular a tela enquanto o modelo real não chega.
enum HistoricoMockData {
    /// Padrão fixo de percentuais (proporção da meta diária bebida), repetido a
    /// cada 14 dias só para dar variedade visual ao mock.
    private static let padraoPercentual: [Double] = [
        1.0, 1.0, 0.45, 1.0, 1.0, 0.3, 1.0, 1.0, 1.0, 0.55, 1.0, 1.0, 1.0, 0.5,
    ]

    static func generateMonth(for monthDate: Date, calendar: Calendar) -> [DiaHistorico] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }
        let today = calendar.startOfDay(for: .now)

        return range.compactMap { day in
            guard let date = calendar.date(bySetting: .day, value: day, of: monthDate) else { return nil }
            let dayStart = calendar.startOfDay(for: date)

            let percentual: Double? = dayStart > today ? nil : padraoPercentual[(day - 1) % padraoPercentual.count]
            return DiaHistorico(date: dayStart, percentualMeta: percentual)
        }
    }
}

struct HistoricoView: View {
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    // Mock: sequência de dias seguidos batendo a meta e dias perdidos no total.
    // Substituir por dados reais quando o histórico estiver persistido.
    private let streakDias = 12
    private let diasPerdidos = 9

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        cal.firstWeekday = 1
        return cal
    }

    private let weekdaySymbols = ["D", "S", "T", "Q", "Q", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var monthDays: [DiaHistorico] {
        HistoricoMockData.generateMonth(for: displayedMonth, calendar: calendar)
    }

    private var gridCells: [DiaHistorico?] {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return monthDays
        }
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
        let leadingEmptyCount = (weekdayOfFirst + 7) % 7
        return Array(repeating: nil, count: leadingEmptyCount) + monthDays.map { Optional($0) }
    }

    private var metasBatidasCount: Int {
        monthDays.filter { $0.bateuMeta }.count
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLLL yyyy"
        let raw = formatter.string(from: displayedMonth)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    topBar
                    mascotSection
                    calendarCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .appScreenBackground()
            .navigationBarHidden(true)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                // Placeholder: abrir ajuda/tutorial do histórico no futuro.
            } label: {
                Image(systemName: "questionmark")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
            .accessibilityLabel("Ajuda")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                Text("\(streakDias)").font(.baloo2ExtraBold(20))
                    + Text(" dias").font(.nunitoBold(12.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
    }

    /// Mascote + seu balão de fala, agrupados para que o balão fique
    /// visualmente grudado nele, saindo de perto da sua cabeça.
    private var mascotSection: some View {
        ZStack(alignment: .top) {
            mascotPlaceholder
                .padding(.top, 28)

            HStack {
                Spacer()
                speechBubble
            }
            .padding(.trailing, 36)
        }
        .padding(.bottom, 20)
    }

    private var speechBubble: some View {
        Text("\(diasPerdidos) dias perdidos…")
            .font(.nunitoExtraBold(13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    /// Placeholder do mascote — design final ainda não definido pelo time.
    private var mascotPlaceholder: some View {
        ZStack {
            Ellipse()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 190, height: 105)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.brown.opacity(0.7), Color.brown],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 120, height: 120)
                .overlay(
                    // ".inverse" fixa o desenho preenchido — sem ela, o sistema
                    // troca entre contorno/preenchido dependendo do light/dark mode.
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(gridCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        DayCell(dia: cell, isToday: calendar.isDateInToday(cell.date))
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            DashedDivider()
            legend
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var monthHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Mês anterior")

                Text(monthTitle)
                    .font(.baloo2ExtraBold(21))

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Próximo mês")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .tint(.secondary)

            Spacer()

            Text("\(metasBatidasCount) metas batidas")
                .font(.nunitoExtraBold(12.5))
                .foregroundStyle(calendarBlue)
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.nunitoExtraBold(11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(percentual: 1.0, label: "Meta batida")
            legendItem(percentual: 0.5, label: "Parcial")
            legendItem(percentual: nil, label: "A vir")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(percentual: Double?, label: String) -> some View {
        HStack(spacing: 6) {
            FillSwatch(percentual: percentual)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private func changeMonth(by value: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = newDate
    }
}

/// Célula de um dia no calendário: preenchida de baixo pra cima proporcionalmente
/// ao percentual da meta diária que o usuário bebeu naquele dia (0% vazia,
/// 100% totalmente cheia), como um copo se enchendo.
private struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let dia: DiaHistorico
    let isToday: Bool

    private var dayNumber: Int {
        Calendar.current.component(.day, from: dia.date)
    }

    private var clampedFill: Double {
        min(1, max(0, dia.percentualMeta ?? 0))
    }

    var body: some View {
        GeometryReader { geo in
            let fillHeight = geo.size.height * clampedFill

            ZStack(alignment: .bottom) {
                FillSwatch(percentual: dia.percentualMeta, cornerRadius: 12)

                // O número é desenhado duas vezes, cada cópia recortada exatamente
                // na linha do preenchimento: a metade sobre o azul fica branca, a
                // metade sobre a trilha vazia usa a cor de contraste da trilha —
                // acompanha o preenchimento em vez de escolher uma cor única.
                numberText
                    .foregroundStyle(fillTextColor)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: fillHeight)
                    }

                numberText
                    .foregroundStyle(trackTextColor)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: geo.size.height - fillHeight)
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(todayRingColor, lineWidth: isToday ? 2 : 0)
                    .padding(1)
            )
        }
        .frame(height: 40)
    }

    private var numberText: Text {
        Text("\(dayNumber)").font(.baloo2ExtraBold(14))
    }

    /// No dark mode o anel do dia atual usa o mesmo azul escuro do fundo da
    /// tela (em vez de branco/azul de marca), pedido explícito do time — no
    /// light mode o comportamento original (branco quando bateu a meta,
    /// azul de marca quando não) continua igual.
    private var todayRingColor: Color {
        guard colorScheme == .dark else {
            return dia.bateuMeta ? .white : calendarBlue
        }
        return AppTheme.screenBackgroundDark
    }

    private var fillTextColor: Color { .white }

    /// No light mode a trilha é bem clara, então o próprio azul do preenchimento
    /// já lê bem sobre ela (metade branca, metade azul). No dark mode a trilha
    /// já é uma versão escura desse mesmo azul, então branco continua sendo a
    /// única cor com contraste suficiente ali.
    private var trackTextColor: Color {
        guard !dia.isFuturo else { return .secondary }
        return colorScheme == .dark ? .white : calendarBlue
    }
}

/// Retângulo arredondado com uma "trilha" clara de fundo e um preenchimento
/// azul subindo de baixo até o percentual informado. `nil` = dia futuro, sem
/// trilha de progresso (cinza neutro).
private struct FillSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let percentual: Double?
    var cornerRadius: CGFloat = 4

    private var clampedFill: CGFloat {
        CGFloat(min(1, max(0, percentual ?? 0)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                trackColor
                if percentual != nil {
                    calendarBlue
                        .frame(height: geo.size.height * clampedFill)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Fundo translúcido: opacidade maior no dark mode porque o cartão por trás
    /// já é escuro — sem isso a trilha ficaria quase preta e o texto branco
    /// perderia contraste contra ela.
    private var trackColor: Color {
        guard percentual != nil else { return Color(.systemGray4) }
        return colorScheme == .dark ? calendarBlue.opacity(0.32) : calendarBlue.opacity(0.12)
    }
}

private struct DashedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(Color(.systemGray4))
        }
        .frame(height: 1)
    }
}

#Preview {
    HistoricoView()
}
