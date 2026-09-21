import Foundation
import SwiftData
import Testing
@testable import HidrataPOC

/// Fase 7.4 da spec HYDRATE-IX-01 — cobre o mecanismo comum a todo call site
/// (`InteractionTracker.log`/`logOpen`/`logClose`) com um `ModelContext` em
/// memória, sem depender de CloudKit nem da UI.
@MainActor
struct InteractionTrackerTests {
    // `ModelContext` guarda uma referência `unowned` pro seu `ModelContainer` — se o
    // container só existir como `let` local de uma função auxiliar, ele é
    // desalocado ao retornar e o context devolvido fica dangling (crash no
    // primeiro `save()`). Guardando o container aqui, ele vive por toda a
    // duração do teste.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = Schema([UIInteractionEvent.self])
        // `cloudKitDatabase: .none` — sem isso o SwiftData valida o schema contra os
        // requisitos do CloudKit mirroring automático (todo atributo opcional/com
        // default, sem `.unique`), mesmo para um store só de memória. Mesmo motivo do
        // `PersistenceController` real.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test func logInsertsRowWithExpectedFieldsAndMetadata() throws {
        InteractionTracker.log(
            "historico_day_tap",
            screen: .historico,
            userID: "user-1",
            metadata: ["date": "2026-09-14", "metGoal": "true"],
            context: context
        )

        let events = try context.fetch(FetchDescriptor<UIInteractionEvent>())
        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.eventName == "historico_day_tap")
        #expect(event.screen == "historico")
        #expect(event.userID == "user-1")
        #expect(event.syncStatus == .pending)

        let metadataJSON = try #require(event.metadataJSON)
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))
        #expect(decoded["date"] == "2026-09-14")
        #expect(decoded["metGoal"] == "true")
    }

    @Test func logOpenAndCloseUseSheetPrefixSuffixes() throws {
        InteractionTracker.logOpen(.goalExplainer, screen: .profile, userID: "user-1", context: context)
        InteractionTracker.logClose(.goalExplainer, screen: .profile, userID: "user-1", context: context)

        let events = try context.fetch(FetchDescriptor<UIInteractionEvent>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(events.map(\.eventName) == ["goal_explainer_open", "goal_explainer_close"])
        #expect(events.allSatisfy { $0.screen == "profile" })
    }

    @Test func logWithoutMetadataLeavesMetadataJSONNil() throws {
        InteractionTracker.log("home_help_tap", screen: .home, userID: "user-1", context: context)

        let events = try context.fetch(FetchDescriptor<UIInteractionEvent>())
        let event = try #require(events.first)
        #expect(event.metadataJSON == nil)
    }
}
