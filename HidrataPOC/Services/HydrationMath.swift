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

    static func dailyTotals(_ logs: [IntakeLog], days: Int, calendar: Calendar = .current, now: Date = .now) -> [(day: Date, totalML: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let total = totalML(logs, on: day, calendar: calendar)
            return (day, total)
        }
    }
}
