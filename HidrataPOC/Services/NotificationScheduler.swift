import Foundation
import SwiftData
import UserNotifications

/// A slot the app has committed to firing a local notification at, but hasn't yet
/// captured weather/calendar/deficit context for. Local-only bookkeeping (UserDefaults
/// JSON) — deliberately not a synced record type, since it's scheduling plumbing, not
/// data for the model. `NotificationEvent` is the record that matters and only gets
/// created once context is captured.
private struct PendingSlot: Codable {
    let id: UUID
    let firesAt: Date
    var captured: Bool
}

/// Drives the whole "notification with context" pipeline described in the spec:
/// schedules semi-random reminder times for the day, captures context shortly before
/// each fires (creating the `NotificationEvent`), and resolves `statusInteracao` either
/// from a direct interaction or, failing that, a timeout.
///
/// Context capture is meant to happen "at send, or shortly before, in background."
/// iOS gives local notifications no exact-time background hook (`BGAppRefreshTask` is
/// opportunistic, not guaranteed to fire close to a specific instant), so this POC
/// leans on two reliable paths instead: a foreground poll (`tick()`, driven by
/// `HidrataPOCApp`'s scenePhase/timer) that captures context a few minutes ahead of
/// each slot while the app is open, and a same-day best-effort `BGAppRefreshTask` for
/// when it isn't. Either way, `NotificationDelegate` captures context synchronously as
/// a last-resort fallback the moment a tester interacts with a notification whose
/// event was never captured in time — so no interaction is ever orphaned.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// How far ahead of a slot's fire time we start trying to capture context, so
    /// there's headroom for the WeatherKit/EventKit network round trip to finish.
    private static let captureLeadMinutes = 10

    private let defaultsKey = "pendingNotificationSlots"
    private let scheduledDayKey = "notificationSlotsScheduledForDay"
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func registerCategories() {
        let glass = UNNotificationAction(identifier: Constants.NotificationAction.glass, title: Constants.IntakePreset.glass.label, options: [])
        let bottle = UNNotificationAction(identifier: Constants.NotificationAction.bottle, title: Constants.IntakePreset.bottle.label, options: [])
        let gallon = UNNotificationAction(identifier: Constants.NotificationAction.gallon, title: Constants.IntakePreset.gallon.label, options: [])
        let snooze = UNNotificationAction(identifier: Constants.NotificationAction.snooze, title: "Lembrar mais tarde", options: [])

        let category = UNNotificationCategory(
            identifier: Constants.NotificationCategory.hydrationReminder,
            actions: [glass, bottle, gallon, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Generates today's semi-random reminder times the first time this is called on a
    /// given day, then schedules a system notification for each one. Safe to call
    /// repeatedly — no-ops once today's slots already exist.
    func ensureTodayScheduled() {
        // No point scheduling reminders (or capturing context for them) before
        // onboarding has created a profile — there's no goal/timezone to reason about
        // yet, and `captureContext` would silently no-op without one.
        guard (try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()))?.first != nil else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let last = UserDefaults.standard.object(forKey: scheduledDayKey) as? Date,
           calendar.isDate(last, inSameDayAs: today) {
            return
        }

        let windowStart = calendar.date(bySettingHour: Constants.dailyWindowStartHour, minute: 0, second: 0, of: today) ?? today
        let windowEnd = calendar.date(bySettingHour: Constants.dailyWindowEndHour, minute: 0, second: 0, of: today) ?? today
        let earliestAllowed = max(windowStart, .now)
        guard earliestAllowed < windowEnd else {
            UserDefaults.standard.set(today, forKey: scheduledDayKey)
            return
        }

        let slotCount = Constants.notificationsPerDay
        let totalSeconds = windowEnd.timeIntervalSince(earliestAllowed)
        let strataLength = totalSeconds / Double(slotCount)

        var slots: [PendingSlot] = []
        for i in 0..<slotCount {
            let strataStart = earliestAllowed.addingTimeInterval(strataLength * Double(i))
            let offset = Double.random(in: 0..<strataLength)
            let firesAt = strataStart.addingTimeInterval(offset)
            slots.append(PendingSlot(id: UUID(), firesAt: firesAt, captured: false))
            scheduleSystemNotification(id: slots[i].id, firesAt: firesAt)
        }

        savePendingSlots(slots)
        UserDefaults.standard.set(today, forKey: scheduledDayKey)
    }

    /// Called periodically while the app is foregrounded: captures context for any
    /// imminent slot, resolves any `NotificationEvent` that's timed out unanswered,
    /// and keeps the weather cache warm so a quick-log tap always has something
    /// recent to attach (see `WeatherContextService.cachedContext`).
    func tick(context: ModelContext) async {
        await WeatherContextService.shared.refreshCacheIfStale()
        await captureImminentSlots(context: context)
        await resolveTimedOutEvents(context: context)
    }

    /// Same as `tick(context:)`, but resolves the shared `ModelContext` itself —
    /// lets callers outside MainActor isolation (like the BGAppRefreshTask handler)
    /// invoke a tick without ever handling a non-Sendable `ModelContext` themselves.
    func tick() async {
        await tick(context: PersistenceController.context)
    }

    // MARK: - Context capture

    private func captureImminentSlots(context: ModelContext) async {
        var slots = loadPendingSlots()
        guard !slots.isEmpty else { return }

        let now = Date.now
        for index in slots.indices where !slots[index].captured {
            let minutesUntilFire = slots[index].firesAt.timeIntervalSince(now) / 60
            guard minutesUntilFire <= Double(Self.captureLeadMinutes) else { continue }
            await captureContext(id: slots[index].id, firesAt: slots[index].firesAt, context: context)
            slots[index].captured = true
        }
        savePendingSlots(slots)
    }

    /// Gathers weather/calendar/deficit context and creates the `NotificationEvent`
    /// for one slot. Public so `NotificationDelegate` can call it as a fallback when a
    /// tester interacts with a notification whose event was never pre-captured.
    func captureContext(id: UUID, firesAt: Date, context: ModelContext) async {
        guard fetchNotificationEvent(id: id, context: context) == nil else { return }
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }

        let weather = await WeatherContextService.shared.currentContext()
        let calendarContext = CalendarContextService.shared.currentContext(around: firesAt)

        let targetUserID = profile.userID
        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: firesAt)
        let deficit = HydrationMath.deficitML(metaDiariaML: profile.metaDiariaML, consumidoHojeML: consumidoHoje)
        let minutesSinceLast = HydrationMath.minutesSinceLastIntake(logs, now: firesAt)

        let event = NotificationEvent(
            id: id,
            userID: profile.userID,
            sentAt: firesAt,
            temperaturaC: weather?.temperaturaC ?? 0,
            umidadeRelativa: weather?.umidadeRelativa ?? 0,
            sensacaoTermicaC: weather?.sensacaoTermicaC ?? 0,
            ocupadoNoMomento: calendarContext?.ocupadoNoMomento ?? false,
            densidadeEventosDia: calendarContext?.densidadeEventosDia ?? 0,
            deficitAcumuladoML: deficit,
            tempoDesdeUltimoRegistroMin: minutesSinceLast
        )
        context.insert(event)
        try? context.save()
        await CloudKitSyncService.shared.push(event)
        try? context.save()
    }

    // MARK: - Interaction resolution

    func resolveInteraction(eventID: UUID, status: StatusInteracao, context: ModelContext) async {
        guard let event = fetchNotificationEvent(id: eventID, context: context) else { return }
        guard event.statusInteracao == nil else { return } // already resolved once
        event.statusInteracao = status.rawValue
        event.tempoAteAgirMin = max(0, Int(Date.now.timeIntervalSince(event.sentAt) / 60))
        try? context.save()
        await CloudKitSyncService.shared.push(event)
        try? context.save()
    }

    /// Quick-action taps (Copo/Garrafa/Galão) both log the intake and resolve the
    /// notification's outcome in one step, so `tempoAteAgirMin` reflects the near-zero
    /// gap between the reminder firing and the tester tapping it.
    func recordQuickAction(eventID: UUID, preset: Constants.IntakePreset, context: ModelContext) async {
        guard let event = fetchNotificationEvent(id: eventID, context: context) else { return }
        let log = IntakeLog(userID: event.userID, preset: preset, origem: .notificacao, notificationEventID: eventID.uuidString, weather: WeatherContextService.shared.cachedContext)
        context.insert(log)

        if event.statusInteracao == nil {
            event.statusInteracao = StatusInteracao.aberta.rawValue
            event.tempoAteAgirMin = max(0, Int(Date.now.timeIntervalSince(event.sentAt) / 60))
        }
        event.resultouEmConsumo = true
        try? context.save()

        await CloudKitSyncService.shared.push(log)
        await CloudKitSyncService.shared.push(event)
        try? context.save()
    }

    /// Records a tap on one of the main screen's always-visible intake buttons. Per
    /// the spec, `origem` is inferred automatically: if a `NotificationEvent` for this
    /// user fired within the last `notificationResponseWindowMinutes`, this intake
    /// counts as `"notificacao"` (even though the tester used the app, not a
    /// notification action) — this is what lets a future model tell "the notification
    /// caused this drink" apart from "the user would have drunk water anyway."
    func recordManualIntake(preset: Constants.IntakePreset, userID: String, context: ModelContext) async {
        let cutoff = Date.now.addingTimeInterval(-Double(Constants.notificationResponseWindowMinutes) * 60)
        let predicate = #Predicate<NotificationEvent> { $0.userID == userID && $0.sentAt >= cutoff }
        let recentEvents = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.sorted { $0.sentAt > $1.sentAt } ?? []
        let matchedEvent = recentEvents.first

        let log = IntakeLog(
            userID: userID,
            preset: preset,
            origem: matchedEvent == nil ? .manual : .notificacao,
            notificationEventID: matchedEvent?.id.uuidString,
            weather: WeatherContextService.shared.cachedContext
        )
        context.insert(log)

        if let matchedEvent {
            matchedEvent.resultouEmConsumo = true
            if matchedEvent.tempoAteAgirMin == nil {
                matchedEvent.tempoAteAgirMin = max(0, Int(Date.now.timeIntervalSince(matchedEvent.sentAt) / 60))
            }
        }
        try? context.save()

        await CloudKitSyncService.shared.push(log)
        if let matchedEvent {
            await CloudKitSyncService.shared.push(matchedEvent)
        }
        try? context.save()
    }

    /// Removes an `IntakeLog` the tester logged by mistake. If it was linked to a
    /// `NotificationEvent`, re-checks whether any *other* intake still supports
    /// `resultouEmConsumo` — deleting the one log that caused it shouldn't leave a
    /// notification looking like it worked when the evidence for that was retracted.
    /// `statusInteracao`/`tempoAteAgirMin` are left alone: those describe how the
    /// tester interacted with the notification itself, not whether they drank water,
    /// so a mistaken intake entry doesn't invalidate them.
    func deleteIntake(_ log: IntakeLog, context: ModelContext) async {
        let logID = log.id
        let notificationEventID = log.notificationEventID
        context.delete(log)
        try? context.save()

        await CloudKitSyncService.shared.delete(recordType: "IntakeLog", id: logID)

        guard let notificationEventID, let eventID = UUID(uuidString: notificationEventID),
              let event = fetchNotificationEvent(id: eventID, context: context),
              event.resultouEmConsumo else { return }

        let stillHasSupportingIntake = (try? context.fetch(
            FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.notificationEventID == notificationEventID })
        ))?.isEmpty == false

        if !stillHasSupportingIntake {
            event.resultouEmConsumo = false
            try? context.save()
            await CloudKitSyncService.shared.push(event)
            try? context.save()
        }
    }

    /// "Lembrar mais tarde": inserts one ad-hoc slot ~15 minutes out, outside the
    /// day's regular random schedule.
    func scheduleSnoozeSlot() {
        let firesAt = Date.now.addingTimeInterval(15 * 60)
        let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false)
        var slots = loadPendingSlots()
        slots.append(slot)
        savePendingSlots(slots)
        scheduleSystemNotification(id: slot.id, firesAt: firesAt)
    }

    private func resolveTimedOutEvents(context: ModelContext) async {
        let cutoff = Date.now.addingTimeInterval(-Double(Constants.notificationResponseWindowMinutes) * 60)
        let predicate = #Predicate<NotificationEvent> { $0.statusInteracao == nil && $0.sentAt <= cutoff }
        guard let stale = try? context.fetch(FetchDescriptor(predicate: predicate)) else { return }
        for event in stale {
            event.statusInteracao = StatusInteracao.ignorada.rawValue
            await CloudKitSyncService.shared.push(event)
        }
        if !stale.isEmpty {
            try? context.save()
        }
    }

    private func fetchNotificationEvent(id: UUID, context: ModelContext) -> NotificationEvent? {
        let predicate = #Predicate<NotificationEvent> { $0.id == id }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    // MARK: - System notification + local bookkeeping

    private func scheduleSystemNotification(id: UUID, firesAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Hora de beber água 💧"
        content.body = "Um gole agora ajuda a manter sua meta do dia."
        content.categoryIdentifier = Constants.NotificationCategory.hydrationReminder
        content.userInfo = ["eventID": id.uuidString]
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: firesAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
        center.add(request)
    }

    private func loadPendingSlots() -> [PendingSlot] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingSlot].self, from: data)) ?? []
    }

    private func savePendingSlots(_ slots: [PendingSlot]) {
        // Drop slots more than a day stale so this list can't grow unbounded.
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        let trimmed = slots.filter { $0.firesAt > cutoff }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
