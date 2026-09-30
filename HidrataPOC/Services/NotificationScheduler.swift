import Foundation
import Intents
import SwiftData
import UIKit
import UserNotifications

/// A slot the app has committed to firing a local notification at, but hasn't yet
/// captured weather/calendar/deficit context for. Local-only bookkeeping (UserDefaults
/// JSON) — deliberately not a synced record type, since it's scheduling plumbing, not
/// data for the model. `NotificationEvent` is the record that matters and only gets
/// created once context is captured.
struct PendingSlot: Codable, Equatable {
    let id: UUID
    let firesAt: Date
    var captured: Bool
    /// `NotificationVariant.rawValue` the system notification is currently armed with.
    /// Chosen when the slot is scheduled (not only at capture time), so the persona copy
    /// shows even if the app never got a chance to run in the capture window; kept so a
    /// slot that fires before capture records the variant that was actually shown.
    /// Optional only because slots persisted by older builds don't have it —
    /// `NotificationScheduler.migrateSlotsIfNeeded` backfills those.
    var variant: String? = nil
    /// Set when this slot's request was handed to the system. Only the next slot (plus
    /// the next 8h one) is armed (see `NotificationScheduler.armNextSlotIfClear`), so a slot whose
    /// time passes without this set was never sent and gets no `NotificationEvent`.
    var armedAt: Date? = nil
}

/// A swipe-dismiss recorded by `NotificationScheduler.recordDismissal`, waiting to be
/// resolved on the next tick.
private struct PendingDismissal: Codable {
    let eventID: UUID
    let sentAt: Date
    let dismissedAt: Date
}

/// A hydration reminder currently sitting in Notification Center, as the plain data
/// `NotificationScheduler.decideSlotAction` needs (so tests don't need a `UNNotification`).
struct DeliveredReminder: Equatable {
    let id: String
    let date: Date
}

/// What a tick should do with one uncaptured slot — see
/// `NotificationScheduler.decideSlotAction`.
enum SlotAction: Equatable {
    /// Not armed, or not inside the capture window yet.
    case wait
    /// Armed and about to fire: capture context and re-arm it in place (same id, same
    /// `firesAt`) with the refined variant.
    case capture
    /// Its time has passed and it was armed (so it was shown): record the event with
    /// the variant it was armed with. Never re-armed or re-delivered.
    case recordFired
    /// Its time has passed without it ever being armed — held back by an unanswered
    /// reminder — so nothing was shown: mark it done without a `NotificationEvent`.
    case dropUnsent
}

