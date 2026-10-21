import CloudKit
import Foundation

/// Where the policy's state lives:
///  - params: CloudKit public record PolicyParams/"current" -> cached in the App Group
///            -> bundled policy_params.json as the last resort (ship one with every build)
///  - posterior: App Group UserDefaults, per device/user
/// This is the app's first read from CloudKit; it touches one small record only.
@MainActor
final class PolicyStore {
    static let shared = PolicyStore()

    /// The coordinator runs on every launch/foreground; the published prior changes
    /// monthly at most, so CloudKit is asked at most this often.
    private static let refreshInterval: TimeInterval = 6 * 60 * 60

    private let defaults = UserDefaults(suiteName: Constants.appGroupID) ?? .standard
    private let paramsKey = "policy.params.json"
    private let posteriorKey = "policy.posterior.json"
    private let lastRefreshKey = "policy.params.lastRefresh"
    private let container = CKContainer(identifier: Constants.cloudKitContainerID)

    func loadParams() -> PolicyParams? {
        if let cached = defaults.string(forKey: paramsKey), let p = Self.decode(cached) { return p }
        guard let url = Bundle.main.url(forResource: "policy_params", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Self.decode(text)
    }

    /// Returns the new params if a different, valid version was downloaded.
    func refreshFromCloudKit(now: Date = .now) async -> PolicyParams? {
        if let last = defaults.object(forKey: lastRefreshKey) as? Date,
           now.timeIntervalSince(last) < Self.refreshInterval { return nil }
        defaults.set(now, forKey: lastRefreshKey)
        do {
            let record = try await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: "current"))
            guard let text = record["json"] as? String, let new = Self.decode(text),
                  new.policyVersion != loadParams()?.policyVersion else { return nil }
            defaults.set(text, forKey: paramsKey)
            return new
        } catch {
            return nil   // offline or no record yet: keep the current params
        }
    }

    func loadPosterior() -> PolicyPosterior? {
        guard let data = defaults.data(forKey: posteriorKey) else { return nil }
        return try? JSONDecoder().decode(PolicyPosterior.self, from: data)
    }

    func savePosterior(_ posterior: PolicyPosterior) {
        if let data = try? JSONEncoder().encode(posterior) { defaults.set(data, forKey: posteriorKey) }
    }

    private static func decode(_ text: String) -> PolicyParams? {
        guard let p = try? JSONDecoder().decode(PolicyParams.self, from: Data(text.utf8)), p.isValid else { return nil }
        return p
    }
}
