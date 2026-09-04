import Foundation
import SwiftData

/// One record per user, created at onboarding and updated from the profile screen.
/// `id` doubles as the CloudKit record name, so local and remote identity stay in sync.
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var userID: String
    var idade: Int
    var genero: String?
    var pesoKg: Double
    var alturaCm: Double
    var fusoHorario: String
    var metaDiariaML: Int

    /// Volume (mL) for the one user-editable quick-log button, alongside the fixed
    /// Copo/Garrafa/Galão presets. Defaulted for lightweight migration on existing rows.
    var customIntakeML: Int = 300

    var criadoEm: Date
    var atualizadoEm: Date

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Archived `CKRecord` system fields (change tag, etc.) from the last successful
    /// save, so later edits can update the existing CloudKit record instead of
    /// colliding with a fresh `CKRecord(recordType:recordID:)`.
    var ckSystemFields: Data?

    init(
        userID: String,
        idade: Int,
        genero: String?,
        pesoKg: Double,
        alturaCm: Double,
        fusoHorario: String,
        metaDiariaML: Int,
        customIntakeML: Int = 300
    ) {
        self.id = UUID()
        self.userID = userID
        self.idade = idade
        self.genero = genero
        self.pesoKg = pesoKg
        self.alturaCm = alturaCm
        self.fusoHorario = fusoHorario
        self.metaDiariaML = metaDiariaML
        self.customIntakeML = customIntakeML
        self.criadoEm = .now
        self.atualizadoEm = .now
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    /// Suggested daily goal (mL) from body weight — the classic 35 mL/kg heuristic,
    /// clamped to the commonly recommended 2000–3000 mL range so extreme weights
    /// (very low or very high) don't produce an unrealistic suggestion. Only a
    /// starting point; the user can edit it in the onboarding/profile form.
    static func suggestedGoalML(pesoKg: Double) -> Int {
        let raw = Int((pesoKg * 35).rounded())
        return min(3000, max(2000, raw))
    }
}
