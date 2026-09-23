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

        let firesAtTimes = Constants.notificationFixedHours
            .compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: today) }
            .filter { $0 > .now }
        guard !firesAtTimes.isEmpty else {
            UserDefaults.standard.set(today, forKey: scheduledDayKey)
            return
        }

        var slots: [PendingSlot] = []
        for firesAt in firesAtTimes {
            let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false)
            slots.append(slot)
            await scheduleSystemNotification(
                id: slot.id,
                firesAt: firesAt,
                title: NotificationVariant.fallbackGeneric.title,
                body: NotificationVariant.fallbackGeneric.body,
                sender: mascotSender(title: NotificationVariant.fallbackGeneric.title, consumidoHojeML: consumidoHoje, metaDiariaML: profile.metaDiariaML)
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
        for index in slots.indices where !slots[index].captured {
            let minutesUntilFire = slots[index].firesAt.timeIntervalSince(now) / 60
            guard minutesUntilFire <= Double(Self.captureLeadMinutes) else { continue }

            if await hasOutstandingHydrationNotification() {
                center.removePendingNotificationRequests(withIdentifiers: [slots[index].id.uuidString])
                slots[index].captured = true
                continue
            }

            await captureContext(id: slots[index].id, firesAt: slots[index].firesAt, context: context)
            slots[index].captured = true
        }
        savePendingSlots(slots)
    }

    /// Whether a previous hydration reminder is still sitting delivered (lock
    /// screen/Notification Center) without having been tapped or dismissed — a tap
    /// or a swipe-dismiss both remove an entry from `deliveredNotifications()`, so
    /// this is exactly "outstanding, unactioned." Used to skip a slot outright
    /// rather than pile a new reminder on top of one the tester hasn't dealt with.
    private func hasOutstandingHydrationNotification() async -> Bool {
        let delivered = await center.deliveredNotifications()
        return delivered.contains { $0.request.content.categoryIdentifier == Constants.NotificationCategory.hydrationReminder }
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
        let variant = Self.selectVariant(firesAt: firesAt, weather: weather, profile: profile, logs: logs)

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
        // `NotificationDelegate`), the tester already saw the generic fallback text
        // and there's nothing left to swap; the event still records which variant
        // *would* have been shown, so no data is lost.
        if firesAt > .now {
            let sender = mascotSender(title: variant.title, consumidoHojeML: consumidoHoje, metaDiariaML: profile.metaDiariaML)
            await scheduleSystemNotification(id: id, firesAt: firesAt, title: variant.title, body: variant.body, sender: sender)
        }
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
        calendar: Calendar = .current
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
        return [.middayNeutral, .symptomHeadacheMidday, .symptomConcentrationMidday].randomElement()!
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
        let slot = PendingSlot(id: UUID(), firesAt: firesAt, captured: false)
        var slots = loadPendingSlots()
        slots.append(slot)
        savePendingSlots(slots)
        await scheduleSystemNotification(
            id: slot.id,
            firesAt: firesAt,
            title: NotificationVariant.fallbackGeneric.title,
            body: NotificationVariant.fallbackGeneric.body,
            sender: currentMascotSender(title: NotificationVariant.fallbackGeneric.title)
        )
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

    private func scheduleSystemNotification(id: UUID, firesAt: Date, title: String, body: String, sender: MascotSender? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Constants.NotificationCategory.hydrationReminder
        content.userInfo = ["eventID": id.uuidString]
        content.sound = .default

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
    /// is whichever mascot asset matches today's hydration progress (same
    /// `AppTheme.mascotImageName` used on Home/Profile), and `title` (the persona
    /// copy's own title, e.g. "Vai desidratar nesse calor?") doubles as the "contact
    /// name" the system shows in bold, since these notifications already read as the
    /// mascot needling the tester. Returns nil (silently) on any image-loading
    /// failure, since falling back to a plain notification is better than not firing.
    private func mascotSender(title: String, consumidoHojeML: Int, metaDiariaML: Int) -> MascotSender? {
        let progress = metaDiariaML > 0 ? min(1, Double(consumidoHojeML) / Double(metaDiariaML)) : 0
        let imageName = AppTheme.mascotImageName(for: progress)
        guard let image = UIImage(named: imageName), let data = image.pngData() else { return nil }

        let avatar = INImage(imageData: data)
        let person = INPerson(
            personHandle: INPersonHandle(value: "hidratapoc.mascot", type: .unknown),
            nameComponents: nil,
            displayName: title,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: "hidratapoc.mascot",
            isMe: false,
            suggestionType: .none
        )
        return MascotSender(person: person, image: avatar)
    }

    /// Same as `mascotSender(title:consumidoHojeML:metaDiariaML:)`, but fetches
    /// whatever profile/intake data is on hand right now — used where the caller
    /// doesn't already have a `ModelContext`/profile in scope (initial scheduling,
    /// snooze).
    private func currentMascotSender(title: String) -> MascotSender? {
        guard let profile = (try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()))?.first else { return nil }
        let targetUserID = profile.userID
        let logs = (try? PersistenceController.context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.userID == targetUserID }))) ?? []
        let consumidoHoje = HydrationMath.totalML(logs, on: .now)
        return mascotSender(title: title, consumidoHojeML: consumidoHoje, metaDiariaML: profile.metaDiariaML)
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
