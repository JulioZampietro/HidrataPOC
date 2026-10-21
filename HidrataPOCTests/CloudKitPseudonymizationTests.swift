import Foundation
import Testing
@testable import HidrataPOC

/// The `UserProfile` record goes to the CloudKit **public** database, so what it
/// carries is a privacy decision, not a formatting one — see
/// `CloudKitSyncService.push(_ profile:)`. These cover the two derivations that
/// replaced the raw anthropometrics, plus the round trip the restore path depends on.
@MainActor
struct CloudKitPseudonymizationTests {
    @Test func ageBandsAreFiveYearsWideAndCollapseAtEighty() {
        #expect(CloudKitSyncService.ageBand(30) == "30-34")
        #expect(CloudKitSyncService.ageBand(34) == "30-34")
        #expect(CloudKitSyncService.ageBand(35) == "35-39")
        #expect(CloudKitSyncService.ageBand(10) == "10-14")
        // Nobody old enough to be identifiable by a narrow band gets one.
        #expect(CloudKitSyncService.ageBand(80) == "80+")
        #expect(CloudKitSyncService.ageBand(97) == "80+")
        // A profile that never got a real age must not leak a misleading band.
        #expect(CloudKitSyncService.ageBand(0) == "desconhecida")
    }

    @Test func bandMidpointRoundTripsCloseEnoughForRestore() throws {
        for age in [12, 25, 33, 47, 64, 79] {
            let recovered = try #require(CloudKitSyncService.ageFromBand(CloudKitSyncService.ageBand(age)))
            #expect(abs(recovered - age) <= 2, "idade \(age) voltou como \(recovered)")
        }
        #expect(CloudKitSyncService.ageFromBand("80+") == 82)
        #expect(CloudKitSyncService.ageFromBand("desconhecida") == nil)
        #expect(CloudKitSyncService.ageFromBand("") == nil)
    }

    @Test func bmiReplacesWeightAndHeight() throws {
        // 70 kg a 1,75 m = 22,857… -> uma decimal
        let value = try #require(CloudKitSyncService.bmi(pesoKg: 70, alturaCm: 175))
        #expect(value == 22.9)
    }

    /// A profile with a zero/garbage measurement must push no BMI at all rather than
    /// an infinity or a NaN, which would poison the training frame.
    @Test func bmiIsNilForUnusableMeasurements() {
        #expect(CloudKitSyncService.bmi(pesoKg: 70, alturaCm: 0) == nil)
        #expect(CloudKitSyncService.bmi(pesoKg: 0, alturaCm: 175) == nil)
        #expect(CloudKitSyncService.bmi(pesoKg: -5, alturaCm: 175) == nil)
    }
}
