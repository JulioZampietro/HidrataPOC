import Foundation
import SwiftData

/// Snapshot of the goal that applied on one calendar day — the base goal the user had
/// set (`UserProfile.metaDiariaML`) plus that day's temperature adjustment. Only today's
/// row is ever written (see `recordToday`), so editing the goal or a new forecast never
/// rewrites how past days are judged (history, streak, charts).
///
/// Compiled into both targets because `PersistenceController`'s schema lists it; the
/// widget extension only ever reads `UserProfile`/`IntakeLog`, never this.
@Model
final class DailyGoal {
    @Attribute(.unique) var id: UUID
    var userID: String

    /// "yyyy-MM-dd" in the calendar the day was recorded in — a day label rather than a
    /// `Date`, so travelling across time zones doesn't shift which day a goal belongs to.
    var dayKey: String

    var baseGoalML: Int
    var adjustmentML: Int
    var atualizadoEm: Date

    var goalML: Int { baseGoalML + adjustmentML }

    init(userID: String, dayKey: String, baseGoalML: Int, adjustmentML: Int) {
        self.id = UUID()
        self.userID = userID
        self.dayKey = dayKey
        self.baseGoalML = baseGoalML
        self.adjustmentML = adjustmentML
        self.atualizadoEm = .now
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Upserts today's row. `adjustmentML == nil` means "no fresh forecast right now":
    /// an existing row keeps the adjustment it already has, a new one starts at 0.
    @MainActor
    static func recordToday(
        userID: String,
        baseGoalML: Int,
        adjustmentML: Int?,
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        let key = dayKey(for: now, calendar: calendar)
        let descriptor = FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userID == userID && $0.dayKey == key })
        if let existing = try? context.fetch(descriptor).first {
            let newAdjustment = adjustmentML ?? existing.adjustmentML
            guard existing.baseGoalML != baseGoalML || existing.adjustmentML != newAdjustment else { return }
            existing.baseGoalML = baseGoalML
            existing.adjustmentML = newAdjustment
            existing.atualizadoEm = now
        } else {
            context.insert(DailyGoal(userID: userID, dayKey: key, baseGoalML: baseGoalML, adjustmentML: adjustmentML ?? 0))
        }
        try? context.save()
    }
}

/// Answers "what was the goal on day X" from the recorded `DailyGoal` rows, so
/// `HydrationMath` and the views can judge each day against its own goal.
///
/// - Today (and any later day) → `todayGoalML`, the live goal on screen.
/// - A past day with a row → that row's goal.
/// - A past day without one (the app wasn't opened that day) → the closest earlier
///   row, i.e. the previous day's goal carried forward.
/// - Before the first row ever recorded (history that predates goal snapshots) → the
///   earliest row, or `fallbackGoalML` when there are none at all.
struct DailyGoalResolver {
    let todayGoalML: Int
    let fallbackGoalML: Int
    let calendar: Calendar
    let now: Date
    /// Sorted ascending by `dayKey` — "yyyy-MM-dd" sorts chronologically as a string.
    private let entries: [(dayKey: String, goalML: Int, adjustmentML: Int)]

    init(goals: [DailyGoal], todayGoalML: Int, fallbackGoalML: Int, calendar: Calendar = .current, now: Date = .now) {
        self.todayGoalML = todayGoalML
        self.fallbackGoalML = fallbackGoalML
        self.calendar = calendar
        self.now = now
        self.entries = goals
            .map { (dayKey: $0.dayKey, goalML: $0.goalML, adjustmentML: $0.adjustmentML) }
            .sorted { $0.dayKey < $1.dayKey }
    }

    func goalML(on day: Date) -> Int {
        let key = DailyGoal.dayKey(for: day, calendar: calendar)
        guard key < DailyGoal.dayKey(for: now, calendar: calendar) else { return todayGoalML }
        // Binary search for the last entry with dayKey <= key.
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].dayKey <= key { low = mid + 1 } else { high = mid }
        }
        if low > 0 { return entries[low - 1].goalML }
        return entries.first?.goalML ?? fallbackGoalML
    }

    /// The temperature adjustment already recorded for `day`, if that exact day has a row.
    /// Lets today's goal keep its adjustment when a fresh forecast can't be fetched.
    static func recordedAdjustmentML(in goals: [DailyGoal], on day: Date, calendar: Calendar = .current) -> Int? {
        let key = DailyGoal.dayKey(for: day, calendar: calendar)
        return goals.first { $0.dayKey == key }?.adjustmentML
    }
}
