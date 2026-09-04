import UserNotifications

/// Routes every notification interaction (quick action, snooze, body tap, explicit
/// dismiss) to `NotificationScheduler`. If the tapped notification's `NotificationEvent`
/// hasn't been captured yet (the foreground/background pre-capture never got to it in
/// time), captures context synchronously first so the interaction always has a row to
/// attach to.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let eventIDString = response.notification.request.content.userInfo["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDString) else { return }

        let actionIdentifier = response.actionIdentifier
        let sentAt = response.notification.date

        await Self.handle(eventID: eventID, sentAt: sentAt, actionIdentifier: actionIdentifier)
    }

    @MainActor
    private static func handle(eventID: UUID, sentAt: Date, actionIdentifier: String) async {
        let context = PersistenceController.context
        let scheduler = NotificationScheduler.shared

        await scheduler.captureContext(id: eventID, firesAt: sentAt, context: context)

        switch actionIdentifier {
        case Constants.NotificationAction.glass:
            await scheduler.recordQuickAction(eventID: eventID, preset: .glass, context: context)
        case Constants.NotificationAction.bottle:
            await scheduler.recordQuickAction(eventID: eventID, preset: .bottle, context: context)
        case Constants.NotificationAction.gallon:
            await scheduler.recordQuickAction(eventID: eventID, preset: .gallon, context: context)
        case Constants.NotificationAction.snooze:
            await scheduler.resolveInteraction(eventID: eventID, status: .soneca, context: context)
            await scheduler.scheduleSnoozeSlot()
        case UNNotificationDismissActionIdentifier:
            await scheduler.resolveInteraction(eventID: eventID, status: .ignorada, context: context)
        case UNNotificationDefaultActionIdentifier:
            await scheduler.resolveInteraction(eventID: eventID, status: .aberta, context: context)
        default:
            break
        }
    }
}
