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

    @Test func nearGoalWhenMascotIsInItsLateStages() {
        let weather = WeatherContext(temperaturaC: 35, umidadeRelativa: 40, sensacaoTermicaC: 38)
        // Meta de 2000 mL: 1300 mL = 65% (estágio 2) e 1700 mL = 85% (estágio 1), mesmo num dia quente.
        for consumed in [1300, 1700] {
            let variant = NotificationScheduler.selectVariant(
                firesAt: date(hour: 14), weather: weather, profile: profile(),
                logs: [log(day: 15, hour: 10, volumeML: consumed)], calendar: calendar
            )
            #expect(variant == .nearGoal)
        }
    }

    @Test func wellHydratedWhenMascotIsInTheMiddleStage() {
        // 1000 mL de 2000 = 50% (estágio 3).
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 14), weather: nil, profile: profile(),
            logs: [log(day: 15, hour: 10, volumeML: 1000)], calendar: calendar
        )
        #expect(variant == .wellHydrated)
    }

    @Test func earlyStagesKeepTheUsualVariants() {
        // 600 mL de 2000 = 30% (estágio 4): segue a regra de clima e horário.
        let weather = WeatherContext(temperaturaC: 32, umidadeRelativa: 50, sensacaoTermicaC: 34)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 14), weather: weather, profile: profile(),
            logs: [log(day: 15, hour: 10, volumeML: 600)], calendar: calendar
        )
        #expect(variant == .hotDay)
    }

    @Test func streakRiskStillBeatsProgressInTheEvening() {
        let yesterdayMetGoal = log(day: 14, hour: 12, volumeML: 2500)
        let todayAlmostThere = log(day: 15, hour: 12, volumeML: 1700)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 20), weather: nil, profile: profile(),
            logs: [yesterdayMetGoal, todayAlmostThere], calendar: calendar
        )
        #expect(variant == .streakRiskEvening)
    }

    @Test func everyVariantHasCopyAndEachSlotKeepsItsOwn() {
        for variant in NotificationVariant.allCases {
            #expect(!variant.copies.isEmpty)
            #expect(variant.copies.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })

            let slotID = UUID()
            #expect(variant.copy(for: slotID) == variant.copy(for: slotID))
            #expect(variant.copies.contains(variant.copy(for: slotID)))
        }
    }

    @Test func variantsWithSeveralOptionsUseMoreThanOne() {
        var seen: Set<String> = []
        for _ in 0..<200 {
            seen.insert(NotificationVariant.hotDay.copy(for: UUID()).title)
        }
        #expect(seen.count > 1)
    }

    @Test func symptomIrritabilityEveningWhenStreakNotAtRisk() {
        let weather = WeatherContext(temperaturaC: 22, umidadeRelativa: 50, sensacaoTermicaC: 22)
        let variant = NotificationScheduler.selectVariant(
            firesAt: date(hour: 20), weather: weather, profile: profile(), logs: [], calendar: calendar
        )
        #expect(variant == .symptomIrritabilityEvening)
    }
}
