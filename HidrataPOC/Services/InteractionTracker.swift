import Foundation
import SwiftData

/// Registra uma linha de `UIInteractionEvent` por interação de UI que não é log de
/// água — abertura/fechamento de sheets, navegação, toques em botões sem ação
/// própria. Local-first (grava e salva na hora), com push best-effort pro
/// CloudKit público, igual ao resto do pipeline (`NotificationEvent`/`IntakeLog`).
@MainActor
enum InteractionTracker {
    static func logOpen(_ sheet: TrackedSheet, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        log("\(sheet.rawValue)_open", screen: screen, userID: userID, metadata: metadata, context: context)
    }

    static func logClose(_ sheet: TrackedSheet, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        log("\(sheet.rawValue)_close", screen: screen, userID: userID, metadata: metadata, context: context)
    }

    static func log(_ eventName: String, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        let json = metadata.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let event = UIInteractionEvent(userID: userID, eventName: eventName, screen: screen.rawValue, metadataJSON: json)
        context.insert(event)
        try? context.save()
        Task {
            await CloudKitSyncService.shared.push(event)
            try? context.save()
        }
    }
}