/// Drives the whole "notification with context" pipeline described in the spec:
/// schedules the fixed-hour reminders, captures context shortly before
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
///
/// Delivery rule: while a hydration reminder sits unanswered in Notification Center,
/// no other reminder may be delivered — except the next morning's first one (8h),
/// which always goes out; unanswered reminders from the night before are deleted.
/// iOS delivers every queued local notification whether or not the app runs, so the
/// only way to guarantee that is to keep just the next slot (plus the next 8h one)
/// queued with the system, and to queue the one after only once the current one has
/// been interacted with (`NotificationDelegate` → `armNextSlotIfClear`).
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// How far ahead of a slot's fire time we start trying to capture context, so
    /// there's headroom for the WeatherKit/EventKit network round trip to finish.
    nonisolated private static let captureLeadMinutes = 10

    private let defaultsKey = "pendingNotificationSlots"
    /// Legacy: older builds scheduled once per day behind this key. Slot creation is
    /// now idempotent per fixed hour, so it's only cleared during migration.
    private let legacyScheduledDayKey = "notificationSlotsScheduledForDay"
    /// Bumped whenever a build changes how requests are armed in a way that makes
    /// requests queued by an older build wrong (old copy, pushed-back times). On a
    /// mismatch, every pending hydration request is removed and today is re-scheduled.
    private let schedulingSchemaVersionKey = "notificationSchedulingSchemaVersion"
    private static let schedulingSchemaVersion = 3
    /// Dismissals recorded by `NotificationDelegate` without touching SwiftData (see
    /// `recordDismissal`), resolved on the next tick.
    nonisolated private static let pendingDismissalsKey = "pendingNotificationDismissals"
    private let adjustmentValueKey = "lastTemperatureAdjustmentML"
    private let adjustmentDayKey = "lastTemperatureAdjustmentDay"
    private let renderedMascotKey = "pendingNotificationsRenderedMascot"
    /// Last mascot asset computed from real progress, with its day — lets
    /// `armNextSlotIfClear` pick an avatar without SwiftData or WeatherKit, since it
    /// also runs from the background dismiss path.
    private let lastMascotImageNameKey = "lastNotificationMascotImageName"
    private let lastMascotDayKey = "lastNotificationMascotDay"
    /// Slots exist for today and the following days up to this count, so the next
    /// reminder can be armed from a notification interaction (e.g. a 22h dismiss arms
    /// tomorrow's 8h) without the app having to run first.
    private static let scheduleDaysAhead = 2
    private let center = UNUserNotificationCenter.current()

    /// Deduplicates concurrent `ensureTodayScheduled()` calls (e.g. the launch `.task`
    /// and the scenePhase-`.active` handler firing within moments of each other) so a
    /// second caller awaits the first's in-flight work instead of racing it — without
    /// this, both would see the same hours as missing before either had saved its new
    /// slots, doubling every fixed-hour slot with distinct UUIDs.
    private var inflightEnsureTodayScheduledTask: Task<Void, Never>?

    /// Bumped every time a request id is added or removed. `scheduleSystemNotification`
    /// awaits (the intent donation) before calling `center.add`, so without this a
    /// slower, older write — e.g. `refreshPendingMascotIfNeeded` re-adding a request it
    /// read before a cancel — could land after a newer one and resurrect or re-time it.
    private var requestGenerations: [String: Int] = [:]

    private init() {}

    func registerCategories() {
        let glass = UNNotificationAction(identifier: Constants.NotificationAction.glass, title: Constants.IntakePreset.glass.label, options: [])
        let bottle = UNNotificationAction(identifier: Constants.NotificationAction.bottle, title: Constants.IntakePreset.bottle.label, options: [])
        let gole = UNNotificationAction(identifier: Constants.NotificationAction.gole, title: Constants.IntakePreset.gole.label, options: [])
        let snooze = UNNotificationAction(identifier: Constants.NotificationAction.snooze, title: "Lembrar mais tarde", options: [])

        let category = UNNotificationCategory(
            identifier: Constants.NotificationCategory.hydrationReminder,
            actions: [glass, bottle, gole, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Creates a slot for each fixed reminder time (`Constants.notificationFixedHours`)
    /// from now through the next `scheduleDaysAhead` days that doesn't already have one,
    /// then arms the next slot if nothing is waiting on the tester. Idempotent per fixed
    /// hour, so it's safe to call on every launch/foreground. Safe to call concurrently
    /// too — overlapping callers all await the same in-flight work (see
    /// `inflightEnsureTodayScheduledTask`).
    func ensureTodayScheduled() async {
        if let inflightEnsureTodayScheduledTask {
            await inflightEnsureTodayScheduledTask.value
            return
        }
        let task = Task { await self.performEnsureTodayScheduled() }
        inflightEnsureTodayScheduledTask = task
        await task.value
        inflightEnsureTodayScheduledTask = nil
    }

    private func performEnsureTodayScheduled() async {
        // No point scheduling reminders (or capturing context for them) before
        // onboarding has created a profile — there's no goal/timezone to reason about
        // yet, and `captureContext` would silently no-op without one.
        guard let profile = (try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }

        let targetUserID = profile.userID
        let logs = (try? PersistenceController.context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []

        await migrateSlotsIfNeeded(profile: profile, logs: logs)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let existing = Set(loadPendingSlots().map(\.firesAt))
        let firesAtTimes = (0..<Self.scheduleDaysAhead)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .flatMap { day in
                Constants.notificationFixedHours.compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
            }
            .filter { $0 > .now && !existing.contains($0) }

        if !firesAtTimes.isEmpty {
            // Every slot gets its persona copy up front, so whichever one gets armed —
            // possibly from a background notification response — already has it. The
            // capture pass a few minutes before firing only refines it. Weather is
            // unknown for later days, which leaves those to the time-of-day rules.
            let weather = await WeatherContextService.shared.currentContext()
            let newSlots = firesAtTimes.map { firesAt in
                let dayWeather = calendar.isDate(firesAt, inSameDayAs: today) ? weather : nil
                let variant = Self.selectVariant(firesAt: firesAt, weather: dayWeather, profile: profile, logs: logs)
                return PendingSlot(id: UUID(), firesAt: firesAt, captured: false, variant: variant.rawValue)
            }
            // Re-read before saving: a tick or snooze may have written the list during
            // the await above, and saving the stale copy would drop its changes.
            var slots = loadPendingSlots()
            slots.append(contentsOf: newSlots)
            savePendingSlots(slots)
        }

        await armNextSlotIfClear()
    }

    private func isAuthorizedForNotifications() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// One-time cleanup for state left behind by older builds:
    /// - On a scheduling-schema change, removes every pending hydration request (older
    ///   builds queued every slot at once, some with generic copy and pushed-back
    ///   times) and drops the uncaptured future slots they belonged to, so the caller
    ///   re-creates them. Past uncaptured slots are marked armed, since older builds
    ///   armed every slot — they were shown and still need recording.
    /// - Backfills slots whose `variant` is missing or unreadable, so nothing downstream
    ///   ever has to fall back to the generic copy for a tester who has a profile.
    private func migrateSlotsIfNeeded(profile: UserProfile, logs: [IntakeLog]) async {
        let defaults = UserDefaults.standard
        var slots = loadPendingSlots()
        var didChange = false

        if defaults.integer(forKey: schedulingSchemaVersionKey) != Self.schedulingSchemaVersion {
            let pending = await center.pendingNotificationRequests()
            let staleIDs = pending
                .filter { $0.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder }
                .map(\.identifier)
            removePendingRequests(withIdentifiers: staleIDs)
            // Re-read: the await above may have let a tick write the list.
            let now = Date.now
            slots = loadPendingSlots()
            slots.removeAll { !$0.captured && $0.firesAt > now }
            for index in slots.indices where !slots[index].captured && slots[index].armedAt == nil {
                slots[index].armedAt = slots[index].firesAt
            }
            defaults.removeObject(forKey: legacyScheduledDayKey)
            defaults.set(Self.schedulingSchemaVersion, forKey: schedulingSchemaVersionKey)
            didChange = true
        }

        let weather = WeatherContextService.shared.cachedContext
        for index in slots.indices where slots[index].variant.flatMap(NotificationVariant.init(rawValue:)) == nil {
            slots[index].variant = Self.selectVariant(firesAt: slots[index].firesAt, weather: weather, profile: profile, logs: logs).rawValue
            didChange = true
        }

        if didChange {
            savePendingSlots(slots)
        }
    }

    // MARK: - One reminder at a time

    /// Makes the system's queue match the delivery rule:
    /// - The next upcoming slot is queued only if no reminder from the current reminder
    ///   day (see `reminderDayStart`) sits unanswered in Notification Center.
    /// - The next first-of-day slot (8h) is always queued, so each morning starts fresh
    ///   even if the app never runs overnight to clear yesterday's unread reminder.
    /// - Unanswered reminders from a previous reminder day are deleted.
    /// Everything else is un-queued. Called on launch/foreground, every tick, and right
    /// after every notification interaction.
    ///
    /// Touches only UserDefaults and `UNUserNotificationCenter` — no SwiftData,
    /// location or WeatherKit — so it's safe from the background dismiss path.
    ///
    /// `answered`: the notification the tester just interacted with. It may not have
    /// left `deliveredNotifications()` yet when the response handler runs, so it's
    /// removed explicitly and never counts as unanswered.
    func armNextSlotIfClear(answered answeredID: String? = nil) async {
        let now = Date.now
        var delivered = await deliveredHydrationReminders().filter { $0.id != answeredID }
        let staleIDs = Self.staleReminderIDs(delivered, now: now)
        let removedIDs = staleIDs + [answeredID].compactMap { $0 }
        if !removedIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: removedIDs)
        }
        delivered.removeAll { staleIDs.contains($0.id) }

        let pendingIDs = await center.pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder }
            .map(\.identifier)
        let authorized = await isAuthorizedForNotifications()

        let slots = loadPendingSlots()
        // Without permission `center.add` fails silently, and the slot would be
        // recorded as sent; leave it unarmed so it's dropped instead.
        let toArm = authorized ? Self.slotsToArm(slots, now: now, delivered: delivered) : []
        let toArmIDs = Set(toArm.map(\.id.uuidString))

        removePendingRequests(withIdentifiers: pendingIDs.filter { !toArmIDs.contains($0) })
        for slot in slots where slot.armedAt != nil && slot.firesAt > now && !toArmIDs.contains(slot.id.uuidString) {
            updateSlot(id: slot.id) { $0.armedAt = nil }
        }

        for slot in toArm where !pendingIDs.contains(slot.id.uuidString) {
            let variant = slot.variant.flatMap(NotificationVariant.init(rawValue:)) ?? .fallbackGeneric
            updateSlot(id: slot.id) { $0.armedAt = now }
            await armSlot(id: slot.id, firesAt: slot.firesAt, variant: variant, sender: cachedMascotSender(title: variant.title, firesAt: slot.firesAt))
        }
    }

    /// The slots that should be queued with the system right now — pure, for tests.
    /// The earliest future slot, unless a reminder from the current reminder day is
    /// unanswered (then nothing until the tester acts on it); plus, always, the next
    /// first-of-day slot, so an unread reminder never silences the next morning.
    nonisolated static func slotsToArm(
        _ slots: [PendingSlot],
        now: Date,
        delivered: [DeliveredReminder],
        calendar: Calendar = .current
    ) -> [PendingSlot] {
        let upcoming = slots.filter { $0.firesAt > now }.sorted { $0.firesAt < $1.firesAt }
        let dayStart = reminderDayStart(containing: now, calendar: calendar)
        let hasUnanswered = delivered.contains { $0.date >= dayStart }

        var toArm: [PendingSlot] = []
        if !hasUnanswered, let next = upcoming.first {
            toArm.append(next)
        }
        if let morning = upcoming.first(where: { isFirstSlotOfDay($0.firesAt, calendar: calendar) }),
           !toArm.contains(morning) {
            toArm.append(morning)
        }
        return toArm
    }

    /// Unanswered reminders delivered before the current reminder day began — i.e.
    /// left over from the previous night — which get deleted so they stop blocking.
    nonisolated static func staleReminderIDs(_ delivered: [DeliveredReminder], now: Date, calendar: Calendar = .current) -> [String] {
        let dayStart = reminderDayStart(containing: now, calendar: calendar)
        return delivered.filter { $0.date < dayStart }.map(\.id)
    }

    /// A "reminder day" runs from the first fixed hour (8h) to the next day's first
    /// fixed hour, so everything from 22h through the night still belongs to the day
    /// before, and resets at 8h.
    nonisolated static func reminderDayStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let firstHour = Constants.notificationFixedHours.min() ?? 0
        let start = calendar.date(bySettingHour: firstHour, minute: 0, second: 0, of: date) ?? calendar.startOfDay(for: date)
        return date >= start ? start : calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    nonisolated static func isFirstSlotOfDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour == Constants.notificationFixedHours.min() && parts.minute == 0 && parts.second == 0
    }

    /// Called periodically while the app is foregrounded: keeps the delivery rule
    /// (see `armNextSlotIfClear`), captures context for an imminent slot, resolves any
    /// `NotificationEvent` that's timed out unanswered, and keeps the weather cache warm
    /// so a quick-log tap always has something recent to attach (see
    /// `WeatherContextService.cachedContext`).
    func tick(context: ModelContext) async {
        await WeatherContextService.shared.refreshCacheIfStale()
        // Also catches reminders cleared without a response callback (e.g. "Clear All"
        // in Notification Center), which unblocks the next one.
        await armNextSlotIfClear()
        await captureImminentSlots(context: context)
        // Before the timeout pass, so a dismissal keeps its real `tempoAteAgirMin`
        // instead of being swept up as a plain timeout.
        await resolvePendingDismissals(context: context)
        await resolveTimedOutEvents(context: context)
        await refreshPendingMascotIfNeeded()
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            await LiveActivityManager.shared.touchIfNeeded(profile: profile, context: context)
        }
    }

    /// Same as `tick(context:)`, but resolves the shared `ModelContext` itself —
    /// lets callers outside MainActor isolation (like the BGAppRefreshTask handler)
    /// invoke a tick without ever handling a non-Sendable `ModelContext` themselves.
    func tick() async {
        await tick(context: PersistenceController.context)
    }

    // MARK: - Context capture

    private func captureImminentSlots(context: ModelContext) async {
        let slots = loadPendingSlots().filter { !$0.captured }
        guard !slots.isEmpty else { return }

        let delivered = await deliveredHydrationReminders()
        let now = Date.now
        for slot in slots {
            switch Self.decideSlotAction(slot: slot, now: now, delivered: delivered) {
            case .wait:
                continue
            case .capture, .recordFired:
                let variant = await captureContext(id: slot.id, firesAt: slot.firesAt, context: context)
                updateSlot(id: slot.id) {
                    if let variant { $0.variant = variant.rawValue }
                    $0.captured = true
                }
            case .dropUnsent:
                updateSlot(id: slot.id) { $0.captured = true }
            }
        }
    }

    /// The per-slot decision behind `captureImminentSlots`, kept pure so it's testable.
    ///
    /// A slot whose time has passed is only ever *recorded*, never re-armed: iOS
    /// delivers queued requests on time whether or not the app runs, so re-arming one
    /// (as the old push-back did) re-sent reminders the tester had already received.
    /// Only the armed slot is captured ahead of time — an unarmed one may never be sent.
    nonisolated static func decideSlotAction(
        slot: PendingSlot,
        now: Date,
        delivered: [DeliveredReminder]
    ) -> SlotAction {
        guard !slot.captured else { return .wait }
        if slot.firesAt <= now {
            let wasShown = slot.armedAt != nil || delivered.contains { $0.id == slot.id.uuidString }
            return wasShown ? .recordFired : .dropUnsent
        }
        guard slot.armedAt != nil,
              slot.firesAt.timeIntervalSince(now) <= Double(captureLeadMinutes) * 60 else { return .wait }
        return .capture
    }

    private func deliveredHydrationReminders() async -> [DeliveredReminder] {
        await center.deliveredNotifications()
            .filter { $0.request.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder }
            .map { DeliveredReminder(id: $0.request.identifier, date: $0.date) }
    }

    /// Gathers weather/calendar/deficit context and creates the `NotificationEvent`
    /// for one slot. Public so `NotificationDelegate` can call it as a fallback when a
    /// tester interacts with a notification whose event was never pre-captured.
    ///
    /// A slot whose `firesAt` has passed is only recorded (with the variant it was
    /// armed with); only a still-pending one is re-armed, in place, with the re-pick.
    ///
    /// `preferCachedWeather` skips the location + WeatherKit round trip — for the
    /// notification-response path, which may run in a short background launch.
    ///
    /// Returns the variant recorded on the event (nil if nothing was captured), so the
    /// caller can keep the slot's bookkeeping in sync with what's armed.
    @discardableResult
    func captureContext(id: UUID, firesAt: Date, context: ModelContext, preferCachedWeather: Bool = false) async -> NotificationVariant? {
        guard fetchNotificationEvent(id: id, context: context) == nil else { return nil }
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return nil }

        let weather = preferCachedWeather
            ? WeatherContextService.shared.cachedContext
            : await WeatherContextService.shared.currentContext()
        let calendarContext = CalendarContextService.shared.currentContext(around: firesAt)

        let targetUserID = profile.userID
        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: firesAt)
        let deficit = HydrationMath.deficitML(metaDiariaML: profile.metaDiariaML, consumidoHojeML: consumidoHoje)
        let minutesSinceLast = HydrationMath.minutesSinceLastIntake(logs, now: firesAt)
        // The variant the slot is currently armed with (chosen at scheduling time).
        let armed = loadPendingSlots().first { $0.id == id }?.variant.flatMap(NotificationVariant.init(rawValue:))
        let alreadyFired = firesAt <= .now
        // If the reminder already fired on its own, the tester saw the armed copy, so
        // that's what the event must record; otherwise re-pick with fresh context, but
        // don't re-roll a random midday pick that's still valid.
        let variant: NotificationVariant
        if alreadyFired, let armed {
            variant = armed
        } else {
            variant = Self.selectVariant(firesAt: firesAt, weather: weather, profile: profile, logs: logs, keeping: armed)
        }

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
            tempoDesdeUltimoRegistroMin: minutesSinceLast,
            notificationVariant: variant
        )
        context.insert(event)
        try? context.save()
        await CloudKitSyncService.shared.push(event)
        try? context.save()

        // Reschedule with the chosen persona copy, in place, only if this is the armed
        // slot and it hasn't fired yet — if it already fired, the tester already saw the
        // armed copy and there's nothing left to swap. Never re-delivered, and never
        // arms a slot that isn't the armed one (that would break one-at-a-time).
        let isArmed = loadPendingSlots().first { $0.id == id }?.armedAt != nil
        if firesAt > .now, isArmed {
            let goalML = await effectiveGoalML(for: profile)
            let sender = mascotSender(title: variant.title, consumidoHojeML: consumidoHoje, goalML: goalML)
            await armSlot(id: id, firesAt: firesAt, variant: variant, sender: sender)
        }
        return variant
    }

    /// Picks which persona-flavored copy variant to show for a reminder firing at
    /// `firesAt` — see HYDRATE-NP-01 §7. Pure aside from `randomElement()`, so it's
    /// easy to unit test with fixed inputs. `static`/non-private so
    /// `NotificationSchedulerVariantSelectionTests` can call it without going through
    /// the whole scheduling pipeline.
    static func selectVariant(
        firesAt: Date,
        weather: WeatherContext?,
        profile: UserProfile,
        logs: [IntakeLog],
        calendar: Calendar = .current,
        keeping: NotificationVariant? = nil
    ) -> NotificationVariant {
        let hour = calendar.component(.hour, from: firesAt)
        let isEvening = hour >= Constants.notificationEveningStartHour
        let isMorning = hour < Constants.notificationMorningEndHour

        if isEvening, HydrationMath.isStreakAtRisk(logs, metaDiariaML: profile.metaDiariaML, calendar: calendar, firesAt: firesAt) {
            return .streakRiskEvening
        }
        if let temp = weather?.temperaturaC {
            if temp >= Constants.notificationHotThresholdC { return .hotDay }
            if temp <= Constants.notificationColdThresholdC { return .coldDay }
        }
        if isMorning { return .mildMorning }
        if isEvening { return .symptomIrritabilityEvening }
        // `keeping` lets a re-pick with fresher context avoid re-rolling a midday variant
        // the slot was already armed with.
        let midday: [NotificationVariant] = [.middayNeutral, .symptomHeadacheMidday, .symptomConcentrationMidday]
        if let keeping, midday.contains(keeping) { return keeping }
        return midday.randomElement()!
    }

    // MARK: - Interaction resolution

    func resolveInteraction(eventID: UUID, status: StatusInteracao, at actedAt: Date = .now, context: ModelContext) async {
        guard let event = fetchNotificationEvent(id: eventID, context: context) else { return }
        guard event.statusInteracao == nil else { return } // already resolved once
        event.statusInteracao = status.rawValue
        event.tempoAteAgirMin = max(0, Int(actedAt.timeIntervalSince(event.sentAt) / 60))
        try? context.save()
        await CloudKitSyncService.shared.push(event)
        try? context.save()
    }

    /// Records a swipe-dismiss without touching SwiftData, location, WeatherKit,
    /// EventKit or CloudKit. `.customDismissAction` wakes the app in the background —
    /// often from the lock screen — with very little time, and running the full
    /// capture path there is a crash risk (watchdog kill, or the store being
    /// unavailable while locked). Resolved on the next tick by `resolvePendingDismissals`.
    nonisolated static func recordDismissal(eventID: UUID, sentAt: Date, dismissedAt: Date = .now) {
        let defaults = UserDefaults.standard
        var pending = (defaults.data(forKey: pendingDismissalsKey))
            .flatMap { try? JSONDecoder().decode([PendingDismissal].self, from: $0) } ?? []
        pending.append(PendingDismissal(eventID: eventID, sentAt: sentAt, dismissedAt: dismissedAt))
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingDismissalsKey)
        }
    }

    private func resolvePendingDismissals(context: ModelContext) async {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.pendingDismissalsKey),
              let pending = try? JSONDecoder().decode([PendingDismissal].self, from: data),
              !pending.isEmpty else { return }
        // Cleared up front: anything recorded while the awaits below run is appended to
        // a fresh list and picked up next tick instead of being overwritten.
        defaults.removeObject(forKey: Self.pendingDismissalsKey)
        for dismissal in pending {
            await captureContext(id: dismissal.eventID, firesAt: dismissal.sentAt, context: context)
            await resolveInteraction(eventID: dismissal.eventID, status: .ignorada, at: dismissal.dismissedAt, context: context)
        }
    }

    /// Quick-action taps (Gole/Copo/Garrafa) both log the intake and resolve the
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

        await IntakeLogService.endLiveActivity()
        await HealthKitService.shared.save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
        await refreshPendingMascotIfNeeded()
    }

    /// Records a tap on one of the main screen's always-visible intake buttons. Per
    /// the spec, `origem` is inferred automatically: if a `NotificationEvent` for this
    /// user fired within the last `notificationResponseWindowMinutes`, this intake
    /// counts as `"notificacao"` (even though the tester used the app, not a
    /// notification action) — this is what lets a future model tell "the notification
    /// caused this drink" apart from "the user would have drunk water anyway."
    func recordManualIntake(preset: Constants.IntakePreset, userID: String, context: ModelContext) async {
        // Called from the Home screen's always-visible buttons, i.e. while the app is
        // already running in the foreground — there's no widget-extension cold-start
        // race to ride out here, so skip `endLiveActivity`'s retry wait, and defer the
        // CloudKit sync inside `record` to the background (otherwise every tap pays
        // up to 1s of artificial delay plus a full network round trip on the common
        // case of no Live Activity running).
        await IntakeLogService.record(
            preset: preset,
            userID: userID,
            source: "app",
            weather: WeatherContextService.shared.cachedContext,
            context: context,
            waitForColdStartActivity: false,
            deferCloudSync: true
        )
        // `record()` already wrote this to HealthKit synchronously via
        // `IntakeLogService.onIntakeRecorded` — saving it again here would double-count
        // the intake in Health. The pending-reminders mascot refresh doesn't affect
        // anything the Home screen shows (SwiftData's @Query already reflects the new
        // log), so it's the only thing left to run in the background here.
        Task {
            await refreshPendingMascotIfNeeded()
        }
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

        await HealthKitService.shared.delete(logID: logID)
        await CloudKitSyncService.shared.delete(recordType: "IntakeLog", id: logID)
        await refreshPendingMascotIfNeeded()

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
    /// day's fixed-hour schedule.
    /// Only adds the slot: `NotificationDelegate` then calls `armNextSlotIfClear`, which
    /// arms it as the next upcoming slot.
    func scheduleSnoozeSlot() async {
        let firesAt = Date.now.addingTimeInterval(15 * 60)
        let variant = provisionalVariant(firesAt: firesAt)
        let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false, variant: variant.rawValue)
        var slots = loadPendingSlots()
        slots.append(slot)
        savePendingSlots(slots)
    }

    /// Persona variant for an ad-hoc slot (snooze), from whatever profile/intake/weather
    /// data is on hand right now. Falls back to the generic copy without a profile.
    /// Uses cached weather: this runs from a notification response, possibly in a short
    /// background launch.
    private func provisionalVariant(firesAt: Date) -> NotificationVariant {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return .fallbackGeneric }
        let targetUserID = profile.userID
        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let weather = WeatherContextService.shared.cachedContext
        return Self.selectVariant(firesAt: firesAt, weather: weather, profile: profile, logs: logs)
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

    /// The device owner, as the intent's `recipients` entry — `isMe: true` is what
    /// lets the system recognize this as an *incoming* message addressed to the
    /// tester rather than an outgoing one, which in practice turned out to matter for
    /// whether the avatar treatment actually renders (found via community reports;
    /// not spelled out in Apple's own docs).
    private static let selfPerson = INPerson(
        personHandle: INPersonHandle(value: "hidratapoc.owner", type: .unknown),
        nameComponents: nil,
        displayName: nil,
        image: nil,
        contactIdentifier: nil,
        customIdentifier: nil,
        isMe: true,
        suggestionType: .none
    )

    /// Arms a real reminder slot. The one place a slot's variant turns into a request,
    /// so it's also where a generic-copy regression would show up.
    /// Slots are only ever created once a profile exists, so the generic copy here is
    /// always a regression (no SwiftData lookup: this also runs from the dismiss path).
    private func armSlot(id: UUID, firesAt: Date, variant: NotificationVariant, sender: MascotSender?) async {
        if variant == .fallbackGeneric {
            print("⚠️ NotificationScheduler: arming fallback_generic for \(id) — a persona variant should have been chosen")
        }
        await scheduleSystemNotification(id: id, firesAt: firesAt, title: variant.title, body: variant.body, sender: sender)
    }

    /// The only path that cancels pending requests, so it can invalidate any
    /// in-flight `scheduleSystemNotification` for the same id (see `requestGenerations`).
    private func removePendingRequests(withIdentifiers ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            requestGenerations[id, default: 0] += 1
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// `expectedGeneration`: only write if nothing has added or removed this id since
    /// the caller read it (used by `refreshPendingMascotIfNeeded`).
    private func scheduleSystemNotification(id: UUID, firesAt: Date, title: String, body: String, sender: MascotSender? = nil, isDebug: Bool = false, expectedGeneration: Int? = nil) async {
        let key = id.uuidString
        if let expectedGeneration, requestGenerations[key, default: 0] != expectedGeneration { return }
        requestGenerations[key, default: 0] += 1
        let generation = requestGenerations[key, default: 0]

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Debug notifications carry no category/eventID, so tapping one can never
        // create a NotificationEvent or log an intake in the real dataset.
        if !isDebug {
            content.categoryIdentifier = Constants.NotificationCategory.hydrationReminder
            content.userInfo = ["eventID": id.uuidString]
        }
        // gulun.caf: the .m4a (AAC) source isn't a format local notifications can play
        // as a custom sound, so it's bundled converted to Linear PCM .caf. Must stay
        // under 30s, or iOS falls back to the default sound.
        content.sound = UNNotificationSound(named: UNNotificationSoundName("gulun.caf"))

        // Communication Notifications (requires the entitlement in
        // HidrataPOC.entitlements): donating an `INSendMessageIntent` whose sender
        // carries the mascot's photo makes the system render that photo as the leading
        // avatar — with the app's own icon as a small badge next to it, à la
        // Messages/WhatsApp — instead of the plain app icon. Falls back to the
        // undecorated content if building the intent fails for any reason.
        var finalContent: UNNotificationContent = content
        if let sender {
            let intent = INSendMessageIntent(
                recipients: [Self.selfPerson],
                outgoingMessageType: .outgoingMessageText,
                content: body,
                speakableGroupName: nil,
                conversationIdentifier: id.uuidString,
                serviceName: nil,
                sender: sender.person,
                attachments: nil
            )
            // Redundant with passing `image:` into the INPerson above, but community
            // reports (see the chat-notification StackOverflow thread this mirrors)
            // found the avatar silently fails to render without also setting it
            // explicitly on the intent's `sender` parameter this way.
            intent.setImage(sender.image, forParameterNamed: \.sender)

            // Per Apple's docs for `updating(from:)`: the system only renders the
            // sender's photo as the leading avatar once it has "learned" that person
            // via a donated interaction — and that donation must complete *before*
            // `updating(from:)` runs, or the content gets built too early and silently
            // keeps showing the plain app icon.
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            await donate(interaction)

            do {
                finalContent = try content.updating(from: intent)
                print("✅ NotificationScheduler: built communication notification content for sender \(sender.person.displayName ?? "?")")
            } catch {
                print("⚠️ NotificationScheduler: failed to build communication notification content: \(error)")
            }
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: firesAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: key, content: finalContent, trigger: trigger)
        // A newer add or a cancel for this id happened during the donation await —
        // it wins; adding this stale request now would undo it.
        guard requestGenerations[key, default: 0] == generation else { return }
        center.add(request) { error in
            if let error {
                print("⚠️ NotificationScheduler: failed to schedule notification: \(error)")
            }
        }
    }

    /// Donates an `INInteraction` and suspends until the system confirms it's been
    /// recorded — `donate(completion:)` is itself async/callback-based, and Apple's
    /// docs call for the donation to finish before `updating(from:)` builds the
    /// notification content around the same intent.
    private func donate(_ interaction: INInteraction) async {
        await withCheckedContinuation { continuation in
            interaction.donate { error in
                if let error {
                    print("⚠️ NotificationScheduler: failed to donate mascot sender interaction: \(error)")
                }
                continuation.resume()
            }
        }
    }

    /// Pairs the mascot `INPerson` with the raw `INImage`, since the image needs to be
    /// set twice — once inside the `INPerson` and once again via
    /// `INSendMessageIntent.setImage(_:forParameterNamed:)` — see
    /// `scheduleSystemNotification`.
    private struct MascotSender {
        let person: INPerson
        let image: INImage
    }

    /// Builds the `INPerson` "sender" behind the mascot avatar treatment — its photo
    /// is whichever mascot asset matches today's hydration progress against the same
    /// goal Home shows (base goal + temperature adjustment, see `effectiveGoalML`), via
    /// the same `AppTheme.mascotImageName`. `title` (the persona
    /// copy's own title, e.g. "Vai desidratar nesse calor?") doubles as the "contact
    /// name" the system shows in bold, since these notifications already read as the
    /// mascot needling the tester. Returns nil (silently) on any image-loading
    /// failure, since falling back to a plain notification is better than not firing.
    ///
    /// The person's handle/`customIdentifier` embed the asset name on purpose: the
    /// system caches a sender's avatar per person identity, so a single fixed
    /// identifier would keep showing whichever mascot it saw first.
    private func mascotSender(title: String, consumidoHojeML: Int, goalML: Int) -> MascotSender? {
        mascotSender(title: title, imageName: Self.currentMascotImageName(consumidoHojeML: consumidoHojeML, goalML: goalML))
    }

    private func mascotSender(title: String, imageName: String) -> MascotSender? {
        guard let image = UIImage(named: imageName), let data = image.pngData() else { return nil }

        let identity = "hidratapoc.mascot.\(imageName)"
        let avatar = INImage(imageData: data)
        let person = INPerson(
            personHandle: INPersonHandle(value: identity, type: .unknown),
            nameComponents: nil,
            displayName: title,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: identity,
            isMe: false,
            suggestionType: .none
        )
        return MascotSender(person: person, image: avatar)
    }

    private static func currentMascotImageName(consumidoHojeML: Int, goalML: Int) -> String {
        let progress = goalML > 0 ? min(1, Double(consumidoHojeML) / Double(goalML)) : 0
        return AppTheme.mascotImageName(for: progress)
    }

    /// Mascot for a reminder firing at `firesAt` without SwiftData or WeatherKit: the
    /// last asset `refreshPendingMascotIfNeeded` computed if that was for the same day,
    /// otherwise the zero-progress one (a later day starts from nothing). A tick
    /// re-renders it with live progress whenever the app next runs.
    private func cachedMascotSender(title: String, firesAt: Date) -> MascotSender? {
        let defaults = UserDefaults.standard
        let imageName: String
        if let day = defaults.object(forKey: lastMascotDayKey) as? Date,
           Calendar.current.isDate(day, inSameDayAs: firesAt),
           let name = defaults.string(forKey: lastMascotImageNameKey) {
            imageName = name
        } else {
            imageName = AppTheme.mascotImageName(for: 0)
        }
        return mascotSender(title: title, imageName: imageName)
    }

    private func currentHydrationState() async -> (consumidoHojeML: Int, goalML: Int)? {
        guard let profile = (try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()))?.first else { return nil }
        let targetUserID = profile.userID
        let logs = (try? PersistenceController.context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: .now)
        return (consumidoHoje, await effectiveGoalML(for: profile))
    }

    /// Home's goal is the base goal plus today's temperature adjustment; the
    /// notification's mascot has to be picked against that same number or it lands in a
    /// different progress bucket than the one on screen. The forecast needs
    /// location/network, so the last adjustment fetched today is kept as a fallback for
    /// background paths where that lookup fails.
    private func effectiveGoalML(for profile: UserProfile) async -> Int {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: .now)
        if let fresh = await WeatherContextService.shared.temperatureAdjustmentContext()?.adjustmentML {
            defaults.set(fresh, forKey: adjustmentValueKey)
            defaults.set(today, forKey: adjustmentDayKey)
            return profile.metaDiariaML + fresh
        }
        if let day = defaults.object(forKey: adjustmentDayKey) as? Date, Calendar.current.isDate(day, inSameDayAs: today) {
            return profile.metaDiariaML + defaults.integer(forKey: adjustmentValueKey)
        }
        return profile.metaDiariaML
    }

    // MARK: - Debug

    /// Fires a throwaway notification a few seconds from now, built exactly like a real
    /// reminder (same mascot selection + communication-notification path), with the
    /// expected mascot asset and progress spelled out in the body so the avatar the
    /// system renders can be checked against it. Returns that description, or nil if
    /// there's no profile yet.
    @discardableResult
    func sendDebugNotification(after seconds: TimeInterval = 5) async -> String? {
        guard let state = await currentHydrationState() else { return nil }
        let imageName = Self.currentMascotImageName(consumidoHojeML: state.consumidoHojeML, goalML: state.goalML)
        let percent = state.goalML > 0 ? Int(min(1, Double(state.consumidoHojeML) / Double(state.goalML)) * 100) : 0
        let description = "\(imageName) · \(state.consumidoHojeML)/\(state.goalML) mL (\(percent)%)"

        let title = "Teste de notificação"
        let body = "Mascote esperado: \(description)"
        let sender = mascotSender(title: title, consumidoHojeML: state.consumidoHojeML, goalML: state.goalML)
        await scheduleSystemNotification(id: UUID(), firesAt: .now.addingTimeInterval(seconds), title: title, body: body, sender: sender, isDebug: true)
        return description
    }

    // MARK: - Keeping pending reminders' mascot current

    /// Reminders are scheduled ahead of time, so the mascot baked into each one
    /// reflects progress at scheduling time — not when it fires. Re-renders the pending
    /// reminders' content whenever today's mascot has changed since the last render
    /// (after logging/deleting an intake, or from `tick`). Title, body, trigger and
    /// identifier are preserved.
    func refreshPendingMascotIfNeeded() async {
        guard let state = await currentHydrationState() else { return }
        let imageName = Self.currentMascotImageName(consumidoHojeML: state.consumidoHojeML, goalML: state.goalML)
        let day = Calendar.current.startOfDay(for: .now)
        UserDefaults.standard.set(imageName, forKey: lastMascotImageNameKey)
        UserDefaults.standard.set(day, forKey: lastMascotDayKey)
        let stamp = "\(day.timeIntervalSince1970)|\(imageName)"
        guard UserDefaults.standard.string(forKey: renderedMascotKey) != stamp else { return }

        let pending = await center.pendingNotificationRequests()
        // Snapshot right after the read: any add/cancel from here on (e.g. a response
        // un-arming this request while this loop awaits) makes the re-add below a
        // no-op instead of resurrecting or re-timing that request.
        let generations = requestGenerations
        for request in pending where request.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder {
            guard let id = UUID(uuidString: request.identifier),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let firesAt = trigger.nextTriggerDate(),
                  firesAt > .now else { continue }
            // A reminder armed for a later day (e.g. tomorrow 8h) starts from zero progress.
            let isToday = Calendar.current.isDate(firesAt, inSameDayAs: day)
            let sender = mascotSender(title: request.content.title, consumidoHojeML: isToday ? state.consumidoHojeML : 0, goalML: state.goalML)
            await scheduleSystemNotification(
                id: id,
                firesAt: firesAt,
                title: request.content.title,
                body: request.content.body,
                sender: sender,
                expectedGeneration: generations[request.identifier, default: 0]
            )
        }
        UserDefaults.standard.set(stamp, forKey: renderedMascotKey)
    }

    /// Mutates one slot against a fresh read of the list, so concurrent writers
    /// (ensure/tick/snooze interleave at their awaits) don't clobber each other.
    private func updateSlot(id: UUID, _ mutate: (inout PendingSlot) -> Void) {
        var slots = loadPendingSlots()
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        mutate(&slots[index])
        savePendingSlots(slots)
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
