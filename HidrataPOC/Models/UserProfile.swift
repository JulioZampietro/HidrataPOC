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

    /// Free-text label, set only when `genero == "autodeclarado"` ("self-identify").
    var generoAutoDeclarado: String?

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
        generoAutoDeclarado: String? = nil,
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
        self.generoAutoDeclarado = generoAutoDeclarado
        self.pesoKg = pesoKg
        self.alturaCm = alturaCm
        self.fusoHorario = fusoHorario
        self.metaDiariaML = metaDiariaML
        self.customIntakeML = customIntakeML
        self.criadoEm = .now
        self.atualizadoEm = .now
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    /// Suggested daily goal (mL) from `WaterIntakeCalculator` — baseline (gender +
    /// weight) plus activity, per the model spec. Only a starting point; the user can
    /// edit it in the onboarding/profile form.
    ///
    /// `gender` is `nil` for every `Genero` case other than male/female (nonbinary,
    /// self-identify, decline to state) — averages the male/female baselines rather
    /// than guessing, since there's no gender-neutral Adequate Intake figure in the
    /// source model.
    ///
    /// `activityLevel` isn't collected yet (spec §6 open question), so this always
    /// passes `.sedentary`. `tempC`/`rhPercent` are fixed at mild, unremarkable values
    /// — comfortably below the Heat Index "caution" threshold — so the environment
    /// increment is always 0 here; this is a profile-level baseline, not a live
    /// forecast-driven target (that's `tempContext` in HomeView, computed separately
    /// from today's actual weather).
    static func suggestedGoalML(gender: Gender?, idade: Int, pesoKg: Double, alturaCm: Double) -> Int {
        let neutralTempC = 20.0
        let neutralRHPercent = 40.0

        func totalL(_ gender: Gender) -> Double {
            WaterIntakeCalculator.recommend(
                gender: gender,
                age: idade,
                heightCm: alturaCm,
                weightKg: pesoKg,
                activityLevel: .sedentary,
                tempC: neutralTempC,
                rhPercent: neutralRHPercent
            ).totalL
        }

        let liters: Double
        switch gender {
        case .male:
            liters = totalL(.male)
        case .female:
            liters = totalL(.female)
        case nil:
            liters = (totalL(.male) + totalL(.female)) / 2
        }

        return Int((liters * 1000).rounded())
    }
}
