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

    public init(startedAt: Date) {
        self.startedAt = startedAt
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
