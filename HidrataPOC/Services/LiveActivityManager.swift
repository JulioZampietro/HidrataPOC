import ActivityKit
import Foundation
import HydrationKit
import SwiftData

/// Owns the hydration Live Activity's request lifecycle and the "should one exist at
/// all right now" decision — the only place that calls `Activity<HydrationAttributes>
/// .request`, so NR-2/FR-8 ("at most one active at a time") has a single enforcement
/// point. App-target only. `IntakeLogService.endLiveActivity`, compiled into both
/// targets, independently calls `.end()` when an intake is logged — ending is safe to
/// duplicate (a second `.end()` on an already-ended activity is a no-op) in a way
/// requesting a fresh one is not, so that half doesn't need to funnel through here.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// End-and-restart once within this long of the OS's 8h cap (FR-10).
    private static let restartLeadSeconds: TimeInterval = 30 * 60
    private static let activityDurationSeconds: TimeInterval = 8 * 60 * 60

    private init() {}

    /// FR-9: start a Live Activity if none is running *and* the user is already
    /// overdue. Seeds `lastIntakeDate` from the most recent local `IntakeLog` — the
    /// same source of truth the Home screen itself reads, since there's no CloudKit
    /// pull-sync to derive it from instead — and `customAmountML` from the profile's
    /// persisted preference (FR-4c).
    ///
    /// Gating on `isOverdue` here (rather than requesting unconditionally and letting
    /// the widget render a quiet placeholder) is deliberate: the Lock Screen/Dynamic
    /// Island should never show up with nothing to act on, so the activity's very
    /// existence is now the signal that quick-log buttons are available.
    func startIfNeeded(profile: UserProfile, context: ModelContext) async {
        guard await Self.currentActivities().isEmpty else { return } // NR-2/FR-8
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await requestIfOverdue(profile: profile, context: context)
    }

    /// FR-10: within 30 minutes of the OS's 8h cap, end the current activity and
    /// start a fresh one, carrying `lastIntakeDate`/`customAmountML` forward so
    /// nothing visibly resets.
    func restartIfNearingLimit() async {
        guard let activity = Activity<HydrationAttributes>.activities.first else { return }
        let age = Date.now.timeIntervalSince(activity.attributes.startedAt)
        guard age >= Self.activityDurationSeconds - Self.restartLeadSeconds else { return }

        let carriedState = activity.content.state
        await activity.end(nil, dismissalPolicy: .immediate)

        let attributes = HydrationAttributes(startedAt: .now)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: carriedState, staleDate: nil))
    }

    /// FR-4b: push the edited custom-amount preset into the running activity's
    /// `ContentState` so the Lock Screen's third button relabels without a restart.
    func updateCustomAmount(_ amountML: Int) async {
        for activity in Activity<HydrationAttributes>.activities {
            var state = activity.content.state
            state.customAmountML = amountML
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Re-derives `lastIntakeDate`/`customAmountML` from the same source of truth
    /// `startIfNeeded` seeds from, and re-pushes them — both to force a fresh redraw
    /// (the Lock Screen/Dynamic Island no longer use a native timer; `isOverdue` is
    /// computed from `Date.now` at render time in `HydrationLiveActivity.swift`, so a
    /// locked phone that's never woken or foregrounded would otherwise keep showing
    /// whatever was last rendered even past the 1h mark) and to self-heal a stuck
    /// `ContentState` if a `LogIntakeIntent` run from the extension process ever
    /// wrote the `IntakeLog` but couldn't find the activity to update on its own
    /// (that half can fail independently of the write — NR-1 already treats it as
    /// best-effort). Called from `NotificationScheduler.tick(context:)`, which
    /// already runs every 60s in the foreground and opportunistically via
    /// `BackgroundRefreshService` — the same best-effort cadence this app already
    /// uses for notification timing, not a new mechanism.
    ///
    /// No activity currently running is the normal state for most of every hour
    /// (see `startIfNeeded`'s doc comment) — that case now doubles as "check whether
    /// we just crossed the overdue threshold and should start one", so the reminder
    /// still appears within a tick of becoming due even though nothing requested it
    /// at launch.
    func touchIfNeeded(profile: UserProfile, context: ModelContext) async {
        guard let activity = Activity<HydrationAttributes>.activities.first else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            await requestIfOverdue(profile: profile, context: context)
            return
        }
        var state = activity.content.state
        state.lastIntakeDate = lastKnownIntakeDate(userID: profile.userID, context: context)
        state.customAmountML = profile.customIntakeML
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private func requestIfOverdue(profile: UserProfile, context: ModelContext) async {
        let state = HydrationAttributes.ContentState(
            lastIntakeDate: lastKnownIntakeDate(userID: profile.userID, context: context),
            reminderThreshold: Constants.hydrationReminderThresholdSeconds,
            customAmountML: profile.customIntakeML
        )
        guard state.isOverdue else { return }

        let attributes = HydrationAttributes(startedAt: .now)
        // A failed request is a best-effort UI feature (NR-1) — never block app startup on it.
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
    }

    /// NR-3: never fabricate `lastIntakeDate` — re-derive it from the last locally
    /// known `IntakeLog`, falling back to `.now` only when this user has never logged
    /// anything yet (fresh onboarding).
    private func lastKnownIntakeDate(userID: String, context: ModelContext) -> Date {
        let predicate = #Predicate<IntakeLog> { $0.userID == userID }
        var descriptor = FetchDescriptor<IntakeLog>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp ?? .now
    }

    /// `Activity<HydrationAttributes>.activities` reads empty for a brief moment
    /// right after this process's ActivityKit XPC subscription first activates
    /// (before the daemon's initial push arrives) — most noticeable right after a
    /// cold app launch, which is exactly when this NR-2/FR-8 guard runs. A false
    /// empty read here would let a second, duplicate activity get requested even
    /// though one is already running, so this rides out that startup race the same
    /// way `IntakeLogService.endLiveActivity` does.
    private static func currentActivities() async -> [Activity<HydrationAttributes>] {
        var activities = Activity<HydrationAttributes>.activities
        var attemptsRemaining = 5
        while activities.isEmpty, attemptsRemaining > 0 {
            try? await Task.sleep(for: .milliseconds(200))
            activities = Activity<HydrationAttributes>.activities
            attemptsRemaining -= 1
        }
        return activities
    }
}
