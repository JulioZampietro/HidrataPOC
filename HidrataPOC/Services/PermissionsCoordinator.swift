import Foundation

/// Requests notification and location access together. Called once
/// onboarding has finished (and again, harmlessly, on later launches — each underlying
/// API only actually prompts the first time) so the OS permission dialogs never appear
/// before or during onboarding.
@MainActor
enum PermissionsCoordinator {
    static func requestAll() async {
        _ = await NotificationScheduler.shared.requestAuthorization()
        WeatherContextService.shared.requestWhenInUseAuthorizationIfNeeded()
    }
}
