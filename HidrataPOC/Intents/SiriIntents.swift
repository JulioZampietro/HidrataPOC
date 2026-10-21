import AppIntents
import SwiftData

// MARK: - Quantidade

enum DrinkQuantity: Int, AppEnum, CaseIterable {
    case one = 1, two = 2, three = 3, four = 4, five = 5

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Quantidade" }

    static let caseDisplayRepresentations: [DrinkQuantity: DisplayRepresentation] = [
        .one:   "um",
        .two:   "dois",
        .three: "três",
        .four:  "quatro",
        .five:  "cinco",
    ]

    var value: Int { rawValue }
}

// MARK: - Intents

struct LogGoleIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Gole" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Quantidade", default: DrinkQuantity.one)
    var quantity: DrinkQuantity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$quantity) gole(s)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.gole.volumeML
        let total = await Self.record(count: q)
        return .result(dialog: "\(q) gole\(q > 1 ? "s" : "") registrado\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }

    @MainActor
    private static func record(count: Int) async -> Int {
        await logIntakes(count: count, preset: .gole)
        return await totalConsumedToday()
    }
}

struct LogGlassIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Copo" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Quantidade", default: DrinkQuantity.one)
    var quantity: DrinkQuantity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$quantity) copo(s)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.glass.volumeML
        let total = await Self.record(count: q, preset: .glass)
        return .result(dialog: "\(q) copo\(q > 1 ? "s" : "") registrado\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }

    @MainActor
    private static func record(count: Int, preset: Constants.IntakePreset) async -> Int {
        await logIntakes(count: count, preset: preset)
        return await totalConsumedToday()
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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = quantity.value
        let ml = q * Constants.IntakePreset.bottle.volumeML
        let total = await Self.record(count: q, preset: .bottle)
        return .result(dialog: "\(q) garrafa\(q > 1 ? "s" : "") registrada\(q > 1 ? "s" : "")! +\(ml) mL. Total hoje: \(total) mL.")
    }

    @MainActor
    private static func record(count: Int, preset: Constants.IntakePreset) async -> Int {
        await logIntakes(count: count, preset: preset)
        return await totalConsumedToday()
    }
}

struct LogCustomIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar Quantidade Personalizada" }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (ml, total) = await Self.record()
        return .result(dialog: "+\(ml) mL registrado! Total hoje: \(total) mL.")
    }

    @MainActor
    private static func record() async -> (ml: Int, total: Int) {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else {
            return (0, 0)
        }
        let ml = profile.customIntakeML
        await IntakeLogService.record(
            preset: .custom(volumeML: ml),
            userID: profile.userID,
            source: "siri",
            weather: nil,
            context: context
        )
        let total = await totalConsumedToday()
        return (ml, total)
    }
}

// MARK: - Shortcuts Siri

struct HidrataPOCShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogCustomIntent(),
            phrases: [
                "Registra minha quantidade personalizada no \(.applicationName)",
                "Bebi minha quantidade personalizada no \(.applicationName)",
                "Tomei minha quantidade personalizada no \(.applicationName)",
                "Registra personalizado no \(.applicationName)",
            ],
            shortTitle: "Personalizado",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: LogGoleIntent(),
            phrases: [
                "Bebi \(\.$quantity) goles de \(.applicationName)",
                "Tomei \(\.$quantity) goles de \(.applicationName)",
                "Dei \(\.$quantity) goles de \(.applicationName)",
                "Bebi um gole de \(.applicationName)",
                "Tomei um gole de \(.applicationName)",
                "Dei um gole de \(.applicationName)",
            ],
            shortTitle: "Registrar Gole",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogGlassIntent(),
            phrases: [
                "Bebi \(\.$quantity) copos de \(.applicationName)",
                "Tomei \(\.$quantity) copos de \(.applicationName)",
                "Bebi um copo de \(.applicationName)",
                "Tomei um copo de \(.applicationName)",
                "Acabei de tomar um copo de \(.applicationName)",
                "Registra um copo no \(.applicationName)",
                "Bebi um copo de água no \(.applicationName)",
                "Tomei um copo de água no \(.applicationName)",
                "Bebi um copo no \(.applicationName)",
            ],
            shortTitle: "Registrar Copo",
            systemImageName: "mug.fill"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Bebi \(\.$quantity) garrafas de \(.applicationName)",
                "Tomei \(\.$quantity) garrafas de \(.applicationName)",
                "Bebi uma garrafa de \(.applicationName)",
                "Tomei uma garrafa de \(.applicationName)",
                "Acabei minha garrafa no \(.applicationName)",
                "Terminei uma garrafa de \(.applicationName)",
                "Registra uma garrafa no \(.applicationName)",
                "Bebi uma garrafa de água no \(.applicationName)",
            ],
            shortTitle: "Registrar Garrafa",
            systemImageName: "waterbottle.fill"
        )
    }
}

// MARK: - Helpers

/// "Bebi 5 copos" fazia cinco chamadas completas a `IntakeLogService.record` — cada uma
/// com fetch, save, um push ao CloudKit aguardado inline e até 1s do retry de
/// `endLiveActivity`. São cinco round trips de rede dentro de um intent da Siri, que
/// tem orçamento curto. Agora só o último registro paga o encerramento da Live
/// Activity, e o sync vai para o fim, de uma vez.
@MainActor
private func logIntakes(count: Int, preset: Constants.IntakePreset) async {
    let context = PersistenceController.context
    guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first, count > 0 else { return }
    for index in 0..<count {
        let isLast = index == count - 1
        await IntakeLogService.record(
            preset: preset,
            userID: profile.userID,
            source: "siri",
            weather: nil,
            context: context,
            // Só a última chamada espera a corrida de inicialização do ActivityKit: as
            // anteriores já teriam encerrado a atividade, se houvesse uma.
            waitForColdStartActivity: isLast,
            // O processo da Siri pode ser suspenso quando o handler retorna, então o
            // push não pode ser adiado para depois — mas pode ser feito uma vez, no fim.
            deferCloudSync: !isLast
        )
    }
    // Os pushes adiados acima: feitos aqui, ainda dentro do intent, em uma passada.
    await CloudKitSyncService.shared.flushPending(context: context)
}

@MainActor
private func totalConsumedToday() async -> Int {
    let context = PersistenceController.context
    guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return 0 }
    let uid = profile.userID
    // Só hoje: antes carregava o histórico inteiro do usuário para somar um dia.
    let dayStart = Calendar.current.startOfDay(for: .now)
    let predicate = #Predicate<IntakeLog> { $0.userID == uid && $0.timestamp >= dayStart }
    let logs = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    return HydrationMath.totalML(logs, on: .now)
}
