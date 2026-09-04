import Foundation
import SwiftData

/// One record per hydration reminder sent — the central table for the future
/// recommendation model. Created with full context around send time, then updated
/// (once) with the interaction outcome, either immediately or after the
/// `Constants.notificationResponseWindowMinutes` timeout.
@Model
final class NotificationEvent {
    @Attribute(.unique) var id: UUID
    var userID: String
    var sentAt: Date
    var diaSemana: Int
    var fimDeSemana: Bool
    var feriado: Bool
    var temperaturaC: Double
    var umidadeRelativa: Double
    var sensacaoTermicaC: Double
    var ocupadoNoMomento: Bool
    var densidadeEventosDia: Int
    var deficitAcumuladoML: Int
    var tempoDesdeUltimoRegistroMin: Int?

    /// nil until an interaction (action, tap, dismiss) or the timeout resolves it.
    var statusInteracao: String?
    var tempoAteAgirMin: Int?
    var resultouEmConsumo: Bool

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var ckSystemFields: Data?

    init(
        id: UUID = UUID(),
        userID: String,
        sentAt: Date,
        temperaturaC: Double,
        umidadeRelativa: Double,
        sensacaoTermicaC: Double,
        ocupadoNoMomento: Bool,
        densidadeEventosDia: Int,
        deficitAcumuladoML: Int,
        tempoDesdeUltimoRegistroMin: Int?
    ) {
        self.id = id
        self.userID = userID
        self.sentAt = sentAt
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: sentAt)
        self.diaSemana = weekday
        self.fimDeSemana = weekday == 1 || weekday == 7
        self.feriado = false // holiday calendar out of scope for this POC
        self.temperaturaC = temperaturaC
        self.umidadeRelativa = umidadeRelativa
        self.sensacaoTermicaC = sensacaoTermicaC
        self.ocupadoNoMomento = ocupadoNoMomento
        self.densidadeEventosDia = densidadeEventosDia
        self.deficitAcumuladoML = deficitAcumuladoML
        self.tempoDesdeUltimoRegistroMin = tempoDesdeUltimoRegistroMin
        self.statusInteracao = nil
        self.tempoAteAgirMin = nil
        self.resultouEmConsumo = false
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}

enum StatusInteracao: String {
    case aberta
    case ignorada
    case soneca
}
