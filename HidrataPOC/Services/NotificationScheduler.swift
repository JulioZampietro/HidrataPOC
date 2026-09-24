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
private struct PendingSlot: Codable {
    let id: UUID
    let firesAt: Date
    var captured: Bool
    /// `NotificationVariant.rawValue` the system notification is currently armed with.
    /// Chosen when the slot is scheduled (not only at capture time), so the persona copy
    /// shows even if the app never got a chance to run in the capture window; kept so a
    /// slot that fires before capture records the variant that was actually shown.
    var variant: String? = nil
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
    private let adjustmentValueKey = "lastTemperatureAdjustmentML"
    private let adjustmentDayKey = "lastTemperatureAdjustmentDay"
    private let renderedMascotKey = "pendingNotificationsRenderedMascot"
    private let center = UNUserNotificationCenter.current()

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

    /// Generates today's fixed reminder times (`Constants.notificationFixedHours`) the
    /// first time this is called on a given day, then schedules a system notification
    /// for each one still ahead of `.now`. Safe to call repeatedly — no-ops once
    /// today's slots already exist.
    func ensureTodayScheduled() async {
        // No point scheduling reminders (or capturing context for them) before
        // onboarding has created a profile — there's no goal/timezone to reason about
        // yet, and `captureContext` would silently no-op without one.
        guard let profile = (try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let last = UserDefaults.standard.object(forKey: scheduledDayKey) as? Date,
           calendar.isDate(last, inSameDayAs: today) {
            return
        }

        let targetUserID = profile.userID
        let logs = (try? PersistenceController.context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: .now)
        let goalML = await effectiveGoalML(for: profile)

        let firesAtTimes = Constants.notificationFixedHours
            .compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: today) }
            .filter { $0 > .now }
        guard !firesAtTimes.isEmpty else {
            UserDefaults.standard.set(today, forKey: scheduledDayKey)
            return
        }

        // Every slot is armed with its persona copy right away — the capture pass a few
        // minutes before firing (`captureContext`) only refines it with fresher weather.
        // Relying on that pass alone left the generic fallback on screen whenever the app
        // wasn't running in the capture window, which is the common case.
        let weather = await WeatherContextService.shared.currentContext()
        var slots: [PendingSlot] = []
        for firesAt in firesAtTimes {
            let variant = Self.selectVariant(firesAt: firesAt, weather: weather, profile: profile, logs: logs)
            let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false, variant: variant.rawValue)
            slots.append(slot)
            await scheduleSystemNotification(
                id: slot.id,
                firesAt: firesAt,
                title: variant.title,
                body: variant.body,
                sender: mascotSender(title: variant.title, consumidoHojeML: consumidoHoje, goalML: goalML)
            )
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
        var slots = loadPendingSlots()
        guard !slots.isEmpty else { return }

