import Charts
import SwiftData
import SwiftUI

/// Azul de marca usado no calendário do histórico (preenchimento, anel do dia
/// atual e contador de metas batidas).

struct DiaHistorico: Identifiable {
    let id = UUID()
    let date: Date
    /// Percentual da meta diária de hidratação atingido nesse dia (1.0 = 100%).
    /// `nil` quando o dia ainda não aconteceu — não há o que mostrar.
    let percentualMeta: Double?

    var isFuturo: Bool { percentualMeta == nil }
    var bateuMeta: Bool { (percentualMeta ?? 0) >= 1.0 }
}

/// Deriva os dias do histórico a partir dos `IntakeLog` reais do usuário — cada dia
/// já ocorrido vira uma fração da meta daquele dia (`goals`, ver `DailyGoalResolver`);
/// dias futuros ficam sem dado (`nil`).
private enum HistoricoData {
    static func percentual(for dayStart: Date, totalML: Int, goals: DailyGoalResolver, today: Date) -> Double? {
        guard dayStart <= today else { return nil }
        let goalML = goals.goalML(on: dayStart)
        guard goalML > 0 else { return 0 }
        return Double(totalML) / Double(goalML)
    }

    /// Roda a cada atualização da tela (inclusive no meio do arrasto entre as páginas), então
    /// soma os registros do mês por dia numa passada só: comparar datas é barato, e só os
    /// registros do mês pagam o `startOfDay`. Antes, cada um dos ~31 dias filtrava todos os
    /// registros com o calendário, e o arrasto pra cá travava.
    static func generateMonth(for monthDate: Date, logs: [IntakeLog], goals: DailyGoalResolver, calendar: Calendar) -> [DiaHistorico] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate),
              let month = calendar.dateInterval(of: .month, for: monthDate) else { return [] }

        var totals: [Date: Int] = [:]
        for log in logs {
            let timestamp = log.timestamp
            guard timestamp >= month.start, timestamp < month.end else { continue }
            totals[calendar.startOfDay(for: timestamp), default: 0] += log.volumeML
        }

        let today = calendar.startOfDay(for: .now)
        return range.compactMap { day in
            guard let date = calendar.date(bySetting: .day, value: day, of: monthDate) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            return DiaHistorico(date: dayStart, percentualMeta: percentual(for: dayStart, totalML: totals[dayStart] ?? 0, goals: goals, today: today))
        }
    }
}

private enum HistoricoCardPage {
    case calendario
    case semana
}

