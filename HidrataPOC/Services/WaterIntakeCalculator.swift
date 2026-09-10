import Foundation

/// Gender as used by the recommendation model — only male/female have a distinct
/// Adequate Intake baseline. Distinct from the app's `Genero` enum, which has three
/// more options (nonbinary, self-identify, decline to state); see `Genero.gender` in
/// ProfileFormView.swift for the mapping — those three all resolve to `nil` here and
/// are treated as a male/female average by `UserProfile.suggestedGoalML`.
enum Gender: String, Codable {
    case male, female
}

/// Not currently collected by the app (see spec §6 "Open questions for integration").
/// Needs an onboarding/settings input, or a default, before this model can be driven
/// by real per-user activity data.
enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary, light, moderate, active
}

enum HeatCategory: String, Codable {
    case none, caution, extremeCaution, danger, extremeDanger
}

struct WaterIntakeRecommendation {
    let baselineL: Double
    let activityIncrementL: Double
    let environmentIncrementL: Double
    let heatIndexF: Double
    let heatCategory: HeatCategory
    let totalL: Double
    let capped: Bool
    let elevatedRisk: Bool
}

/// Heuristic (not fitted/ML) daily water intake recommendation, ported 1:1 from a
/// Python reference implementation. Every constant below has a cited source and a
/// stated confidence level — see the project task spec for the full writeup. Do not
/// "improve" these numbers (extra precision, smoother curves) without updating both
/// implementations together, or the two stop being comparable.
enum WaterIntakeCalculator {

    // MARK: - §3.1 Baseline (gender + weight)

    /// IOM (2004) *Dietary Reference Intakes for Water* — sedentary adult Adequate
    /// Intake (total water, food + fluids). https://www.nationalacademies.org/read/10925/chapter/6
    private static let iomBaselineL: [Gender: Double] = [.male: 3.0, .female: 2.2]

    /// IOM reference body weight (kg) the baseline above is defined at.
    private static let iomReferenceWeightKg: [Gender: Double] = [.male: 70.0, .female: 57.0]

    // MARK: - §3.2 Activity increment

    /// ACSM Position Stand on Exercise and Fluid Replacement, converted into rough
    /// daily buckets. Least rigorously validated component of this model — there's
    /// no consensus table the way there is for heat (§3.3).
    private static let activityIncrementL: [ActivityLevel: Double] = [
        .sedentary: 0.00,
        .light: 0.35,
        .moderate: 0.70,
        .active: 1.20,
    ]

    // MARK: - §3.3 Environment increment

    /// Adapted (daily-life-scaled, not a direct unit conversion) from the U.S. Army
    /// Public Health Center's WBGT fluid-replacement table (TB MED 507 / "Garrison
    /// Operations"), scaled down from laborers to a mostly-sedentary general
    /// population. https://api.army.mil/e2/c/downloads/488892.pdf
    private static let environmentIncrementL: [HeatCategory: [ActivityLevel: Double]] = [
        .none: [.sedentary: 0.00, .light: 0.00, .moderate: 0.00, .active: 0.00],
        .caution: [.sedentary: 0.10, .light: 0.25, .moderate: 0.40, .active: 0.60],
        .extremeCaution: [.sedentary: 0.25, .light: 0.50, .moderate: 0.80, .active: 1.20],
        .danger: [.sedentary: 0.50, .light: 0.90, .moderate: 1.30, .active: 1.80],
        .extremeDanger: [.sedentary: 0.75, .light: 1.20, .moderate: 1.70, .active: 2.20],
    ]

    // MARK: - §3.5 Safety ceiling

    /// NIOSH/Army daily ceiling — avoids hyponatremia from over-recommending.
    private static let dailyCeilingL = 11.0

    /// Age threshold for `elevatedRisk` — CDC/NIOSH list older adults as a
    /// heat-vulnerable group (blunted thirst sensation, higher heat-illness risk).
    private static let elevatedRiskAgeThreshold = 65

    // MARK: - Computation

    /// - Parameters:
    ///   - heightCm: not used in the volume calculation in this version — kept for a
    ///     future BMI-/lean-mass-based refinement (see spec §7 Known limitations).
    ///   - age: deliberately not used in the baseline (§3.1) — only feeds `elevatedRisk`.
    static func recommend(
        gender: Gender,
        age: Int,
        heightCm: Double,
        weightKg: Double,
        activityLevel: ActivityLevel,
        tempC: Double,
        rhPercent: Double
    ) -> WaterIntakeRecommendation {
        let mlPerKg = (iomBaselineL[gender]! * 1000) / iomReferenceWeightKg[gender]!
        let baselineL = (mlPerKg * weightKg) / 1000

        let activityIncrementL = self.activityIncrementL[activityLevel]!

        let heatIndexF = heatIndex(tempC: tempC, rhPercent: rhPercent)
        let heatCategory = heatCategory(forHeatIndexF: heatIndexF)
        let environmentIncrementL = self.environmentIncrementL[heatCategory]![activityLevel]!

        let rawTotal = baselineL + activityIncrementL + environmentIncrementL
        let capped = rawTotal > dailyCeilingL
        let totalL = min(rawTotal, dailyCeilingL)

        let elevatedRisk = age >= elevatedRiskAgeThreshold && heatCategory != .none

        return WaterIntakeRecommendation(
            baselineL: baselineL,
            activityIncrementL: activityIncrementL,
            environmentIncrementL: environmentIncrementL,
            heatIndexF: heatIndexF,
            heatCategory: heatCategory,
            totalL: totalL,
            capped: capped,
            elevatedRisk: elevatedRisk
        )
    }

    /// NWS Heat Index (Rothfusz regression), °F in and out.
    /// https://www.wpc.ncep.noaa.gov/html/heatindex_equationbody.html
    private static func heatIndex(tempC: Double, rhPercent: Double) -> Double {
        let T = tempC * 9 / 5 + 32
        let RH = rhPercent

        let simpleHI = 0.5 * (T + 61 + ((T - 68) * 1.2) + (RH * 0.094))
        guard (T + simpleHI) / 2 >= 80 else { return simpleHI }

        var heatIndexF = -42.379
            + 2.04901523 * T
            + 10.14333127 * RH
            - 0.22475541 * T * RH
            - 0.00683783 * T * T
            - 0.05481717 * RH * RH
            + 0.00122874 * T * T * RH
            + 0.00085282 * T * RH * RH
            - 0.00000199 * T * T * RH * RH

        if RH < 13 && T >= 80 && T <= 112 {
            let adj = ((13 - RH) / 4) * ((17 - abs(T - 95)) / 17).squareRoot()
            heatIndexF -= adj
        } else if RH > 85 && T >= 80 && T <= 87 {
            let adj = ((RH - 85) / 10) * ((87 - T) / 5)
            heatIndexF += adj
        }

        return heatIndexF
    }

    private static func heatCategory(forHeatIndexF heatIndexF: Double) -> HeatCategory {
        switch heatIndexF {
        case ..<80: return .none
        case ..<90: return .caution
        case ..<105: return .extremeCaution
        case ...130: return .danger
        default: return .extremeDanger
        }
    }
}
