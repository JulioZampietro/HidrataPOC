import AppIntents
import SwiftData

/// Fired by the Control Center / hardware Action Button controls
/// (`HydrationControlWidgets.swift`). Structurally identical to `LogIntakeIntent`
/// (same `LiveActivityIntent` routing — runs in the app's process rather than the
/// constrained widget extension process, so the CloudKit/SwiftData work has a normal
/// execution budget), but kept as its own type — like the Siri intents in
/// `SiriIntents.swift` each hardcode their own `source` rather than threading it
/// through as a parameter — so `source: "actionButton"` never has to survive
/// cross-process intent serialization; it's baked into which type ran, not into a
/// value carried by it.
struct LogIntakeControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Registrar consumo de água (Botão de Ação)" }

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

    @MainActor
    private static func log(amountML: Int) async {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        await IntakeLogService.record(
            preset: .matching(volumeML: amountML),
            userID: profile.userID,
            source: "actionButton",
            weather: nil,
            context: context
        )
    }
}
