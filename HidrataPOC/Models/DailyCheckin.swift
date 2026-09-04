import Foundation
import SwiftData

/// One record per user per day — sleep and exercise context, collected once daily.
@Model
final class DailyCheckin {
    @Attribute(.unique) var id: UUID
    var userID: String
    var dataReferencia: Date
    var horasSono: Double
    var horarioAcordou: Date
    var treinou: Bool
    var intensidadeExercicio: String

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        userID: String,
        dataReferencia: Date,
        horasSono: Double,
        horarioAcordou: Date,
        treinou: Bool,
        intensidadeExercicio: IntensidadeExercicio
    ) {
        self.id = UUID()
        self.userID = userID
        self.dataReferencia = Calendar.current.startOfDay(for: dataReferencia)
        self.horasSono = horasSono
        self.horarioAcordou = horarioAcordou
        self.treinou = treinou
        self.intensidadeExercicio = intensidadeExercicio.rawValue
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}

enum IntensidadeExercicio: String, CaseIterable, Identifiable {
    case nenhuma, leve, moderada, intensa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nenhuma: return "Nenhuma"
        case .leve: return "Leve"
        case .moderada: return "Moderada"
        case .intensa: return "Intensa"
        }
    }
}
