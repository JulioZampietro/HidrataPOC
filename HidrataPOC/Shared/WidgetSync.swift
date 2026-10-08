import Foundation
import WidgetKit

/// Compiled into both the app and the `HydrationWidget` extension. The widget reads
/// today's intake straight from the shared SwiftData store, but the goal it fills
/// against depends on the temperature adjustment (WeatherKit), which only the app
/// computes — so the app saves the effective goal to the App Group defaults and the
/// widget falls back to the profile's base goal until it has one.
enum WidgetSync {
    static let waterTankKind = "WaterTankWidget"

    private static let effectiveGoalKey = "widget.effectiveGoalML"
    private static let effectiveGoalDayKey = "widget.effectiveGoalDay"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: Constants.appGroupID) }

    /// Saves today's effective goal and refreshes the widget if it changed.
    static func saveEffectiveGoal(_ goalML: Int, now: Date = .now) {
        guard let defaults else { return }
        let day = Calendar.current.startOfDay(for: now)
        let unchanged = defaults.integer(forKey: effectiveGoalKey) == goalML
            && (defaults.object(forKey: effectiveGoalDayKey) as? Date) == day
        guard !unchanged else { return }
        defaults.set(goalML, forKey: effectiveGoalKey)
        defaults.set(day, forKey: effectiveGoalDayKey)
        reloadWaterTank()
    }

    /// The goal saved by the app for `date`'s day, or nil if it saved none that day
    /// (the temperature adjustment is per day, so yesterday's value doesn't carry over).
    static func effectiveGoal(on date: Date) -> Int? {
        guard let defaults,
              let day = defaults.object(forKey: effectiveGoalDayKey) as? Date,
              Calendar.current.isDate(day, inSameDayAs: date) else { return nil }
        let goal = defaults.integer(forKey: effectiveGoalKey)
        return goal > 0 ? goal : nil
    }

    static func reloadWaterTank() {
        WidgetCenter.shared.reloadTimelines(ofKind: waterTankKind)
    }
}
