import Foundation
import SwiftData

/// Supplies the context of a candidate slot as known at `now`. Implemented by
/// `AppPolicyContextProvider` with the services that already fill NotificationEvent,
/// so features mean the same thing as in the training data.
@MainActor
protocol PolicyContextProvider {
    func context(forSlotAt slotDate: Date, now: Date) async -> SlotContext
}

/// Glue between the policy and `NotificationScheduler`, which calls `runCycle`
/// whenever it re-plans (launch/foreground, notification responses, background
/// refresh) and `resolveOutcomes` after every tick.
///
/// Rules this class relies on:
///  - A decision is final. The scheduler turns every decision into a slot and never
///    drops or moves it afterwards. When the one-reminder-at-a-time rule holds a slot
///    back anyway, the scheduler marks the decision `suppressed`, and it is never
///    learned from (see `SlotDecision.suppressed`).
///  - Only run it while notification authorization is granted; otherwise a
///    "send" never reaches the user and its outcome is meaningless.
@MainActor
final class PolicyCoordinator {
    private let context: ModelContext
    private let provider: PolicyContextProvider
    private let store: PolicyStore
    private let userID: String
    private let calendar: Calendar
    private var policy: ThompsonPolicy?

    /// How far back resolved decisions are replayed when a new prior arrives.
    var replayDays = 180

    init(context: ModelContext, provider: PolicyContextProvider, userID: String,
         store: PolicyStore = .shared, calendar: Calendar = .current) {
        self.context = context
        self.provider = provider
        self.userID = userID
        self.store = store
        self.calendar = calendar
    }

    var params: PolicyParams? { policy?.params ?? store.loadParams() }

    // MARK: Main entry point

    /// Refresh params, learn from finished slots, decide the upcoming ones.
    /// Returns every decision (send and skip) from now through tomorrow's first slot,
    /// or nil when there are no usable params. Idempotent.
    func runCycle(now: Date = .now, refreshParams: Bool = true) async throws -> [SlotDecision]? {
        if refreshParams, let newParams = await store.refreshFromCloudKit(now: now) {
            try adopt(newParams)
        }
        try resolveOutcomes(now: now)
        return try await planUpcomingSlots(now: now)
    }

    // MARK: Planning

    /// Decides every undecided, non-quiet slot from now through tomorrow's first
    /// slot (08:00), then returns all decisions in that range.
    func planUpcomingSlots(now: Date = .now) async throws -> [SlotDecision]? {
        guard var policy = try loadPolicy() else { return nil }
        let params = policy.params
        let candidates = candidateSlots(after: now, params: params)
        guard let first = candidates.first, let last = candidates.last else { return [] }

        let uid = userID
        let existing = try context.fetch(FetchDescriptor<SlotDecision>(predicate: #Predicate<SlotDecision> {
            $0.userID == uid && $0.slotFiresAt >= first && $0.slotFiresAt <= last
        }))
        let decided = Set(existing.map(\.slotFiresAt))
        var decisions = existing.filter { QuietHours.allows($0.slotFiresAt, params: params, calendar: calendar) }

