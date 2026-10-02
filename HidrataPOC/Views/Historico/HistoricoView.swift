import Charts
import SwiftData
import SwiftUI

/// Azul de marca usado no calendário do histórico (preenchimento, anel do dia
/// atual e contador de metas batidas).
private let calendarBlue = Color(red: 0.1098, green: 0.4627, blue: 0.9922)

/// Mesmo azul de accent da HomeView — usado na topBar para manter os botões idênticos.
private let accentBlue = Color(red: 0.1098, green: 0.4627, blue: 0.9922)

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

/// Deriva os dias do histórico a partir dos `IntakeLog` reais do usuário — cada dia
/// já ocorrido vira uma fração da meta diária (`metaDiariaML`); dias futuros ficam
/// sem dado (`nil`).
private enum HistoricoData {
    static func percentual(for date: Date, logs: [IntakeLog], metaDiariaML: Int, calendar: Calendar) -> Double? {
        let today = calendar.startOfDay(for: .now)
        let dayStart = calendar.startOfDay(for: date)
        guard dayStart <= today else { return nil }
        guard metaDiariaML > 0 else { return 0 }
        let total = HydrationMath.totalML(logs, on: dayStart, calendar: calendar)
        return Double(total) / Double(metaDiariaML)
    }

    static func generateMonth(for monthDate: Date, logs: [IntakeLog], metaDiariaML: Int, calendar: Calendar) -> [DiaHistorico] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }

        return range.compactMap { day in
            guard let date = calendar.date(bySetting: .day, value: day, of: monthDate) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            return DiaHistorico(date: dayStart, percentualMeta: percentual(for: dayStart, logs: logs, metaDiariaML: metaDiariaML, calendar: calendar))
        }
    }
}

private enum HistoricoCardPage {
    case calendario
    case semana
}

struct HistoricoView: View {
    let profile: UserProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var cardPage: HistoricoCardPage = .calendario
    @State private var selectedDay: DiaHistorico?
    @State private var showHelp = false
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var phraseIndex: Int = 0

    /// Mesmas frases da Home — o mascote precisa falar igual nas duas telas.
    private static let mascotPhrases: [String] = [
        "Nao bebe água não",

    ]

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

