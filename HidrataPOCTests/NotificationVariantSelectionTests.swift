import Foundation
import Testing
@testable import HidrataPOC

/// Fase 3.2 da spec HYDRATE-NP-01 — cobre `NotificationScheduler.selectVariant`
/// pros cenários da tabela da seção 3, com `WeatherContext`/`IntakeLog`s fabricados
/// à mão (nenhum precisa de `ModelContext` — `selectVariant` é pura sobre esses
/// valores).
@MainActor
struct NotificationVariantSelectionTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    private func date(day: Int = 15, hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = day
        comps.hour = hour
        return calendar.date(from: comps)!
    }

    private func profile(metaDiariaML: Int = 2000) -> UserProfile {
        UserProfile(
            userID: "user-1",
            idade: 30,
            genero: "masculino",
            pesoKg: 75,
            alturaCm: 175,
            fusoHorario: "America/Sao_Paulo",
            metaDiariaML: metaDiariaML
        )
    }

    private func log(day: Int, hour: Int, volumeML: Int) -> IntakeLog {
        IntakeLog(
            userID: "user-1",
            timestamp: date(day: day, hour: hour),
            preset: .custom(volumeML: volumeML),
            origem: .manual,
            notificationEventID: nil
        )
    }

    @Test func hotDayWinsOutsideEvening() {
        let weather = WeatherContext(temperaturaC: 32, umidadeRelativa: 50, sensacaoTermicaC: 34)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 13), weather: weather, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .hotDay)
    }

    @Test func coldDayOutsideEvening() {
        let weather = WeatherContext(temperaturaC: 10, umidadeRelativa: 60, sensacaoTermicaC: 8)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 13), weather: weather, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .coldDay)
    }

    @Test func mildMorning() {
        let weather = WeatherContext(temperaturaC: 22, umidadeRelativa: 50, sensacaoTermicaC: 22)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 8), weather: weather, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .mildMorning)
    }

    @Test func noWeatherStillFallsBackToTimeOfDayRules() {
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 8), weather: nil, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .mildMorning)
    }

    @Test func middayNeutralGroupSamplesAllThreeVariants() {
        let weather = WeatherContext(temperaturaC: 22, umidadeRelativa: 50, sensacaoTermicaC: 22)
        let allowed: Set<NotificationVariant> = [.middayNeutral, .symptomHeadacheMidday, .symptomConcentrationMidday]
        var seen: Set<NotificationVariant> = []
        for _ in 0..<200 {
            let variant = NotificationScheduler.selectVariant(
                firesAt: date(hour: 14), weather: weather, profile: profile(), logs: [], calendar: calendar
            )
            #expect(allowed.contains(variant))
            seen.insert(variant)
        }
        // D-2 exige sorteio uniforme entre as 3 — com 200 tentativas, a chance de
        // sempre cair na mesma é (1/3)^199, ou seja, essencialmente zero.
        #expect(seen.count > 1)
    }

    @Test func streakRiskEveningBeatsHotWeather() {
        let weather = WeatherContext(temperaturaC: 35, umidadeRelativa: 40, sensacaoTermicaC: 38)
        let yesterdayMetGoal = log(day: 14, hour: 12, volumeML: 2500)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 20), weather: weather, profile: profile(), logs: [yesterdayMetGoal], calendar: calendar
        )
        #expect(variant == .streakRiskEvening)
    }

    @Test func symptomIrritabilityEveningWhenStreakNotAtRisk() {
        let weather = WeatherContext(temperaturaC: 22, umidadeRelativa: 50, sensacaoTermicaC: 22)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 20), weather: weather, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .symptomIrritabilityEvening)
    }
}