        let now = Date.now
        var didChange = false
        for index in slots.indices where !slots[index].captured {
            let minutesUntilFire = slots[index].firesAt.timeIntervalSince(now) / 60
            guard minutesUntilFire <= Double(Self.captureLeadMinutes) else { continue }

            // Re-checked on every tick, never cached: an outstanding notification
            // only blocks sending right now, not this slot for the rest of the day.
            if await hasOutstandingHydrationNotification(excluding: slots[index].id) {
                await pushBackPendingSlot(id: slots[index].id, variant: slots[index].variant.flatMap(NotificationVariant.init(rawValue:)))
                continue
            }

            let wasOverdue = minutesUntilFire < 0
            if let variant = await captureContext(id: slots[index].id, firesAt: slots[index].firesAt, context: context, forceImmediateDelivery: wasOverdue) {
                slots[index].variant = variant.rawValue
            }
            slots[index].captured = true
            didChange = true
        }
        if didChange {
            savePendingSlots(slots)
        }
    }

    /// Re-arms a held-back slot's system notification a few minutes out (same
    /// identifier, keeping the slot's persona copy — generic fallback only if it never
    /// had one) so it doesn't fire while still blocked, but keeps trying — the slot
    /// stays uncaptured, so the next tick checks again.
    private func pushBackPendingSlot(id: UUID, variant: NotificationVariant?) async {
        let retryAt = Date.now.addingTimeInterval(Double(Constants.notificationBlockedRetryMinutes) * 60)
        let copy = variant ?? .fallbackGeneric
        await scheduleSystemNotification(
            id: id,
            firesAt: retryAt,
            title: copy.title,
            body: copy.body,
            sender: await currentMascotSender(title: copy.title)
        )
    }

    /// Whether a previous hydration reminder is still sitting delivered (lock
    /// screen/Notification Center) without having been tapped or dismissed — a tap
    /// or a swipe-dismiss both remove an entry from `deliveredNotifications()`, so
    /// this is exactly "outstanding, unactioned." Used to hold a slot back rather
    /// than pile a new reminder on top of one the tester hasn't dealt with.
    /// `excluding` leaves out the slot currently being evaluated, so a reminder
    /// that already delivered itself (e.g. caught up on after being held back)
    /// never counts as blocking its own slot.
    private func hasOutstandingHydrationNotification(excluding id: UUID) async -> Bool {
        let delivered = await center.deliveredNotifications()
        return delivered.contains {
            $0.request.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder
                && $0.request.identifier != id.uuidString
        }
    }

    /// Gathers weather/calendar/deficit context and creates the `NotificationEvent`
    /// for one slot. Public so `NotificationDelegate` can call it as a fallback when a
    /// tester interacts with a notification whose event was never pre-captured.
    ///
    /// `forceImmediateDelivery` is for a slot that was held back past its original
    /// `firesAt` by `hasOutstandingHydrationNotification` (see
    /// `captureImminentSlots`/`pushBackPendingSlot`) and only just cleared: nothing
    /// was ever delivered for it, unlike the ordinary `firesAt <= .now` case below
    /// (a notification that already fired on its own and is now being interacted
    /// with), so it still needs scheduling — just for right now instead of the
    /// stale original time.
    ///
    /// Returns the variant recorded on the event (nil if nothing was captured), so the
    /// caller can keep the slot's bookkeeping in sync with what's armed.
    @discardableResult
    func captureContext(id: UUID, firesAt: Date, context: ModelContext, forceImmediateDelivery: Bool = false) async -> NotificationVariant? {
        guard fetchNotificationEvent(id: id, context: context) == nil else { return nil }
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return nil }

        let weather = await WeatherContextService.shared.currentContext()
        let calendarContext = CalendarContextService.shared.currentContext(around: firesAt)

        let targetUserID = profile.userID
        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: firesAt)
        let deficit = HydrationMath.deficitML(metaDiariaML: profile.metaDiariaML, consumidoHojeML: consumidoHoje)
        let minutesSinceLast = HydrationMath.minutesSinceLastIntake(logs, now: firesAt)
        // The variant the slot is currently armed with (chosen at scheduling time).
        let armed = loadPendingSlots().first { $0.id == id }?.variant.flatMap(NotificationVariant.init(rawValue:))
        let alreadyFired = firesAt <= .now && !forceImmediateDelivery
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

        // Reschedule with the chosen persona copy, in place, only if the notification
        // hasn't fired yet — if it already fired (last-resort fallback capture from
        // `NotificationDelegate`), the tester already saw the armed copy and there's
        // nothing left to swap.
        if firesAt > .now || forceImmediateDelivery {
            let goalML = await effectiveGoalML(for: profile)
            let sender = mascotSender(title: variant.title, consumidoHojeML: consumidoHoje, goalML: goalML)
            let scheduledFireDate = firesAt > .now ? firesAt : Date.now.addingTimeInterval(2)
            await scheduleSystemNotification(id: id, firesAt: scheduledFireDate, title: variant.title, body: variant.body, sender: sender)
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

    func resolveInteraction(eventID: UUID, status: StatusInteracao, context: ModelContext) async {
        guard let event = fetchNotificationEvent(id: eventID, context: context) else { return }
        guard event.statusInteracao == nil else { return } // already resolved once
        event.statusInteracao = status.rawValue
        event.tempoAteAgirMin = max(0, Int(Date.now.timeIntervalSince(event.sentAt) / 60))
        try? context.save()
        await CloudKitSyncService.shared.push(event)
        try? context.save()
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
        let log = await IntakeLogService.record(
            preset: preset,
            userID: userID,
            source: "app",
            weather: WeatherContextService.shared.cachedContext,
            context: context
        )
        await HealthKitService.shared.save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
        await refreshPendingMascotIfNeeded()
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
    /// day's regular random schedule.
    func scheduleSnoozeSlot() async {
        let firesAt = Date.now.addingTimeInterval(15 * 60)
        let variant = await provisionalVariant(firesAt: firesAt)
        let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false, variant: variant.rawValue)
        var slots = loadPendingSlots()
        slots.append(slot)
        savePendingSlots(slots)
        await scheduleSystemNotification(
            id: slot.id,
            firesAt: firesAt,
            title: variant.title,
            body: variant.body,
            sender: await currentMascotSender(title: variant.title)
        )
    }

    /// Persona variant for an ad-hoc slot (snooze), from whatever profile/intake/weather
    /// data is on hand right now. Falls back to the generic copy without a profile.
    private func provisionalVariant(firesAt: Date) async -> NotificationVariant {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return .fallbackGeneric }
        let targetUserID = profile.userID
        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let weather = await WeatherContextService.shared.currentContext()
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

    private func scheduleSystemNotification(id: UUID, firesAt: Date, title: String, body: String, sender: MascotSender? = nil, isDebug: Bool = false) async {
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
        let request = UNNotificationRequest(identifier: id.uuidString, content: finalContent, trigger: trigger)
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
        let imageName = Self.currentMascotImageName(consumidoHojeML: consumidoHojeML, goalML: goalML)
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

    /// Same as `mascotSender(title:consumidoHojeML:goalML:)`, but fetches
    /// whatever profile/intake data is on hand right now — used where the caller
    /// doesn't already have a `ModelContext`/profile in scope (snooze, pending-content refresh).
    private func currentMascotSender(title: String) async -> MascotSender? {
        guard let state = await currentHydrationState() else { return nil }
        return mascotSender(title: title, consumidoHojeML: state.consumidoHojeML, goalML: state.goalML)
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
        let stamp = "\(day.timeIntervalSince1970)|\(imageName)"
        guard UserDefaults.standard.string(forKey: renderedMascotKey) != stamp else { return }

        let pending = await center.pendingNotificationRequests()
        for request in pending where request.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder {
            guard let id = UUID(uuidString: request.identifier),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let firesAt = trigger.nextTriggerDate() else { continue }
            let sender = mascotSender(title: request.content.title, consumidoHojeML: state.consumidoHojeML, goalML: state.goalML)
            await scheduleSystemNotification(id: id, firesAt: firesAt, title: request.content.title, body: request.content.body, sender: sender)
        }
        UserDefaults.standard.set(stamp, forKey: renderedMascotKey)
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
