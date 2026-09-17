import Charts
import SwiftUI

/// Azul de marca usado no calendário do histórico (preenchimento, anel do dia
/// atual e contador de metas batidas).
private let calendarBlue = Color(red: 0x3E / 255.0, green: 0x8F / 255.0, blue: 0xC7 / 255.0)

/// Meta diária mockada usada para converter os percentuais do histórico em
/// mL nos gráficos — substituir pelo `metaDiariaML` real do perfil quando o
/// histórico estiver persistido.
private let metaDiariaML = 2450

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

/// Um registro individual de consumo de água mockado, exibido na lista do
/// sheet de detalhe do dia — permite ao usuário apagar um registro lançado
/// errado, como faria com um `IntakeLog` real.
struct MockIntake: Identifiable {
    let id = UUID()
    let hour: Int
    let ml: Int

    var timeLabel: String { String(format: "%02d:00", hour) }
}

/// Gera dados mockados de histórico por mês. Sem integração com banco de dados
/// ainda — isto existe só para popular a tela enquanto o modelo real não chega.
enum HistoricoMockData {
    /// Padrão fixo de percentuais (proporção da meta diária bebida), repetido a
    /// cada 14 dias só para dar variedade visual ao mock.
    private static let padraoPercentual: [Double] = [
        1.0, 1.0, 0.45, 1.0, 1.0, 0.3, 1.0, 1.0, 1.0, 0.55, 1.0, 1.0, 1.0, 0.5,
    ]

    /// Distribuição relativa de consumo ao longo do dia (soma 1.0), usada só
    /// para desenhar o gráfico por horário no sheet de detalhe do dia — sem
    /// logs reais de horário ainda, então o formato é fixo (mais consumo no
    /// meio do dia) em vez de aleatório, para o gráfico ficar estável.
    private static let distribuicaoPorHora: [(hour: Int, weight: Double)] = [
        (8, 0.10), (10, 0.16), (12, 0.20), (14, 0.16), (16, 0.16), (18, 0.14), (20, 0.08),
    ]

    /// Mesmo cálculo usado tanto para popular o mês exibido quanto para os
    /// "últimos 7 dias" — dias futuros (após hoje) não têm dado (`nil`).
    static func percentual(for date: Date, calendar: Calendar) -> Double? {
        let today = calendar.startOfDay(for: .now)
        let dayStart = calendar.startOfDay(for: date)
        guard dayStart <= today else { return nil }
        let day = calendar.component(.day, from: dayStart)
        return padraoPercentual[(day - 1) % padraoPercentual.count]
    }

    static func generateMonth(for monthDate: Date, calendar: Calendar) -> [DiaHistorico] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }

        return range.compactMap { day in
            guard let date = calendar.date(bySetting: .day, value: day, of: monthDate) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            return DiaHistorico(date: dayStart, percentualMeta: percentual(for: dayStart, calendar: calendar))
        }
    }

    /// Últimos 7 dias corridos terminando hoje, independente do mês que o
    /// calendário está exibindo — usado no gráfico semanal do card.
    static func lastSevenDays(calendar: Calendar) -> [DiaHistorico] {
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DiaHistorico(date: date, percentualMeta: percentual(for: date, calendar: calendar))
        }
    }

    static func hourlyBreakdown(for dia: DiaHistorico, metaDiariaML: Int) -> [MockIntake] {
        let totalML = Double(metaDiariaML) * (dia.percentualMeta ?? 0)
        return distribuicaoPorHora.map { MockIntake(hour: $0.hour, ml: Int((totalML * $0.weight).rounded())) }
    }
}

private enum HistoricoCardPage {
    case calendario
    case semana
}

struct HistoricoView: View {
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var cardPage: HistoricoCardPage = .calendario
    @State private var selectedDay: DiaHistorico?

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

    private var weeklyChartData: [(day: Date, totalML: Int)] {
        HistoricoMockData.lastSevenDays(calendar: calendar).map {
            (day: $0.date, totalML: Int(Double(metaDiariaML) * ($0.percentualMeta ?? 0)))
        }
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
        .sheet(item: $selectedDay) { dia in
            DayDetailSheet(dia: dia)
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

    /// Card com duas "páginas": o calendário do mês e um gráfico dos últimos
    /// 7 dias. Troca de página pela setinha (`pageToggleButton`, presente nos
    /// dois cabeçalhos) ou arrastando o card para o lado.
    private var calendarCard: some View {
        VStack(spacing: 14) {
            if cardPage == .calendario {
                calendarPageContent
            } else {
                weeklyChartPageContent
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .simultaneousGesture(cardSwipeGesture)
    }

    private var calendarPageContent: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(gridCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        DayCell(dia: cell, isToday: calendar.isDateInToday(cell.date))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !cell.isFuturo else { return }
                                selectedDay = cell
                            }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            DashedDivider()
            legend
        }
        .transition(.opacity)
    }

    private var weeklyChartPageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Últimos 7 dias")
                    .font(.baloo2ExtraBold(21))
                Spacer()
                pageToggleButton
            }
            HydrationChartView(dailyTotals: weeklyChartData, metaDiariaML: metaDiariaML)
        }
        .transition(.opacity)
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

