import Foundation
import SwiftData

/// Um registro por interação de UI que não é log de água (essas já vivem em
/// `IntakeLog.source`/`tipoEntrada`) — abertura/fechamento de sheets, navegação no
/// calendário do histórico, toques em botões sem ação. Mesmo padrão de sync que
/// `NotificationEvent`/`IntakeLog`: local-first, push best-effort pro CloudKit
/// público, retry em `CloudKitSyncService.flushPending`.
@Model
final class UIInteractionEvent {
    @Attribute(.unique) var id: UUID
    var userID: String
    var timestamp: Date

    /// Raw value de `TrackedEvent` — ex. "goal_explainer_open", "historico_day_tap".
    var eventName: String

    /// Raw value de `AppScreen` — em qual tela a interação aconteceu.
    var screen: String

    /// Contexto extra pequeno, serializado como JSON (`{"date":"2026-09-14",...}`).
    /// String em vez de dicionário porque SwiftData/CKRecord não guardam dict
    /// arbitrário direto — mesma razão de `IntakeLog` guardar campos achatados.
    var metadataJSON: String?

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var ckSystemFields: Data?

    init(userID: String, eventName: String, screen: String, metadataJSON: String? = nil) {
        self.id = UUID()
        self.userID = userID
        self.timestamp = .now
        self.eventName = eventName
        self.screen = screen
        self.metadataJSON = metadataJSON
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}
