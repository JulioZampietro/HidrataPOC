import ActivityKit
import Foundation

/// Lives in its own framework, linked by both the app and the `HydrationWidget`
/// extension, rather than being compiled separately into each target's module.
/// ActivityKit matches a running `Activity<Attributes>` across processes by the
/// attributes type's fully-qualified name — two independently-compiled copies of an
/// identical-looking struct (one in the `HidrataPOC` module, one in
/// `HydrationWidget`) are NOT the same type as far as that lookup is concerned, so
/// `Activity<HydrationAttributes>.activities` would come back empty from the
/// extension. A shared framework is what makes it one real type (see HYDRATE-LA-01
/// §3.2).
public struct HydrationAttributes: ActivityAttributes {
    /// When this activity was started — not part of `ContentState` because it never
    /// changes for the lifetime of the activity. Lets `LiveActivityManager` detect
    /// "within 30 minutes of the 8h system cap" (FR-10) without a separate store.
    public let startedAt: Date

    /// The "backup" variant started after the user swipes the Lock Screen card away
    /// while still overdue: iOS ends an activity whenever its card is dismissed, so
    /// this one keeps only the Dynamic Island icon alive and renders an invisible
    /// Lock Screen presentation.
    public let isIslandOnly: Bool

    public init(startedAt: Date, isIslandOnly: Bool = false) {
        self.startedAt = startedAt
        self.isIslandOnly = isIslandOnly
    }

    public struct ContentState: Codable, Hashable {
        public var lastIntakeDate: Date
        public var reminderThreshold: TimeInterval
        public var customAmountML: Int

        public init(lastIntakeDate: Date, reminderThreshold: TimeInterval, customAmountML: Int) {
            self.lastIntakeDate = lastIntakeDate
            self.reminderThreshold = reminderThreshold
            self.customAmountML = customAmountML
        }
    }
}

extension HydrationAttributes.ContentState {
    /// Shared by both targets: the app gates `Activity.request`/`.update` on this
    /// (only ever run the activity while it's true) and the widget extension no
    /// longer needs its own copy of the same check.
    public var isOverdue: Bool {
        Date.now.timeIntervalSince(lastIntakeDate) >= reminderThreshold
    }
}


/// The Lock Screen always hands Live Activity views `colorScheme == .dark`, whatever the
/// system appearance is, while `activityBackgroundTint` is resolved against the real
/// one — so reading the environment gives white text on a light card. The app records
/// the real system style here (App Group defaults) and the widget reads it, so the card
/// background and its text are always picked from the same source.
public enum LockScreenAppearance {
    private static let key = "systemInterfaceStyleIsDark"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.hidratapoc") }

    public static var isDark: Bool {
        get { defaults?.bool(forKey: key) ?? true }
        set { defaults?.set(newValue, forKey: key) }
    }
}