            pageToggleButton
        }
    }

    /// Setinha que alterna entre o calendário e o gráfico semanal — a mesma
    /// troca também acontece arrastando o card para o lado (`cardSwipeGesture`).
    private var pageToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                cardPage = cardPage == .calendario ? .semana : .calendario
            }
        } label: {
            Image(systemName: cardPage == .calendario ? "chevron.right" : "chevron.left")
                .font(.caption.bold())
                .foregroundStyle(calendarBlue)
                .frame(width: 26, height: 26)
                .background(calendarBlue.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(cardPage == .calendario ? "Ver estatísticas dos últimos 7 dias" : "Voltar para o calendário")
    }

    private var cardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 50 else { return }

                withAnimation(.easeInOut(duration: 0.2)) {
                    cardPage = horizontal < 0 ? .semana : .calendario
                }
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
        return dia.bateuMeta ? .white : calendarBlue
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

/// Sheet aberto ao tocar em um dia do calendário: detalha quanto da meta
/// diária foi bebido naquele dia, com um gráfico mockado por horário
/// (`HistoricoMockData.hourlyBreakdown`, já que ainda não há logs reais com
/// horário associados ao histórico).
private struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dia: DiaHistorico

    /// Cópia local e mutável dos registros mockados do dia — apagar aqui só
    /// afeta esta sessão do sheet (não há persistência real ainda), mas o
    /// total e o gráfico acima reagem imediatamente à remoção, como
    /// aconteceria com um `IntakeLog` de verdade.
    @State private var intakes: [MockIntake]

    init(dia: DiaHistorico) {
        self.dia = dia
        _intakes = State(initialValue: HistoricoMockData.hourlyBreakdown(for: dia, metaDiariaML: metaDiariaML))
    }

    private var totalML: Int {
        intakes.reduce(0) { $0 + $1.ml }
    }

    private var atingiuMeta: Bool {
        totalML >= metaDiariaML
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        let raw = formatter.string(from: dia.date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateTitle)
                            .font(.baloo2ExtraBold(21))
                        Text("\(totalML) mL de \(metaDiariaML) mL da meta")
                            .font(.nunitoExtraBold(13))
                            .foregroundStyle(atingiuMeta ? calendarBlue : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Consumo ao longo do dia")
                            .font(.nunitoExtraBold(12.5))
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(intakes) { entry in
                                BarMark(
                                    x: .value("Hora", entry.timeLabel),
                                    y: .value("mL", entry.ml)
                                )
                                .foregroundStyle(calendarBlue)
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 200)
                    }

                    intakeList
                }
                .padding(20)
            }
            .appScreenBackground()
            .navigationTitle("Detalhe do dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    private var intakeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Registros do dia")
                .font(.nunitoExtraBold(12.5))
                .foregroundStyle(.secondary)

            if intakes.isEmpty {
                Text("Nenhum registro — todos foram apagados.")
                    .font(.nunitoBold(12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(intakes) { intake in
                        IntakeRow(intake: intake) { deleteIntake(intake) }
                        if intake.id != intakes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func deleteIntake(_ intake: MockIntake) {
        withAnimation(.easeInOut(duration: 0.2)) {
            intakes.removeAll { $0.id == intake.id }
        }
    }
}

/// Uma linha de registro no sheet de detalhe do dia, com botão de apagar —
/// para o usuário remover um consumo lançado errado.
private struct IntakeRow: View {
    let intake: MockIntake
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.footnote)
                .foregroundStyle(calendarBlue)
                .frame(width: 30, height: 30)
                .background(calendarBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(intake.timeLabel)
                    .font(.nunitoExtraBold(13))
                Text("\(intake.ml) mL")
                    .font(.nunitoBold(12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apagar registro das \(intake.timeLabel)")
        }
        .padding(.vertical, 10)
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
