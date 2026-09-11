import AppIntents
import SwiftData

// MARK: - Quantidade

enum DrinkQuantity: Int, AppEnum, CaseIterable {
    case one = 1, two = 2, three = 3, four = 4, five = 5

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Quantidade" }

    static nonisolated(unsafe) var caseDisplayRepresentations: [DrinkQuantity: DisplayRepresentation] = [
        .one:   "um",
        .two:   "dois",
        .three: "três",
        .four:  "quatro",
        .five:  "cinco",
    ]

    var value: Int { rawValue }
}

// MARK: - Intents

struct LogGlassIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Copo" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Quantidade", default: DrinkQuantity.one)
    var quantity: DrinkQuantity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$quantity) copo(s)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.glass.volumeML
        await logIntakes(count: q, preset: .glass)
        let total = await totalConsumedToday()
        return .result(dialog: "\(q) copo\(q > 1 ? "s" : "") registrado\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }
}

struct LogBottleIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Garrafa" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Quantidade", default: DrinkQuantity.one)
    var quantity: DrinkQuantity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$quantity) garrafa(s)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.bottle.volumeML
        await logIntakes(count: q, preset: .bottle)
        let total = await totalConsumedToday()
        return .result(dialog: "\(q) garrafa\(q > 1 ? "s" : "") registrada\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }
}

struct LogGallonIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Galão" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Quantidade", default: DrinkQuantity.one)
    var quantity: DrinkQuantity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$quantity) galão(ões)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.gallon.volumeML
        await logIntakes(count: q, preset: .gallon)
        let total = await totalConsumedToday()
        return .result(dialog: "\(q) galão\(q > 1 ? "ões" : "") registrado\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }
}

// MARK: - Shortcuts Siri

struct HidrataPOCShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogGlassIntent(),
            phrases: [
                "Bebi \(\.$quantity) copos de \(.applicationName)",
                "Tomei \(\.$quantity) copos de \(.applicationName)",
                "Bebi um copo de \(.applicationName)",
                "Tomei um copo de \(.applicationName)",
            ],
            shortTitle: "Registrar Copo",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Bebi \(\.$quantity) garrafas de \(.applicationName)",
                "Tomei \(\.$quantity) garrafas de \(.applicationName)",
                "Bebi uma garrafa de \(.applicationName)",
                "Tomei uma garrafa de \(.applicationName)",
            ],
            shortTitle: "Registrar Garrafa",
            systemImageName: "waterbottle.fill"
        )
        AppShortcut(
            intent: LogGallonIntent(),
            phrases: [
                "Bebi \(\.$quantity) galões de \(.applicationName)",
                "Tomei \(\.$quantity) galões de \(.applicationName)",
                "Bebi um galão de \(.applicationName)",
                "Tomei um galão de \(.applicationName)",
            ],
            shortTitle: "Registrar Galão",
            systemImageName: "cylinder.fill"
        )
    }
}

// MARK: - Helpers

@MainActor
private func logIntakes(count: Int, preset: Constants.IntakePreset) async {
    let context = PersistenceController.context
    guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
    for _ in 0..<count {
        await IntakeLogService.record(
            preset: preset,
            userID: profile.userID,
            source: "siri",
            weather: nil,
            context: context
        )
    }
}

@MainActor
private func totalConsumedToday() async -> Int {
    let context = PersistenceController.context
    guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return 0 }
    let uid = profile.userID
    let predicate = #Predicate<IntakeLog> { $0.userID == uid }
    let logs = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    return HydrationMath.totalML(logs, on: .now)
}
