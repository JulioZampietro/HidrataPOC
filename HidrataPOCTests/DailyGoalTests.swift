import Foundation
import SwiftData
import Testing
@testable import HidrataPOC

/// Per-day goals: editing the goal (or a new forecast) only affects today, so past
/// days — and the streak built from them — keep the goal they actually had.
@MainActor
struct DailyGoalTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    private func date(day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func goal(day: Int, base: Int, adjustment: Int = 0) -> DailyGoal {
        DailyGoal(userID: "user-1", dayKey: DailyGoal.dayKey(for: date(day: day), calendar: calendar), baseGoalML: base, adjustmentML: adjustment)
    }

    private func log(day: Int, volumeML: Int) -> IntakeLog {
        IntakeLog(userID: "user-1", timestamp: date(day: day), preset: .custom(volumeML: volumeML), origem: .manual, notificationEventID: nil)
    }

    private func resolver(_ goals: [DailyGoal], todayGoalML: Int, today: Int = 15, fallbackGoalML: Int = 2000) -> DailyGoalResolver {
        DailyGoalResolver(goals: goals, todayGoalML: todayGoalML, fallbackGoalML: fallbackGoalML, calendar: calendar, now: date(day: today))
    }

    @Test func pastDayKeepsItsRecordedGoal() {
        let goals = resolver([goal(day: 13, base: 2000, adjustment: 150)], todayGoalML: 3000)
        #expect(goals.goalML(on: date(day: 13)) == 2150)
    }

    @Test func todayUsesLiveGoalEvenWhenRecorded() {
        let goals = resolver([goal(day: 15, base: 2000)], todayGoalML: 3000)
        #expect(goals.goalML(on: date(day: 15, hour: 8)) == 3000)
        #expect(goals.goalML(on: date(day: 16)) == 3000)
    }

    @Test func dayWithoutRecordRepeatsPreviousDay() {
        let goals = resolver([goal(day: 10, base: 1800), goal(day: 12, base: 2200)], todayGoalML: 3000)
        #expect(goals.goalML(on: date(day: 11)) == 1800)
        #expect(goals.goalML(on: date(day: 14)) == 2200)
    }

    @Test func daysBeforeFirstRecordUseEarliestRecord() {
        let goals = resolver([goal(day: 10, base: 1800), goal(day: 12, base: 2200)], todayGoalML: 3000)
        #expect(goals.goalML(on: date(day: 2)) == 1800)
    }

    @Test func noRecordsFallsBackToBaseGoal() {
        let goals = resolver([], todayGoalML: 3000, fallbackGoalML: 2000)
        #expect(goals.goalML(on: date(day: 14)) == 2000)
    }

    @Test func raisingTodaysGoalDoesNotBreakPastStreak() {
        // Days 12–14 met their 2000 mL goal; the goal is raised to 3000 mL today.
        let goals = resolver([goal(day: 12, base: 2000), goal(day: 13, base: 2000), goal(day: 14, base: 2000)], todayGoalML: 3000)
        let logs = [log(day: 12, volumeML: 2000), log(day: 13, volumeML: 2100), log(day: 14, volumeML: 2000), log(day: 15, volumeML: 2500)]
        let streak = HydrationMath.currentStreak(logs, goalML: goals.goalML(on:), calendar: calendar, now: date(day: 15))
        #expect(streak == 3)
        #expect(HydrationMath.isStreakAtRisk(logs, goalML: goals.goalML(on:), calendar: calendar, firesAt: date(day: 15, hour: 20)))
    }

    @Test func meetingTodaysNewGoalExtendsStreak() {
        let goals = resolver([goal(day: 14, base: 2000)], todayGoalML: 3000)
        let logs = [log(day: 14, volumeML: 2000), log(day: 15, volumeML: 3000)]
        #expect(HydrationMath.currentStreak(logs, goalML: goals.goalML(on:), calendar: calendar, now: date(day: 15)) == 2)
    }

    @Test func recordTodayUpdatesOnlyTodaysRow() throws {
        let schema = Schema([DailyGoal.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let yesterday = goal(day: 14, base: 2000, adjustment: 100)
        context.insert(yesterday)

        DailyGoal.recordToday(userID: "user-1", baseGoalML: 2000, adjustmentML: 250, context: context, calendar: calendar, now: date(day: 15))
        // Goal edited later today, no fresh forecast: keeps today's adjustment.
        DailyGoal.recordToday(userID: "user-1", baseGoalML: 3000, adjustmentML: nil, context: context, calendar: calendar, now: date(day: 15, hour: 18))

        let rows = try context.fetch(FetchDescriptor<DailyGoal>(sortBy: [SortDescriptor(\.dayKey)]))
        #expect(rows.count == 2)
        #expect(rows[0].goalML == 2100)
        #expect(rows[1].baseGoalML == 3000)
        #expect(rows[1].adjustmentML == 250)
    }
}
