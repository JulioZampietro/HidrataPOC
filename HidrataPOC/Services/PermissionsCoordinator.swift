import Foundation

/// Requests notification, location, and calendar access together. Called once the
/// tester has accepted the consent screen (and again, harmlessly, on later launches —
/// each underlying API only actually prompts the first time) so the OS permission
/// dialogs never appear before the tester has agreed to participate.
@MainActor
enum PermissionsCoordinator {
    static func requestAll() async {
        _ = await NotificationScheduler.shared.requestAuthorization()
        WeatherContextService.shared.requestWhenInUseAuthorizationIfNeeded()
        await CalendarContextService.shared.requestAccessIfNeeded()
    }
}
