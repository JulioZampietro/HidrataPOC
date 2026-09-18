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

    static func minutesSinceLastIntake(_ logs: [IntakeLog], now: Date = .now) -> Int? {
        guard let last = logs.map(\.timestamp).max() else { return nil }
        return max(0, Int(now.timeIntervalSince(last) / 60))
    }

    /// Extra mL to add when today's forecast high exceeds `Constants.baselineMaxTempC`.
    /// Returns 0 when today is at or below the baseline.
    static func temperatureAdjustmentML(todayMaxC: Double) -> Int {
        let excess = max(0, todayMaxC - Constants.baselineMaxTempC)
        return Int((excess * Double(Constants.tempAdjustmentMLPerDegree)).rounded())
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
    /// exceeded `metaDiariaML`. If today's goal is already met, today counts; if
    /// not yet (user may still drink more), the count starts from yesterday so the
    /// streak is not broken mid-day. `logs` should already be filtered to the target user.
    static func currentStreak(_ logs: [IntakeLog], metaDiariaML: Int, calendar: Calendar = .current, now: Date = .now, maxDays: Int = 365) -> Int {
        guard metaDiariaML > 0 else { return 0 }
        let today = calendar.startOfDay(for: now)
        let todayMet = totalML(logs, on: today, calendar: calendar) >= metaDiariaML
        guard let startDate = todayMet ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var count = 0
        var checkDate = startDate
        for _ in 0..<maxDays {
            guard totalML(logs, on: checkDate, calendar: calendar) >= metaDiariaML else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }
        return count
    }
}