struct HistoricoView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @Query private var allDailyGoals: [DailyGoal]
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var cardPage: HistoricoCardPage = .calendario
    @State private var selectedDay: DiaHistorico?
    @State private var tempContext: TemperatureAdjustmentContext?
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        cal.firstWeekday = 1
        return cal
    }

    private let weekdaySymbols = ["D", "S", "T", "Q", "Q", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing), count: 7)

    private var userLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID }
    }

    private var dailyGoals: [DailyGoal] {
        allDailyGoals.filter { $0.userID == profile.userID }
    }

    /// Cada dia passado é julgado pela meta gravada pra ele — editar a meta hoje não
    /// muda o histórico nem a sequência.
    private var goalResolver: DailyGoalResolver {
        DailyGoalResolver(goals: dailyGoals, todayGoalML: effectiveGoalML, fallbackGoalML: profile.metaDiariaML, calendar: calendar)
    }

    private var monthDays: [DiaHistorico] {
        HistoricoData.generateMonth(for: displayedMonth, logs: userLogs, goals: goalResolver, calendar: calendar)
    }

    /// O que o calendário mostra do mês, calculado uma vez por atualização do `body`. Os
    /// `GeometryReader` desta tela refazem o conteúdo a cada frame enquanto a página desliza
    /// (o arrasto entre Home e Histórico); se o mês fosse calculado lá dentro, o arrasto travava.
    private struct MonthSummary {
        let cells: [DiaHistorico?]
        let metasBatidas: Int
        let title: String
    }

    private var monthSummary: MonthSummary {
        let days = monthDays
        var cells = days.map { Optional($0) }
        if let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) {
            let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
            cells = Array(repeating: nil, count: (weekdayOfFirst + 7) % 7) + cells
        }
        return MonthSummary(cells: cells, metasBatidas: days.filter(\.bateuMeta).count, title: monthTitle)
    }

    /// True once today's temperature adjustment has already been fetched and locked
    /// in (see `DailyGoal.recordToday`) — at that point a fresh WeatherKit call would
    /// only repeat work `recordedAdjustmentML` already covers, so it's skipped.
    private var isTodaysAdjustmentLocked: Bool {
        let key = DailyGoal.dayKey(for: .now, calendar: calendar)
        return dailyGoals.first { $0.dayKey == key }?.adjustmentLocked ?? false
    }

    /// Mesma meta ajustada pelo clima usada na Home — sem isso, o nível de água das
    /// duas telas diverge num dia quente (ver `HydrationMath.effectiveGoalML`).
    private var effectiveGoalML: Int {
        HydrationMath.effectiveGoalML(
            baseGoalML: profile.metaDiariaML,
            tempContext: tempContext,
            recordedAdjustmentML: DailyGoalResolver.recordedAdjustmentML(in: dailyGoals, on: .now, calendar: calendar)
        )
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLLL yyyy"
        let raw = formatter.string(from: displayedMonth)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private var weeklyChartData: [(day: Date, totalML: Int, goalML: Int)] {
        let goals = goalResolver
        return HydrationMath.dailyTotals(userLogs, days: 7, calendar: calendar)
            .map { (day: $0.day, totalML: $0.totalML, goalML: goals.goalML(on: $0.day)) }
    }

    var body: some View {
        let month = monthSummary
        let chartData = cardPage == .semana ? weeklyChartData : []
        GeometryReader { geo in
            // Same layout as Home (`TabScreenLayout`): the water container
            // (`WaterHeaderView`) is drawn by `RootView`, fixed on top of both pages,
            // so this only keeps its space; the card ends the same gap above the
            // bottom safe area.
            VStack(spacing: TabScreenLayout.spacing) {
                Color.clear
                    .frame(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height, safeAreaTop: geo.safeAreaInsets.top))
                calendarCard(height: TabScreenLayout.contentHeight(forVisibleHeight: geo.size.height), month: month, chartData: chartData)
                    .padding(.horizontal)
            }
            .padding(.top, TabScreenLayout.waterTop(safeAreaTop: geo.safeAreaInsets.top))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .appScreenBackground()
        .onAppear {
            guard tempContext == nil, !isTodaysAdjustmentLocked else { return }
            Task {
                tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
            }
        }
        .sheet(item: $selectedDay) { dia in
            DayDetailSheet(dia: dia, metaDiariaML: goalResolver.goalML(on: dia.date), userID: profile.userID, calendar: calendar)
                .trackSheetLifecycle(.historicoDayDetail, screen: .historico, userID: profile.userID, metadata: ["date": isoDate(dia.date)])
        }
    }

    private static let gridRowSpacing: CGFloat = 10
    private static let gridColumnSpacing: CGFloat = 8

    /// Card com duas "páginas": o calendário do mês e um gráfico dos últimos
    /// 7 dias. Troca de página pela setinha (`pageToggleButton`, presente nos
    /// dois cabeçalhos) ou arrastando o card para o lado.
    private func calendarCard(height: CGFloat, month: MonthSummary, chartData: [(day: Date, totalML: Int, goalML: Int)]) -> some View {
        VStack(spacing: 14) {
            if cardPage == .calendario {
                calendarPageContent(month)
            } else {
                weeklyChartPageContent(chartData)
            }
        }
        .padding(20)
        // O calendário tem células de tamanho fixo e o cartão uma altura calculada: nos
        // tamanhos de acessibilidade os números e o título do mês estourariam. O teto é
        // o maior tamanho "normal"; o resto da tela continua escalando livremente.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
    }

    private func calendarPageContent(_ month: MonthSummary) -> some View {
        VStack(spacing: 14) {
            monthHeader(month)
            weekdayHeader
            // 6-row months stretch their cells to fill the space the card leaves for
            // the grid. Shorter months use square cells (capped so they still fit),
            // centered vertically in that space.
            GeometryReader { geo in
                let rows = CGFloat((month.cells.count + 6) / 7)
                let fillHeight = max((geo.size.height - (rows - 1) * Self.gridRowSpacing) / rows, 26)
                let cellWidth = (geo.size.width - 6 * Self.gridColumnSpacing) / 7
                calendarGrid(month.cells, cellHeight: rows >= 6 ? fillHeight : min(cellWidth, fillHeight))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .transition(.opacity)
    }

    private func calendarGrid(_ cells: [DiaHistorico?], cellHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: Self.gridRowSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    DayCell(dia: cell, isToday: calendar.isDateInToday(cell.date), height: cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !cell.isFuturo else {
                                Haptic.warning.play() // dia que ainda não chegou
                                return
                            }
                            Haptic.tap.play()
                            InteractionTracker.log(
                                "historico_day_tap",
                                screen: .historico,
                                userID: profile.userID,
                                metadata: [
                                    "date": isoDate(cell.date),
                                    "metGoal": "\(cell.bateuMeta)",
                                    "isToday": "\(calendar.isDateInToday(cell.date))",
                                ],
                                context: modelContext
                            )
                            selectedDay = cell
                        }
                } else {
                    Color.clear.frame(height: cellHeight)
                }
            }
        }
    }

    private func weeklyChartPageContent(_ chartData: [(day: Date, totalML: Int, goalML: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Últimos 7 dias")
                    .font(AppFont.displayTitle)
                Spacer()
                pageToggleButton
            }
            HydrationChartView(dailyTotals: chartData)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }

    private func monthHeader(_ month: MonthSummary) -> some View {
        HStack {
            HStack(spacing: 6) {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .touchTarget()
                }
                .accessibilityLabel("Mês anterior")

                Text(month.title)
                    .font(AppFont.displayTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .touchTarget()
                }
                .accessibilityLabel("Próximo mês")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .tint(.secondary)

            Spacer()

            Text("\(month.metasBatidas) metas batidas")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appAccentText)

            pageToggleButton
        }
    }

    /// Setinha que alterna entre o calendário e o gráfico semanal. Arrastar o card
    /// para o lado não troca de página: esse gesto volta para a Home.
    private var pageToggleButton: some View {
        Button {
            Haptic.selection.play()
            let toPage = cardPage == .calendario ? "semana" : "calendario"
            InteractionTracker.log("historico_page_toggle", screen: .historico, userID: profile.userID, metadata: ["method": "tap", "toPage": toPage], context: modelContext)
            withAnimation(.easeInOut(duration: 0.2)) {
                cardPage = cardPage == .calendario ? .semana : .calendario
            }
        } label: {
            Image(systemName: cardPage == .calendario ? "chevron.right" : "chevron.left")
                .font(.caption.bold())
                .foregroundStyle(Color.appAccentText)
                .frame(width: 26, height: 26)
                .background(Color.appAccent.opacity(0.12), in: Circle())
                .touchTarget(visibleSize: 26)
        }
        .accessibilityLabel(cardPage == .calendario ? "Ver estatísticas dos últimos 7 dias" : "Voltar para o calendário")
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.appSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func changeMonth(by value: Int) {
        Haptic.selection.play()
        InteractionTracker.log("historico_month_nav", screen: .historico, userID: profile.userID, metadata: ["direction": value < 0 ? "prev" : "next"], context: modelContext)
        guard let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = newDate
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }
}