    private var monthDays: [DiaHistorico] {
        HistoricoData.generateMonth(for: displayedMonth, logs: userLogs, metaDiariaML: profile.metaDiariaML, calendar: calendar)
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

    private var streakDias: Int {
        HydrationMath.currentStreak(userLogs, metaDiariaML: profile.metaDiariaML, calendar: calendar)
    }

    /// Mesma meta ajustada pelo clima usada na Home — sem isso, o nível de água das
    /// duas telas diverge num dia quente (ver `HydrationMath.effectiveGoalML`).
    private var effectiveGoalML: Int {
        HydrationMath.effectiveGoalML(baseGoalML: profile.metaDiariaML, tempContext: tempContext)
    }

    private var todayProgress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        let total = HydrationMath.totalML(userLogs, on: .now, calendar: calendar)
        return min(1, Double(total) / Double(effectiveGoalML))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLLL yyyy"
        let raw = formatter.string(from: displayedMonth)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private var weeklyChartData: [(day: Date, totalML: Int)] {
        HydrationMath.dailyTotals(userLogs, days: 7, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    // Same layout as Home (`TabScreenLayout`), so the mascot and water
                    // match on both tabs and the card ends the same gap above the tab bar.
                    VStack(spacing: TabScreenLayout.spacing) {
                        topBar
                            .padding(.horizontal, 20)
                        topSection(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height))
                            .padding(.horizontal, 10)
                        calendarCard(height: max(TabScreenLayout.contentHeight(forVisibleHeight: geo.size.height), Self.minCalendarCardHeight))
                            .padding(.horizontal)
                    }
                    .padding(.bottom, TabScreenLayout.spacing)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .appScreenBackground()
            .navigationBarHidden(true)
        }
        .onAppear {
            guard tempContext == nil else { return }
            Task {
                tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
            }
        }
        .sheet(isPresented: $showHelp) { HistoricoHelpView() }
        .sheet(item: $selectedDay) { dia in
            DayDetailSheet(dia: dia, metaDiariaML: profile.metaDiariaML, userID: profile.userID, calendar: calendar)
                .trackSheetLifecycle(.historicoDayDetail, screen: .historico, userID: profile.userID, metadata: ["date": isoDate(dia.date)])
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                InteractionTracker.log("historico_help_tap", screen: .historico, userID: profile.userID, context: modelContext)
                showHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Ajuda")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(accentBlue)
                Text("\(streakDias)")
                    .font(.custom("Nunito", size: 15).bold())
                Text("dias")
                    .font(.custom("Nunito", size: 15))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
    }

    /// Mesmo recipiente da Home (mesma forma, altura e margens), enchendo com o
    /// progresso do dia. O cabeçalho fica fora do conteúdo da água (a refração
    /// achata o conteúdo e o vidro dos botões ficaria escuro).
    private var containerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 32, bottomTrailingRadius: 32, topTrailingRadius: 32, style: .continuous)
    }

    private func topSection(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            mascotPlaceholder(height: TabScreenLayout.mascotHeight(forWaterHeight: height))
        }
        .padding(.bottom, TabScreenLayout.mascotBottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            // O conteúdo do recipiente (mascote + shader da água) não tem fundo opaco
            // próprio, então uma `.shadow` direta nele sairia recortada e irregular.
            // Essa forma preenchida com a mesma cor do fundo fica escondida atrás do
            // recipiente e só deixa a sombra aparecer, contornando-o nos dois temas.
            containerShape
                .fill(AppTheme.screenBackground(for: colorScheme))
        }
        .waterContainer(
            level: todayProgress,
            in: containerShape,
            bleedsIntoTopSafeArea: true
        )
    }

    private func mascotPlaceholder(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(AppTheme.mascotImageName(for: todayProgress))
                .resizable()
                .scaledToFit()
                .frame(height: height)

            MascotSpeechBubble(text: Self.mascotPhrases[phraseIndex])
                .offset(x: 8, y: -8)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
        }
        .onAppear { phraseIndex = Int.random(in: 0..<Self.mascotPhrases.count) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeInOut(duration: 0.35)) {
                    phraseIndex = (phraseIndex + 1) % Self.mascotPhrases.count
                }
            }
        }
    }

    /// Below this the day cells would get too small; the screen scrolls instead.
    private static let minCalendarCardHeight: CGFloat = 330
    private static let gridRowSpacing: CGFloat = 10
    private static let gridColumnSpacing: CGFloat = 8

    /// Card com duas "páginas": o calendário do mês e um gráfico dos últimos
    /// 7 dias. Troca de página pela setinha (`pageToggleButton`, presente nos
    /// dois cabeçalhos) ou arrastando o card para o lado.
    private func calendarCard(height: CGFloat) -> some View {
        VStack(spacing: 14) {
            if cardPage == .calendario {
                calendarPageContent
            } else {
                weeklyChartPageContent
            }
        }
        .padding(20)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
        .simultaneousGesture(cardSwipeGesture)
    }

    private var calendarPageContent: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeader
            // 6-row months stretch their cells to fill the space the card leaves for
            // the grid. Shorter months use square cells (capped so they still fit),
            // centered vertically in that space.
            GeometryReader { geo in
                let rows = CGFloat((gridCells.count + 6) / 7)
                let fillHeight = max((geo.size.height - (rows - 1) * Self.gridRowSpacing) / rows, 26)
                let cellWidth = (geo.size.width - 6 * Self.gridColumnSpacing) / 7
                calendarGrid(cellHeight: rows >= 6 ? fillHeight : min(cellWidth, fillHeight))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .transition(.opacity)
    }

    private func calendarGrid(cellHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: Self.gridRowSpacing) {
            ForEach(Array(gridCells.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    DayCell(dia: cell, isToday: calendar.isDateInToday(cell.date), height: cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !cell.isFuturo else { return }
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

    private var weeklyChartPageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Últimos 7 dias")
                    .font(.baloo2ExtraBold(21))
                Spacer()
                pageToggleButton
            }
            HydrationChartView(dailyTotals: weeklyChartData, metaDiariaML: profile.metaDiariaML)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

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
            let toPage = cardPage == .calendario ? "semana" : "calendario"
            InteractionTracker.log("historico_page_toggle", screen: .historico, userID: profile.userID, metadata: ["method": "tap", "toPage": toPage], context: modelContext)
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

                let toPage = horizontal < 0 ? "semana" : "calendario"
                InteractionTracker.log("historico_page_toggle", screen: .historico, userID: profile.userID, metadata: ["method": "swipe", "toPage": toPage], context: modelContext)
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

    private func changeMonth(by value: Int) {
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

                Text("\(dayNumber)")
                    .font(.baloo2ExtraBold(14))
                    .foregroundStyle(numberColor)
                    .shadow(color: numberShadow, radius: 1, x: 0, y: 0)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(todayRingColor, lineWidth: isToday ? 2 : 0)
                    .padding(1)
            )
        }
        .frame(height: height)
    }

    private var todayRingColor: Color {
        dia.bateuMeta ? .white : calendarBlue
    }

    /// Cor única do número: branco quando o preenchimento domina (≥ 50%),
    /// caso contrário azul de marca (light) ou branco (dark) sobre a trilha clara.
    private var numberColor: Color {
        if dia.isFuturo { return .secondary }
        if clampedFill >= 0.5 { return .white }
        return colorScheme == .dark ? .white : calendarBlue
    }

    /// Sombra sutil que garante legibilidade na faixa de transição (~30–70%).
    private var numberShadow: Color {
        if dia.isFuturo { return .clear }
        return clampedFill >= 0.5
            ? .black.opacity(0.25)
            : (colorScheme == .dark ? .black.opacity(0.3) : .clear)
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
        return colorScheme == .dark ? calendarBlue.opacity(0.32) : Color(red: 0.8863, green: 0.9333, blue: 0.9922)
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

    private var hourlyBreakdown: [(hour: Int, ml: Int)] {
        let grouped = Dictionary(grouping: logs) { Calendar.current.component(.hour, from: $0.timestamp) }
        return grouped.map { (hour: $0.key, ml: $0.value.reduce(0) { $0 + $1.volumeML }) }.sorted { $0.hour < $1.hour }
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
                            ForEach(hourlyBreakdown, id: \.hour) { entry in
                                BarMark(
                                    x: .value("Hora", String(format: "%02d:00", entry.hour)),
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

            if logs.isEmpty {
                Text("Nenhum registro neste dia.")
                    .font(.nunitoBold(12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
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
    }

    private func deleteIntake(_ log: IntakeLog) {
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
                .foregroundStyle(calendarBlue)
                .frame(width: 30, height: 30)
                .background(calendarBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(.nunitoExtraBold(13))
                Text("\(log.tipoEntrada.capitalized) · \(log.volumeML) mL")
                    .font(.nunitoBold(12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
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
