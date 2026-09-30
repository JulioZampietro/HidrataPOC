import Foundation
import Testing
@testable import HidrataPOC

/// Cobre a decisão pura por trás do agendamento de lembretes (bugs 1 e 3 do
/// NotificationsHandoff.md): enquanto houver um lembrete sem resposta na Central de
/// Notificações, nenhum outro sai — exceto o das 8h do dia seguinte, que sempre sai;
/// os que sobraram da noite anterior são apagados.
struct NotificationSlotDecisionTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    private func date(day: Int = 15, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func slot(day: Int = 15, hour: Int, minute: Int = 0, armedAt: Date? = nil, captured: Bool = false) -> PendingSlot {
        PendingSlot(
            id: UUID(),
            firesAt: date(day: day, hour: hour, minute: minute),
            captured: captured,
            variant: NotificationVariant.middayNeutral.rawValue,
            armedAt: armedAt
        )
    }

    private func unread(_ date: Date, id: String = UUID().uuidString) -> DeliveredReminder {
        DeliveredReminder(id: id, date: date)
    }

    // MARK: - slotsToArm: next slot only when nothing is unanswered, 8h always

    private func toArm(_ slots: [PendingSlot], now: Date, delivered: [DeliveredReminder] = []) -> [Date] {
        NotificationScheduler.slotsToArm(slots, now: now, delivered: delivered, calendar: calendar).map(\.firesAt)
    }

    @Test func armsTheEarliestFutureSlotPlusTomorrowMorning() {
        let slots = [12, 10, 14].map { slot(hour: $0) } + [slot(day: 16, hour: 8), slot(day: 16, hour: 10)]
        #expect(toArm(slots, now: date(hour: 9)) == [date(hour: 10), date(day: 16, hour: 8)])
    }

    @Test func pastSlotsAreNeverArmed() {
        let slots = [8, 10].map { slot(hour: $0) }
        #expect(toArm(slots, now: date(hour: 10, minute: 1)).isEmpty)
    }

    @Test func unreadReminderBlocksTheRestOfTheDay() {
        let slots = [10, 12, 14, 22].map { slot(hour: $0) } + [slot(day: 16, hour: 8)]
        // Só o 8h de amanhã continua armado.
        #expect(toArm(slots, now: date(hour: 9), delivered: [unread(date(hour: 8))]) == [date(day: 16, hour: 8)])
        #expect(toArm(slots, now: date(hour: 19), delivered: [unread(date(hour: 8))]) == [date(day: 16, hour: 8)])
    }

    /// Lembrete das 22h sem resposta: a madrugada continua bloqueada, mas o 8h sai.
    @Test func overnightUnreadStillLetsTheMorningSlotThrough() {
        let slots = [slot(day: 16, hour: 8), slot(day: 16, hour: 10)]
        #expect(toArm(slots, now: date(hour: 23), delivered: [unread(date(hour: 22))]) == [date(day: 16, hour: 8)])
        #expect(toArm(slots, now: date(day: 16, hour: 3), delivered: [unread(date(hour: 22))]) == [date(day: 16, hour: 8)])
    }

    @Test func answeringUnblocksTheNextSlot() {
        let slots = [12, 14].map { slot(hour: $0) }
        #expect(toArm(slots, now: date(hour: 12, minute: 30)) == [date(hour: 14)])
    }

    @Test func snoozeBeforeNextFixedHourIsArmedFirst() {
        let slots = [slot(hour: 12), slot(hour: 10, minute: 20)]
        #expect(toArm(slots, now: date(hour: 10, minute: 5)) == [date(hour: 10, minute: 20)])
    }

    @Test func tomorrowsMorningSlotIsArmedOnceAfterTheLastOneToday() {
        let slots = [slot(hour: 22), slot(day: 16, hour: 8)]
        #expect(toArm(slots, now: date(hour: 22, minute: 5)) == [date(day: 16, hour: 8)])
    }

    // MARK: - Overnight cleanup

    @Test func reminderDayRunsFrom8hTo8h() {
        #expect(NotificationScheduler.reminderDayStart(containing: date(hour: 23), calendar: calendar) == date(hour: 8))
        #expect(NotificationScheduler.reminderDayStart(containing: date(day: 16, hour: 7, minute: 59), calendar: calendar) == date(hour: 8))
        #expect(NotificationScheduler.reminderDayStart(containing: date(day: 16, hour: 8), calendar: calendar) == date(day: 16, hour: 8))
    }

    @Test func lastNightsUnreadIsDeletedFrom8h() {
        let lastNight = unread(date(hour: 22))
        let thisMorning = unread(date(day: 16, hour: 8))
        #expect(NotificationScheduler.staleReminderIDs([lastNight], now: date(day: 16, hour: 7), calendar: calendar).isEmpty)
        #expect(NotificationScheduler.staleReminderIDs([lastNight, thisMorning], now: date(day: 16, hour: 8, minute: 1), calendar: calendar) == [lastNight.id])
    }

    @Test func todaysUnreadIsNeverDeleted() {
        let delivered = [unread(date(hour: 8)), unread(date(hour: 14))]
        #expect(NotificationScheduler.staleReminderIDs(delivered, now: date(hour: 23), calendar: calendar).isEmpty)
    }

    // MARK: - decideSlotAction: recording, never re-arming

    @Test func armedSlotPastItsTimeIsOnlyRecorded() {
        let s = slot(hour: 8, armedAt: date(hour: 7))
        #expect(NotificationScheduler.decideSlotAction(slot: s, now: date(hour: 9), delivered: []) == .recordFired)
    }

    @Test func deliveredLegacySlotIsRecorded() {
        let s = slot(hour: 8)
        let delivered = [unread(date(hour: 8), id: s.id.uuidString)]
        #expect(NotificationScheduler.decideSlotAction(slot: s, now: date(hour: 9), delivered: delivered) == .recordFired)
    }

    @Test func slotThatPassedUnarmedIsDroppedWithoutEvent() {
        #expect(NotificationScheduler.decideSlotAction(slot: slot(hour: 10), now: date(hour: 10, minute: 5), delivered: []) == .dropUnsent)
    }

    @Test func imminentArmedSlotIsCaptured() {
        let s = slot(hour: 10, armedAt: date(hour: 9))
        #expect(NotificationScheduler.decideSlotAction(slot: s, now: date(hour: 9, minute: 55), delivered: []) == .capture)
    }

    @Test func imminentUnarmedSlotIsNotCaptured() {
        #expect(NotificationScheduler.decideSlotAction(slot: slot(hour: 10), now: date(hour: 9, minute: 55), delivered: []) == .wait)
    }

    @Test func farFutureArmedSlotWaits() {
        let s = slot(hour: 10, armedAt: date(hour: 8))
        #expect(NotificationScheduler.decideSlotAction(slot: s, now: date(hour: 9), delivered: []) == .wait)
    }

    @Test func capturedSlotIsLeftAlone() {
        let s = slot(hour: 8, armedAt: date(hour: 7), captured: true)
        #expect(NotificationScheduler.decideSlotAction(slot: s, now: date(hour: 9), delivered: []) == .wait)
    }
}
