import Foundation
import SwiftData

/// One record per user per day — sleep context, collected once daily.
@Model
final class DailyCheckin {
    @Attribute(.unique) var id: UUID
    var userID: String
    var dataReferencia: Date
    var horasSono: Double
    var horarioAcordou: Date

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        userID: String,
        dataReferencia: Date,
        horasSono: Double,
        horarioAcordou: Date
    ) {
        self.id = UUID()
        self.userID = userID
        self.dataReferencia = Calendar.current.startOfDay(for: dataReferencia)
        self.horasSono = horasSono
        self.horarioAcordou = horarioAcordou
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}
