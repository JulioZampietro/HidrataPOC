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
        context.saveLogging("evento de interação")
        // O push fica para o `flushPending`, que roda em todo launch e em toda volta ao
        // primeiro plano e já cobre `UIInteractionEvent` pelo `syncStatus`. Antes havia
        // um `Task` solto aqui que capturava o `@Model` e o `ModelContext` e sobrevivia
        // ao chamador: se a linha fosse apagada antes de o push terminar — o que a tela
        // "Meus dados" agora permite — o objeto ficava inválido e o processo caía com
        // "This model instance was destroyed by calling ModelContext.reset". A linha já
        // está salva como `.pending`, então nada se perde esperando o próximo flush
        // (o sync é best-effort, NR-1).
    }
}
