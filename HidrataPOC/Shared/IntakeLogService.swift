import ActivityKit
import Foundation
import HydrationKit
import SwiftData

/// Compiled into both the app and the `HydrationWidget` extension so a Lock Screen /
/// Dynamic Island tap logs an intake exactly the way the app's own quick-log buttons
/// do — same notification-matching logic, same CloudKit push, same Live Activity
/// reset — just tagged with a different `source`.
@MainActor
enum IntakeLogService {
    /// Records a spontaneous intake (not a direct notification-action tap), matching
    /// it to a recent `NotificationEvent` the same way the app's Home screen buttons
    /// already do — see `NotificationScheduler.recordManualIntake`'s doc comment for
    /// why that matters for the ML dataset. `weather` is nil from the widget
    /// extension: pulling a fresh WeatherKit/location reading there would add its own
    /// entitlements and reliability concerns for enrichment data that's already
    /// optional everywhere it's read.
    @discardableResult
    static func record(
        preset: Constants.IntakePreset,
        userID: String,
        source: String,
        weather: WeatherContext?,
        context: ModelContext
    ) async -> IntakeLog {
        let cutoff = Date.now.addingTimeInterval(-Double(Constants.notificationResponseWindowMinutes) * 60)
        let predicate = #Predicate<NotificationEvent> { $0.userID == userID && $0.sentAt >= cutoff }
        let recentEvents = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.sorted { $0.sentAt > $1.sentAt } ?? []
        let matchedEvent = recentEvents.first

        let log = IntakeLog(
            userID: userID,
            preset: preset,
            origem: matchedEvent == nil ? .manual : .notificacao,
            notificationEventID: matchedEvent?.id.uuidString,
            weather: weather,
            source: source
        )
        context.insert(log)

        if let matchedEvent {
            matchedEvent.resultouEmConsumo = true
            if matchedEvent.tempoAteAgirMin == nil {
                matchedEvent.tempoAteAgirMin = max(0, Int(Date.now.timeIntervalSince(matchedEvent.sentAt) / 60))
            }
        }
        try? context.save()

        await CloudKitSyncService.shared.push(log)
        if let matchedEvent {
            await CloudKitSyncService.shared.push(matchedEvent)
        }
        try? context.save()

        await refreshLiveActivity(lastIntakeDate: log.timestamp)
        return log
    }

    /// Resets the running Live Activity's elapsed-time display to zero (FR-7) after
    /// any intake, regardless of which surface logged it — otherwise logging from the
    /// in-app buttons would leave the ambient Lock Screen/Dynamic Island display
    /// showing stale elapsed time. No-ops if no activity is running (NR-2 guards
    /// against more than one ever existing).
    ///
    /// `LogIntakeIntent` runs in a freshly-spawned, short-lived widget extension
    /// process each time — its ActivityKit XPC subscription only just activated and
    /// hasn't yet received the daemon's initial push of running activities, so
    /// `Activity<HydrationAttributes>.activities` reads empty for a brief moment
    /// after launch. Retrying a few times over ~1s rides out that startup race
    /// without holding up the (already-committed) CloudKit write in `record(...)`.
    static func refreshLiveActivity(lastIntakeDate: Date) async {
        var activities = Activity<HydrationAttributes>.activities
        var attemptsRemaining = 5
        while activities.isEmpty, attemptsRemaining > 0 {
            try? await Task.sleep(for: .milliseconds(200))
            activities = Activity<HydrationAttributes>.activities
            attemptsRemaining -= 1
        }

        for activity in activities {
            var state = activity.content.state
            state.lastIntakeDate = lastIntakeDate
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
