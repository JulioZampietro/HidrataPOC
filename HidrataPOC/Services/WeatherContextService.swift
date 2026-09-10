import CoreLocation
import Foundation
import os
import WeatherKit

struct TemperatureAdjustmentContext {
    let todayMaxC: Double
    let baselineC: Double
    let adjustmentML: Int
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

    // Deduplicates concurrent location requests so only one requestLocation() is in flight.
    private var inflightLocationTask: Task<CLLocation, Error>?
    private var cachedLocation: (location: CLLocation, capturedAt: Date)?

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

    /// Refreshes the cache if it's missing or stale; no-ops otherwise.
    func refreshCacheIfStale() async {
        if let cached, !isStale(cached.capturedAt) { return }
        _ = await currentContext()
    }

    /// Returns the cached reading if still fresh, otherwise fetches a new one.
    func currentContext() async -> WeatherContext? {
        if let cached, !isStale(cached.capturedAt) { return cached.context }

        let location: CLLocation
        do {
            location = try await resolveLocation()
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

    /// Fetches today's forecast high via WeatherKit (.daily) and computes the
    /// hydration adjustment relative to `Constants.baselineMaxTempC`.
    func temperatureAdjustmentContext() async -> TemperatureAdjustmentContext? {
        let location: CLLocation
        do { location = try await resolveLocation() } catch { return nil }

        do {
            let forecast = try await WeatherService.shared.weather(for: location, including: .daily)
            guard let today = forecast.forecast.first else { return nil }
            let maxC = today.highTemperature.converted(to: .celsius).value
            let adjustment = HydrationMath.temperatureAdjustmentML(todayMaxC: maxC)
            return TemperatureAdjustmentContext(
                todayMaxC: maxC,
                baselineC: Constants.baselineMaxTempC,
                adjustmentML: adjustment
            )
        } catch {
            logger.error("WeatherKit daily forecast failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Returns a cached location (5-min TTL) or fetches a fresh one, deduplicating
    /// concurrent requests so only one `requestLocation()` call is in flight at a time.
    private func resolveLocation() async throws -> CLLocation {
        if let c = cachedLocation, Date.now.timeIntervalSince(c.capturedAt) < 300 {
            return c.location
        }
        if let t = inflightLocationTask { return try await t.value }
        let t = Task<CLLocation, Error> { try await self.fetchOneTimeLocation() }
        inflightLocationTask = t
        do {
            let loc = try await t.value
            cachedLocation = (loc, .now)
            inflightLocationTask = nil
            return loc
        } catch {
            inflightLocationTask = nil
            throw error
        }
    }

    private func isStale(_ capturedAt: Date) -> Bool {
        Date.now.timeIntervalSince(capturedAt) > Double(Constants.weatherCacheMaxAgeMinutes) * 60
    }

    private func fetchOneTimeLocation() async throws -> CLLocation {
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