/// Célula de um dia no calendário: preenchida de baixo pra cima proporcionalmente
/// ao percentual da meta diária que o usuário bebeu naquele dia (0% vazia,
/// 100% totalmente cheia), como um copo se enchendo.
private struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let dia: DiaHistorico
    let isToday: Bool
    let height: CGFloat

    private var dayNumber: Int {
        Calendar.current.component(.day, from: dia.date)
    }

    private var clampedFill: Double {
        min(1, max(0, dia.percentualMeta ?? 0))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                FillSwatch(percentual: dia.percentualMeta, cornerRadius: 12)

                dayLabel(color: trackInk, in: geo.size)

                // No claro o número é azul sobre a trilha e branco sobre o preenchimento: o
                // mesmo número é desenhado duas vezes e a versão branca é recortada na
                // altura do preenchimento (a mesma ideia da barra de progresso da Home).
                // Isso vale em qualquer percentual — com ~50% a fronteira passa bem no
                // meio do dígito, e uma cor única perdia contraste numa das metades.
                if needsFillLayer {
                    dayLabel(color: .white, in: geo.size)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(width: geo.size.width, height: geo.size.height * clampedFill)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(todayRingColor, lineWidth: isToday ? 2 : 0)
                    .padding(1)
            )
        }
        .frame(height: height)
    }

    private func dayLabel(color: Color, in size: CGSize) -> some View {
        Text("\(dayNumber)")
            .font(AppFont.displayNumber)
            .lineLimit(1)
            .minimumScaleFactor(0.8) // 14 pt × 0.8 ≈ 11 pt (mínimo do HIG)
            .foregroundStyle(color)
            .frame(width: size.width, height: size.height)
    }

    private var todayRingColor: Color {
        dia.bateuMeta ? .white : Color.appAccent
    }

    /// Tinta do número sobre a trilha (a parte ainda não preenchida). No escuro a trilha
    /// é o azul de marca a 32% sobre o cartão escuro e o preenchimento é o azul cheio:
    /// branco passa de 5:1 nos dois, então não precisa de segunda camada.
    private var trackInk: Color {
        if dia.isFuturo { return Color.appSecondary }
        return colorScheme == .dark ? .white : Color.appAccentText
    }

    private var needsFillLayer: Bool {
        !dia.isFuturo && clampedFill > 0 && colorScheme != .dark
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
                    Color.appAccent
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
        guard percentual != nil else { return Color(.systemGray5) }
        return colorScheme == .dark ? Color.appAccent.opacity(0.32) : Color(red: 0.8863, green: 0.9333, blue: 0.9922)
    }
}

