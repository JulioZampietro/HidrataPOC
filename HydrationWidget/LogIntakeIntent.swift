import AppIntents
import SwiftData

/// Runs in the `HydrationWidget` extension process when a Lock Screen or Dynamic
/// Island button is tapped. `LiveActivityIntent` executes in the background and
/// cannot foreground the app — that's what makes logging without unlocking possible
/// (HYDRATE-LA-01 §2.6). All three buttons (250 mL, 500 mL, and the Lock Screen's
/// custom amount) share this one intent, parameterized by `amountML` (Decision D-2 /
/// D-4).
struct LogIntakeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Registrar consumo de água" }

    @Parameter(title: "Volume (mL)")
    var amountML: Int

    init() {
        amountML = 0
    }

    init(amountML: Int) {
        self.amountML = amountML
    }

    func perform() async throws -> some IntentResult {
        await Self.log(amountML: amountML)
        return .result()
    }

    /// `perform()` itself is nonisolated (a `LiveActivityIntent` requirement), but
    /// `ModelContext` must never cross an actor boundary — so the MainActor hop has
    /// to happen around the whole read-context/write/push sequence, not just around
    /// individual calls.
    ///
    /// The target user is resolved from the shared App Group SwiftData store (this
    /// is a single-profile POC — same assumption `NotificationScheduler` already
    /// makes) rather than from the running Activity's attributes: per NR-1, the
    /// CloudKit write is the source of truth and the Activity update is best-effort,
    /// so the write must not be gated on the Activity lookup succeeding.
    @MainActor
    private static func log(amountML: Int) async {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        await IntakeLogService.record(
            preset: .matching(volumeML: amountML),
            userID: profile.userID,
            source: "liveActivity",
            weather: nil,
            context: context
        )
    }
}