        var rng = SystemRandomNumberGenerator()
        for slot in candidates where !decided.contains(slot) {
            guard QuietHours.allows(slot, params: params, calendar: calendar) else { continue }
            let ctx = await provider.context(forSlotAt: slot, now: now)
            let raw = PolicyFeatures.raw(slotDate: slot, context: ctx, calendar: calendar)
            guard let d = policy.decide(raw: raw, slotDate: slot, now: now, calendar: calendar, rng: &rng) else { continue }
            let row = SlotDecision(userID: userID, slotFiresAt: slot, decidedAt: now,
                                   slotHour: calendar.component(.hour, from: slot), send: d.send,
                                   propensity: d.propensity, policyVersion: params.policyVersion,
                                   featuresJSON: PolicyFeatures.json(raw))
            context.insert(row)
            decisions.append(row)
        }
        self.policy = policy
        store.savePosterior(policy.posterior)
        try context.save()
        return decisions.sorted { $0.slotFiresAt < $1.slotFiresAt }
    }

    private func candidateSlots(after now: Date, params: PolicyParams) -> [Date] {
        let hours = params.slotHours.sorted()
        guard let firstHour = hours.first else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let horizon = calendar.date(bySettingHour: firstHour, minute: 0, second: 0, of: tomorrow)
        else { return [] }
        var out: [Date] = []
        for day in [today, tomorrow] {
            for h in hours {
                if let d = calendar.date(bySettingHour: h, minute: 0, second: 0, of: day),
                   d > now.addingTimeInterval(60), d <= horizon {
                    out.append(d)
                }
            }
        }
        return out
    }

    // MARK: Learning

    /// Closes every decision whose response window has ended and that the scheduler
    /// confirmed reached the user (`suppressed == false`), and feeds it to the
    /// posterior, oldest first. Outcome = any IntakeLog in [slot, slot + window], for
    /// sends and skips alike (skips give the "would they drink anyway" signal).
    func resolveOutcomes(now: Date = .now) throws {
        guard var policy = try loadPolicy() else { return }
        let window = TimeInterval(policy.params.windowMinutes * 60)
        let uid = userID
        let open = try context.fetch(FetchDescriptor<SlotDecision>(
            predicate: #Predicate<SlotDecision> { $0.userID == uid && $0.intakeInWindow == nil && $0.suppressed == false },
            sortBy: [SortDescriptor(\.slotFiresAt)]))

        for d in open {
            let start = d.slotFiresAt
            let end = start.addingTimeInterval(window)
            guard end <= now else { continue }
            let drank = try context.fetchCount(FetchDescriptor<IntakeLog>(predicate: #Predicate<IntakeLog> {
                $0.userID == uid && $0.timestamp >= start && $0.timestamp <= end
            })) > 0
            d.intakeInWindow = drank
            d.resolvedAt = now
            d.syncStatus = .pending
            policy.update(raw: PolicyFeatures.decode(d.featuresJSON), send: d.isSend, outcome: drank, at: end)
        }
        self.policy = policy
        store.savePosterior(policy.posterior)
        try context.save()
    }

    // MARK: Prior updates

    /// A new population prior arrived: rebuild this user's posterior on top of it
    /// by replaying their resolved decisions, so personalization is not lost.
    func adopt(_ params: PolicyParams) throws {
        let rebuilt = try rebuild(params)
        policy = rebuilt
        store.savePosterior(rebuilt.posterior)
    }

    private func loadPolicy() throws -> ThompsonPolicy? {
        if let policy { return policy }
        guard let params = store.loadParams() else { return nil }
        let loaded: ThompsonPolicy
        if let saved = store.loadPosterior(), saved.policyVersion == params.policyVersion {
            loaded = ThompsonPolicy(params: params, posterior: saved)
        } else {
            loaded = try rebuild(params)   // first run, or posterior from an older prior
            store.savePosterior(loaded.posterior)
        }
        policy = loaded
        return loaded
    }

    private func rebuild(_ params: PolicyParams) throws -> ThompsonPolicy {
        let uid = userID
        let since = Date().addingTimeInterval(-Double(replayDays) * 86_400)
        let resolved = try context.fetch(FetchDescriptor<SlotDecision>(predicate: #Predicate<SlotDecision> {
            $0.userID == uid && $0.intakeInWindow != nil && $0.slotFiresAt >= since
        }))
        let window = TimeInterval(params.windowMinutes * 60)
        let history = resolved.compactMap { d -> (raw: [String: Double], send: Bool, outcome: Bool, at: Date)? in
            guard let y = d.intakeInWindow else { return nil }
            return (PolicyFeatures.decode(d.featuresJSON), d.isSend, y, d.slotFiresAt.addingTimeInterval(window))
        }
        return ThompsonPolicy.rebuilt(params: params, history: history)
    }
}
