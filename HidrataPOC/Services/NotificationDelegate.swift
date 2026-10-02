import UserNotifications

/// Routes every notification interaction (quick action, snooze, body tap, explicit
/// dismiss) to `NotificationScheduler`. If the tapped notification's `NotificationEvent`
/// hasn't been captured yet (the foreground/background pre-capture never got to it in
/// time), captures context first so the interaction always has a row to attach to.
///
/// Every interaction is also what unblocks delivery: only one reminder is ever queued
/// with the system, and the next one is armed here, once the current one is answered
/// (see `NotificationScheduler.armNextSlotIfClear`).
///
/// Both callbacks are `@MainActor`, not `nonisolated`: the compiler-generated thunk
/// calls UIKit's completion handler wherever the async method finishes. A
/// `nonisolated async` method finishes on a background thread after its last
/// `await`, and for background launches (quick actions, snooze, dismiss) UIKit then
/// updates the app snapshot off the main thread and aborts with "Call must be made
/// on main thread". `@preconcurrency` lets the non-Sendable UserNotifications types
/// cross into the main-actor implementations (UIKit delivers them on main anyway).
final class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let eventIDString = response.notification.request.content.userInfo["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDString) else { return }

        let actionIdentifier = response.actionIdentifier
        let sentAt = response.notification.date
        let requestID = response.notification.request.identifier

        // A dismiss wakes the app in the background, often on a locked device, with
        // little time to spare: only note it down (UserDefaults, no SwiftData or
        // network) and let the next tick resolve it.
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            NotificationScheduler.recordDismissal(eventID: eventID, sentAt: sentAt)
        } else {
            await Self.handle(eventID: eventID, sentAt: sentAt, actionIdentifier: actionIdentifier)
        }

        // Last, so a snooze slot added above is the one that gets armed.
        await NotificationScheduler.shared.armNextSlotIfClear(answered: requestID)
    }

    @MainActor
    private static func handle(eventID: UUID, sentAt: Date, actionIdentifier: String) async {
        let context = PersistenceController.context
        let scheduler = NotificationScheduler.shared

        // Quick actions also run in the background, so skip the location + WeatherKit
        // round trip here — the cached reading is recent enough.
        await scheduler.captureContext(id: eventID, firesAt: sentAt, context: context, preferCachedWeather: true)

        switch actionIdentifier {
        case Constants.NotificationAction.glass:
            await scheduler.recordQuickAction(eventID: eventID, preset: .glass, context: context)
        case Constants.NotificationAction.bottle:
            await scheduler.recordQuickAction(eventID: eventID, preset: .bottle, context: context)
        case Constants.NotificationAction.gole:
            await scheduler.recordQuickAction(eventID: eventID, preset: .gole, context: context)
        case Constants.NotificationAction.snooze:
            await scheduler.resolveInteraction(eventID: eventID, status: .soneca, context: context)
            await scheduler.scheduleSnoozeSlot()
        case UNNotificationDefaultActionIdentifier:
            await scheduler.resolveInteraction(eventID: eventID, status: .aberta, context: context)
        default:
            break
        }
    }
}