/// Sheet aberto ao tocar em um dia do calendário: detalha quanto da meta diária
/// foi bebido naquele dia, com um gráfico por horário e a lista dos `IntakeLog`
/// reais do dia — reativa a `@Query`, então apagar um registro aqui atualiza a
/// tela (e o calendário por trás dela) imediatamente. Também é aberto pela Home,
/// ao tocar na barra de progresso, com os registros de hoje.
struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let dia: DiaHistorico
    let metaDiariaML: Int
    @Query private var logs: [IntakeLog]

    init(dia: DiaHistorico, metaDiariaML: Int, userID: String, calendar: Calendar) {
        self.dia = dia
        self.metaDiariaML = metaDiariaML
        let dayStart = calendar.startOfDay(for: dia.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let predicate = #Predicate<IntakeLog> { $0.userID == userID && $0.timestamp >= dayStart && $0.timestamp < dayEnd }
        _logs = Query(filter: predicate, sort: \IntakeLog.timestamp)
    }

    private var totalML: Int {
        logs.reduce(0) { $0 + $1.volumeML }
    }

    private var atingiuMeta: Bool {
        totalML >= metaDiariaML
    }

    /// Preenche as horas sem registro, dentro da janela ativa do dia (do primeiro
    /// ao último gole), com 0 mL — sem isso, as horas eram colocadas em um eixo
    /// categórico (strings "08:00", "14:00") igualmente espaçadas, fazendo horas
    /// distantes parecerem vizinhas. Com `hour: Int` como valor numérico, o eixo X
    /// passa a refletir o tempo real entre os registros.
    private var hourlyBreakdown: [(hour: Int, ml: Int)] {
        let grouped = Dictionary(grouping: logs) { Calendar.current.component(.hour, from: $0.timestamp) }
        guard let firstHour = grouped.keys.min(), let lastHour = grouped.keys.max() else { return [] }
        return (firstHour...lastHour).map { hour in
            (hour: hour, ml: grouped[hour]?.reduce(0) { $0 + $1.volumeML } ?? 0)
        }
    }

    /// Domínio do eixo X com 1h de folga de cada lado dos dados — sem isso, com um
    /// só horário de registro no dia, `firstHour == lastHour` faria o domínio ter
    /// largura zero e o Charts não desenha nada num eixo contínuo sem amplitude.
    /// Dia sem registros: o gráfico vazio cobre o dia útil (6h às 22h).
    private static let emptyDayHours = 6...22
    private var domainStart: Int { hourlyBreakdown.first.map { $0.hour - 1 } ?? Self.emptyDayHours.lowerBound }
    private var domainEnd: Int { hourlyBreakdown.last.map { $0.hour + 1 } ?? Self.emptyDayHours.upperBound }

    /// Soma corrida do consumo — 500 mL às 8h e mais 500 mL às 9h aparece como
    /// 500 às 8h e 1000 às 9h, não dois picos iguais. Começa num ponto sintético
    /// no início do domínio (0 mL) e termina com outro no fim, pra área ocupar o
    /// gráfico inteiro em vez de parar (ou começar) no meio do eixo.
    private var cumulativeSeries: [(hour: Int, totalML: Int)] {
        guard !hourlyBreakdown.isEmpty else { return [] }
        var running = 0
        var points: [(hour: Int, totalML: Int)] = [(hour: domainStart, totalML: 0)]
        for entry in hourlyBreakdown {
            running += entry.ml
            points.append((hour: entry.hour, totalML: running))
        }
        points.append((hour: domainEnd, totalML: running))
        return points
    }

    private var chartYUpperBound: Int {
        // Sem registros, o eixo mostra até a meta do dia, para o gráfico vazio ter escala.
        guard !cumulativeSeries.isEmpty else { return max(metaDiariaML, 1) }
        return max(cumulativeSeries.map(\.totalML).max() ?? 0, 1) * 6 / 5
    }

    /// Marcas do eixo X a cada ~1/4 da janela, pra não lotar o eixo com uma
    /// legenda por hora.
    private var hourlyAxisMarks: [Int] {
        let span = domainEnd - domainStart
        guard span > 0 else { return [domainStart] }
        let step = max(1, span / 4)
        return Array(stride(from: domainStart, through: domainEnd, by: step))
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
                            .font(AppFont.displayTitle)
                        Text("\(totalML) mL de \(metaDiariaML) mL da meta")
                            .font(AppFont.footnoteStrong)
                            .foregroundStyle(atingiuMeta ? Color.appAccentText : Color.appSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Consumo ao longo do dia")
                            .font(AppFont.footnoteStrong)
                            .foregroundStyle(Color.appSecondary)

                        Chart {
                            ForEach(cumulativeSeries, id: \.hour) { point in
                                AreaMark(
                                    x: .value("Hora", point.hour),
                                    y: .value("Consumo", point.totalML)
                                )
                                .interpolationMethod(.monotone)
                                // Mesmo azul de marca das barras antigas (`LinearGradient.waterHeader`),
                                // só diluído pra área — não um azul inventado à parte.
                                .foregroundStyle(LinearGradient.waterHeader.opacity(0.35))
                            }
                            ForEach(cumulativeSeries, id: \.hour) { point in
                                LineMark(
                                    x: .value("Hora", point.hour),
                                    y: .value("Consumo", point.totalML)
                                )
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .foregroundStyle(LinearGradient.waterHeader)
                            }
                        }
                        .chartXScale(domain: domainStart...domainEnd)
                        .chartXAxis {
                            AxisMarks(values: hourlyAxisMarks) { value in
                                AxisValueLabel {
                                    if let hour = value.as(Int.self) {
                                        Text("\(hour)h")
                                            .font(AppFont.caption)
                                            .foregroundStyle(Color.appSecondary)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.appSecondary.opacity(0.18))
                                AxisValueLabel {
                                    if let ml = value.as(Int.self) {
                                        Text("\(ml)")
                                            .font(AppFont.caption)
                                            .foregroundStyle(Color.appSecondary)
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...chartYUpperBound)
                        .frame(height: 180)
                        // Dia sem registros: o gráfico aparece vazio, com o aviso por cima.
                        .overlay {
                            if logs.isEmpty {
                                Text(Calendar.current.isDateInToday(dia.date) ? "Sem registros ainda" : "Sem registros neste dia")
                                    .font(AppFont.footnoteStrong)
                                    .foregroundStyle(Color.appSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                        }
                    }
                    .padding(16)
                    .panelBackground()

                    // Sem registros, o aviso já está no gráfico; a lista só aparece com o que listar.
                    if !logs.isEmpty {
                        intakeList
                    }
                }
                // Garante a largura total mesmo que nada aqui peça: sem isso a folha encolhia até
                // o texto mais largo, deixando faixas brancas dos lados.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .appScreenBackground()
            .navigationTitle("Detalhe do dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                }
            }
        }
    }

    private var intakeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Registros do dia")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appSecondary)

            VStack(spacing: 0) {
                ForEach(logs) { log in
                    IntakeRow(log: log) { deleteIntake(log) }
                    if log.id != logs.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func deleteIntake(_ log: IntakeLog) {
        Haptic.destructive.play()
        Task { await NotificationScheduler.shared.deleteIntake(log, context: modelContext) }
    }
}

/// Uma linha de registro no sheet de detalhe do dia, com botão de apagar —
/// para o usuário remover um consumo lançado errado.
private struct IntakeRow: View {
    let log: IntakeLog
    let onDelete: () -> Void

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: log.timestamp)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.footnote)
                .foregroundStyle(Color.appAccentText)
                .frame(width: 30, height: 30)
                .background(Color.appAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(AppFont.footnoteStrong)
                Text("\(log.tipoEntrada.capitalized) · \(log.volumeML) mL")
                    .font(AppFont.footnoteStrong)
                    .foregroundStyle(Color.appSecondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.appDestructive)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apagar registro das \(timeLabel)")
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HistoricoView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}

extension View {
    /// Amplia a área de toque para o mínimo de 44×44 pt do HIG sem mexer no desenho nem no
    /// espaço que o controle ocupa no layout: a margem negativa devolve o excesso, e o
    /// `contentShape` faz a área extra continuar recebendo toques.
    func touchTarget(visibleSize: CGFloat? = nil) -> some View {
        modifier(TouchTargetModifier(visibleSize: visibleSize))
    }
}

private struct TouchTargetModifier: ViewModifier {
    let visibleSize: CGFloat?
    private let minimum: CGFloat = 44

    func body(content: Content) -> some View {
        if let visibleSize {
            let extra = max(0, minimum - visibleSize) / 2
            content
                .frame(width: minimum, height: minimum)
                .contentShape(Rectangle())
                .padding(-extra)
        } else {
            // Ícone sem moldura própria: mede 44×44 e devolve o excesso na horizontal.
            content
                .frame(width: minimum, height: minimum)
                .contentShape(Rectangle())
                .padding(.horizontal, -16)
                .padding(.vertical, -13)
        }
    }
}
