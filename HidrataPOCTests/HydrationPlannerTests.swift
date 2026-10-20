import Foundation
import Testing
@testable import HidrataPOC

/// `HydrationPlanner.idealDayCurve` runs hosted in the app (it reads `PolicyStore`,
/// which falls back to the bundled `policy_params.json`), so it always has a real
/// prior to score candidate hours against — same as production on a fresh install.
@MainActor
struct HydrationPlannerTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    private func profile() -> UserProfile {
        UserProfile(userID: "test", idade: 30, genero: "feminino", pesoKg: 65, alturaCm: 165,
                    fusoHorario: "America/Sao_Paulo", metaDiariaML: 2000)
    }

    @Test func curveIsMonotonicAndReachesTheGoal() throws {
        let plan = try #require(HydrationPlanner.idealDayCurve(
            profile: profile(), effectiveGoalML: 2000,
            weather: WeatherContext(temperaturaC: 31, umidadeRelativa: 0.4, sensacaoTermicaC: 33),
            day: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now,
            calendar: calendar
        ))

        #expect(!plan.isEmpty)
        #expect(plan.last?.idealCumulativeML == 2000)
        for (a, b) in zip(plan, plan.dropFirst()) {
            #expect(b.idealCumulativeML >= a.idealCumulativeML)
            #expect(b.hour > a.hour)
        }
    }

    @Test func pastDayGetsItsOwnStableCurve() throws {
        let aWeekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let plan = try #require(HydrationPlanner.idealDayCurve(
            profile: profile(), effectiveGoalML: 1800, weather: nil, day: aWeekAgo, calendar: calendar
        ))
        #expect(plan.last?.idealCumulativeML == 1800)

        // Same day, same inputs, called again: the plan must not jitter between
        // re-renders of the same past day's detail sheet.
        let again = try #require(HydrationPlanner.idealDayCurve(
            profile: profile(), effectiveGoalML: 1800, weather: nil, day: aWeekAgo, calendar: calendar
        ))
        #expect(plan.map(\.idealCumulativeML) == again.map(\.idealCumulativeML))
    }

    @Test func noGoalMeansNoPlan() {
        #expect(HydrationPlanner.idealDayCurve(profile: profile(), effectiveGoalML: 0, weather: nil, day: .now, calendar: calendar) == nil)
    }
}
