import Testing
@testable import HidrataPOC

/// Parity cases against the Python reference implementation — see the model spec §5.
struct WaterIntakeCalculatorTests {
    @Test func sedentaryMildClimate() {
        let r = WaterIntakeCalculator.recommend(
            gender: .male, age: 35, heightCm: 178, weightKg: 82,
            activityLevel: .sedentary, tempC: 22, rhPercent: 50
        )
        #expect(abs(r.heatIndexF - 70.8) < 0.1)
        #expect(r.heatCategory == .none)
        #expect(abs(r.totalL - 3.51) < 0.01)
        #expect(!r.capped)
        #expect(!r.elevatedRisk)
    }

    @Test func moderateActivityHotHumid() {
        let r = WaterIntakeCalculator.recommend(
            gender: .female, age: 29, heightCm: 165, weightKg: 61,
            activityLevel: .moderate, tempC: 34, rhPercent: 70
        )
        #expect(abs(r.heatIndexF - 116.2) < 0.1)
        #expect(r.heatCategory == .danger)
        #expect(abs(r.totalL - 4.35) < 0.01)
        #expect(!r.elevatedRisk)
    }

    @Test func activeExtremeHeat() {
        let r = WaterIntakeCalculator.recommend(
            gender: .male, age: 24, heightCm: 180, weightKg: 75,
            activityLevel: .active, tempC: 38, rhPercent: 80
        )
        #expect(abs(r.heatIndexF - 160.3) < 0.1)
        #expect(r.heatCategory == .extremeDanger)
        #expect(abs(r.totalL - 6.61) < 0.01)
        #expect(!r.elevatedRisk)
    }

    @Test func olderAdultElevatedRisk() {
        let r = WaterIntakeCalculator.recommend(
            gender: .female, age: 71, heightCm: 160, weightKg: 58,
            activityLevel: .light, tempC: 36, rhPercent: 65
        )
        #expect(abs(r.heatIndexF - 123.8) < 0.1)
        #expect(r.heatCategory == .danger)
        #expect(abs(r.totalL - 3.49) < 0.01)
        #expect(r.elevatedRisk)
    }

    @Test func totalIsCappedAtElevenLiters() {
        let r = WaterIntakeCalculator.recommend(
            gender: .male, age: 40, heightCm: 190, weightKg: 200,
            activityLevel: .active, tempC: 45, rhPercent: 90
        )
        #expect(r.totalL == 11.0)
        #expect(r.capped)
    }
}
