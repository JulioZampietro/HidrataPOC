import CoreLocation
import Foundation
import os
import WeatherKit

struct WeatherContext {
    let temperaturaC: Double
    let umidadeRelativa: Double
    let sensacaoTermicaC: Double
}

private let logger = Logger(subsystem: "com.hidratapoc", category: "WeatherContextService")

/// Wraps WeatherKit + a one-shot location fetch so NotificationScheduler can ask for
/// "the weather right now" without juggling CoreLocation delegates itself.
///
/// Also caches the last successful reading for `Constants.weatherCacheMaxAgeMinutes`,
/// so call sites that must stay instant (tapping a quick-log button) can read
/// `cachedContext` synchronously instead of awaiting a fresh fetch.
@MainActor
final class WeatherContextService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherContextService()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var cached: (context: WeatherContext, capturedAt: Date)?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestWhenInUseAuthorizationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Whatever's currently cached — nil if nothing has been fetched yet, or if the
    /// last reading is older than `Constants.weatherCacheMaxAgeMinutes`. Never
    /// triggers a network/location fetch, so it's safe to call from a UI action that
    /// must respond instantly.
    var cachedContext: WeatherContext? {
        guard let cached, !isStale(cached.capturedAt) else { return nil }
        return cached.context
    }

    /// Refreshes the cache if it's missing or stale; no-ops otherwise. Call this
    /// opportunistically (e.g. from `NotificationScheduler.tick()`) while the app is
    /// active, so `cachedContext` tends to have something recent whenever a tester
    /// taps a log button — the fetch happens ahead of time, off the tap itself.
    func refreshCacheIfStale() async {
        if let cached, !isStale(cached.capturedAt) { return }
        _ = await currentContext()
    }

    /// Returns the cached reading if still fresh, otherwise fetches a new one and
    /// caches it. Returns nil (rather than throwing) on any failure — weather is
    /// enrichment, not something that should block a notification from going out.
    func currentContext() async -> WeatherContext? {
        if let cached, !isStale(cached.capturedAt) { return cached.context }

        let location: CLLocation
        do {
            location = try await currentLocation()
        } catch {
            logger.error("Location fetch failed (authorizationStatus=\(self.locationManager.authorizationStatus.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            return nil
        }

        do {
            let weather = try await WeatherService.shared.weather(for: location, including: .current)
            let context = WeatherContext(
                temperaturaC: weather.temperature.converted(to: .celsius).value,
                umidadeRelativa: weather.humidity,
                sensacaoTermicaC: weather.apparentTemperature.converted(to: .celsius).value
            )
            cached = (context, .now)
            return context
        } catch {
            logger.error("WeatherKit fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func isStale(_ capturedAt: Date) -> Bool {
        Date.now.timeIntervalSince(capturedAt) > Double(Constants.weatherCacheMaxAgeMinutes) * 60
    }

    private func currentLocation() async throws -> CLLocation {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            logger.error("Location not authorized (authorizationStatus=\(status.rawValue, privacy: .public))")
            throw CLError(.denied)
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
