import Charts
import SwiftData
import SwiftUI

/// Azul de marca usado no calendário do histórico (preenchimento, anel do dia
/// atual e contador de metas batidas).
private let calendarBlue = Color(red: 0x3E / 255.0, green: 0x8F / 255.0, blue: 0xC7 / 255.0)

/// Mesmo azul de accent da HomeView — usado na topBar para manter os botões idênticos.
private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

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

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        cal.firstWeekday = 1
        return cal
    }

    private let weekdaySymbols = ["D", "S", "T", "Q", "Q", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

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

    /// Dias já passados neste mês que não bateram a meta.
    private var diasPerdidos: Int {
        monthDays.filter { !$0.isFuturo && !$0.bateuMeta }.count
    }

    private var streakDias: Int {
        HydrationMath.currentStreak(userLogs, metaDiariaML: profile.metaDiariaML, calendar: calendar)
    }

    private var todayProgress: Double {
        guard profile.metaDiariaML > 0 else { return 0 }
        let total = HydrationMath.totalML(userLogs, on: .now, calendar: calendar)
        return min(1, Double(total) / Double(profile.metaDiariaML))
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
            DayDetailSheet(dia: dia, metaDiariaML: profile.metaDiariaML, userID: profile.userID, calendar: calendar)
                .trackSheetLifecycle(.historicoDayDetail, screen: .historico, userID: profile.userID, metadata: ["date": isoDate(dia.date)])
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                InteractionTracker.log("historico_help_tap", screen: .historico, userID: profile.userID, context: modelContext)
                // Placeholder: abrir ajuda/tutorial do histórico no futuro.
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground), in: Circle())
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
            .background(Color(.secondarySystemBackground), in: Capsule())
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

    private var mascotPlaceholder: some View {
        Image(AppTheme.mascotImageName(for: todayProgress))
            .resizable()
            .scaledToFit()
            .frame(height: 190)
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
            HydrationChartView(dailyTotals: weeklyChartData, metaDiariaML: profile.metaDiariaML)
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

/// Sheet aberto ao tocar em um dia do calendário: detalha quanto da meta diária
/// foi bebido naquele dia, com um gráfico por horário e a lista dos `IntakeLog`
/// reais do dia — reativa a `@Query`, então apagar um registro aqui atualiza a
/// tela (e o calendário por trás dela) imediatamente.
private struct DayDetailSheet: View {
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
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HistoricoView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
