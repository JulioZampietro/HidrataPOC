import Foundation
import SwiftData

/// One record per water-intake event, tapped from the main screen or a notification action.
@Model
final class IntakeLog {
    @Attribute(.unique) var id: UUID
    var userID: String
    var timestamp: Date
    var volumeML: Int
    var tipoEntrada: String
    var origem: String
    var notificationEventID: String?

    /// Which surface logged this intake — "app" (in-app buttons, notification quick
    /// actions), "siri" (Siri/Shortcuts phrase), "liveActivity" (Lock Screen /
    /// Dynamic Island quick-log buttons), or "actionButton" (Control Center /
    /// hardware Action Button controls). Orthogonal to `origem`, which instead says
    /// whether a notification prompted the drink.
    var source: String = "app"

    /// UUID da amostra no HealthKit correspondente a este registro — usado para
    /// deduplicar importações do Health e para deletar a amostra ao apagar o log.
    var healthKitUUID: String?

    /// Weather at the moment of logging — reused from a recent cached reading (see
    /// `WeatherContextService.cachedContext`) rather than fetched fresh, so logging
    /// stays instant. Lets a future model use spontaneous ("manual") intakes as
    /// weather-aware baseline signal too, not just notification-linked ones (which
    /// already carry weather via their `NotificationEvent`). nil when no reading was
    /// cached recently enough (e.g. right after a cold app launch).
    var temperaturaC: Double?
    var umidadeRelativa: Double?
    var sensacaoTermicaC: Double?

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        userID: String,
        timestamp: Date = .now,
        preset: Constants.IntakePreset,
        origem: OrigemRegistro,
        notificationEventID: String?,
        weather: WeatherContext? = nil,
        source: String = "app"
    ) {
        self.id = UUID()
        self.userID = userID
        self.timestamp = timestamp
        self.volumeML = preset.volumeML
        self.tipoEntrada = preset.tipoEntrada
        self.origem = origem.rawValue
        self.notificationEventID = notificationEventID
        self.source = source
        self.temperaturaC = weather?.temperaturaC
        self.umidadeRelativa = weather?.umidadeRelativa
        self.sensacaoTermicaC = weather?.sensacaoTermicaC
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    /// Inicializador para registros importados do HealthKit — volume livre (não por preset).
    init(userID: String, timestamp: Date, volumeML: Int, tipoEntrada: String, origem: OrigemRegistro, source: String, healthKitUUID: String) {
        self.id = UUID()
        self.userID = userID
        self.timestamp = timestamp
        self.volumeML = volumeML
        self.tipoEntrada = tipoEntrada
        self.origem = origem.rawValue
        self.notificationEventID = nil
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}

enum OrigemRegistro: String {
    case manual
    case notificacao
}
