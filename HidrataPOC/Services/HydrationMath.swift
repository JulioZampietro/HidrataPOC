import Foundation

/// Pure helpers over already-fetched `IntakeLog` arrays — kept free of SwiftData so
/// they're trivial to call from anywhere (scheduler, views, previews) with plain data.
enum HydrationMath {
    static func totalML(_ logs: [IntakeLog], on day: Date, calendar: Calendar = .current) -> Int {
        logs
            .filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            .reduce(0) { $0 + $1.volumeML }
    }

    static func deficitML(metaDiariaML: Int, consumidoHojeML: Int) -> Int {
        max(0, metaDiariaML - consumidoHojeML)
    }

    /// Total por dia numa passada só, com um `startOfDay` por registro — a mesma
    /// técnica de `HistoricoData.generateMonth`. `currentStreak` caminha até 365 dias e
    /// cada dia filtrava a lista inteira com `Calendar.isDate(inSameDayAs:)`, o que
    /// torna a sequência O(dias × registros): com um ano de uso, mais de um milhão de
    /// comparações de calendário por avaliação do `body` que a lê.
    static func totalsByDay(_ logs: [IntakeLog], calendar: Calendar = .current) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        totals.reserveCapacity(logs.count)
        for log in logs {
            totals[calendar.startOfDay(for: log.timestamp), default: 0] += log.volumeML
        }
        return totals
    }

    static func minutesSinceLastIntake(_ logs: [IntakeLog], now: Date = .now) -> Int? {
        guard let last = logs.map(\.timestamp).max() else { return nil }
        return max(0, Int(now.timeIntervalSince(last) / 60))
    }

    /// Computes an apparent temperature that accounts for both humidity extremes:
    ///
    /// - **Dry air (RH < 40 %, T ≥ 25 °C)**: insensible losses (respiration + skin
    ///   evaporation) rise as RH drops. Modelled as a linear bonus of up to +3 °C
    ///   at 0 % RH (≈ +150 mL at 50 mL/°C per degree).
    ///
    /// - **Hot + humid (RH ≥ 40 %, T ≥ 25 °C)**: sweat evaporation is impaired;
    ///   uses the Rothfusz Heat Index regression.
    ///
    /// Returns `tempC` unchanged when T < 25 °C (conditions don't warrant an
    /// adjustment, and the Rothfusz formula is unreliable below that range).
    static func heatIndex(tempC: Double, humidityFraction: Double) -> Double {
        let rh = humidityFraction * 100
        guard tempC >= 25 else { return tempC }

        if rh < 40 {
            // Linear dry-air penalty: 0 at 40 % → +3 °C at 0 % RH
            let dryBoost = (40 - rh) / 40 * 3.0
            return tempC + dryBoost
        }

        // Rothfusz Heat Index (reliable for T ≥ 25 °C, RH ≥ 40 %)
        let T = tempC, R = rh
        return -8.78469475556
            + 1.61139411  * T
            + 2.338549    * R
            - 0.14611605  * T * R
            - 0.012308094 * T * T
            - 0.016424828 * R * R
            + 0.002211732 * T * T * R
            + 0.00072546  * T * R * R
            - 0.000003582 * T * T * R * R
    }

    /// Extra mL to add when today's forecast Heat Index exceeds `Constants.baselineMaxTempC`.
    /// When `humidityFraction` is provided the Heat Index replaces the raw temperature,
    /// so a humid 30 °C day produces a larger adjustment than a dry 30 °C day.
    /// Returns 0 when conditions are at or below the baseline.
    static func temperatureAdjustmentML(todayMaxC: Double, humidityFraction: Double = 0) -> Int {
        let apparent = heatIndex(tempC: todayMaxC, humidityFraction: humidityFraction)
        let excess = max(0, apparent - Constants.baselineMaxTempC)
        return Int((excess * Double(Constants.tempAdjustmentMLPerDegree)).rounded())
    }

    /// Meta diária ajustada pelo clima (`baseGoalML` + o ajuste de temperatura do dia).
    /// Centralizado aqui pra Home e Histórico calcularem o mesmo nível de água/progresso
    /// do dia a partir do mesmo `TemperatureAdjustmentContext`, em vez de cada tela ter
    /// sua própria conta e divergir entre si. Sem previsão carregada, usa o ajuste já
    /// gravado pra hoje (`DailyGoal`), pra meta não "pular" enquanto o clima carrega.
    static func effectiveGoalML(baseGoalML: Int, tempContext: TemperatureAdjustmentContext?, recordedAdjustmentML: Int? = nil) -> Int {
        baseGoalML + (tempContext?.adjustmentML ?? recordedAdjustmentML ?? 0)
    }

    static func dailyTotals(_ logs: [IntakeLog], days: Int, calendar: Calendar = .current, now: Date = .now) -> [(day: Date, totalML: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let total = totalML(logs, on: day, calendar: calendar)
            return (day, total)
        }
    }

    /// Consecutive days, walking backward from today, whose total intake met or
    /// exceeded that day's own goal (`goalML(day)` — see `DailyGoalResolver`, so a goal
    /// edited today never re-judges past days). If today's goal is already met, today
    /// counts; if not yet (user may still drink more), the count starts from yesterday
    /// so the streak is not broken mid-day. `logs` should already be filtered to the
    /// target user.
    static func currentStreak(_ logs: [IntakeLog], goalML: (Date) -> Int, calendar: Calendar = .current, now: Date = .now, maxDays: Int = 365) -> Int {
        currentStreak(totalsByDay: totalsByDay(logs, calendar: calendar), goalML: goalML, calendar: calendar, now: now, maxDays: maxDays)
    }

    /// Variante que recebe os totais já agregados (ver `totalsByDay`), para quem avalia
    /// a sequência várias vezes a partir da mesma lista de registros não pagar a
    /// agregação de novo a cada chamada.
    static func currentStreak(totalsByDay totals: [Date: Int], goalML: (Date) -> Int, calendar: Calendar = .current, now: Date = .now, maxDays: Int = 365) -> Int {
        let today = calendar.startOfDay(for: now)
        let todayMet = metGoal(totals, on: today, goalML: goalML)
        guard let startDate = todayMet ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var count = 0
        // Sempre reduzido a início de dia: `totals` é indexado por `startOfDay`, e
        // subtrair um dia numa virada de horário de verão pode cair às 23h do dia
        // anterior — uma chave que não existe no dicionário.
        var checkDate = calendar.startOfDay(for: startDate)
        for _ in 0..<maxDays {
            guard metGoal(totals, on: checkDate, goalML: goalML) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = calendar.startOfDay(for: previous)
        }
        return count
    }

    /// Há uma sequência ativa vinda de antes de hoje (`currentStreak` contando só até
    /// ontem é > 0) e hoje ainda não bateu a meta — ou seja, ela quebra se o dia acabar
    /// assim. Usa `firesAt` (não `.now`) pra ser puro e testável com qualquer horário.
    static func isStreakAtRisk(_ logs: [IntakeLog], goalML: (Date) -> Int, calendar: Calendar = .current, firesAt: Date) -> Bool {
        let totals = totalsByDay(logs, calendar: calendar)
        guard !metGoal(totals, on: calendar.startOfDay(for: firesAt), goalML: goalML) else { return false }
        guard goalML(firesAt) > 0 else { return false }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: firesAt)) else { return false }
        return currentStreak(totalsByDay: totals, goalML: goalML, calendar: calendar, now: yesterday) > 0
    }

    /// `day` já deve vir normalizado por `startOfDay` no mesmo calendário que gerou
    /// `totals`, que é indexado por início de dia.
    private static func metGoal(_ totals: [Date: Int], on day: Date, goalML: (Date) -> Int) -> Bool {
        let goal = goalML(day)
        return goal > 0 && (totals[day] ?? 0) >= goal
    }
}
