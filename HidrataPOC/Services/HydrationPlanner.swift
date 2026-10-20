import Foundation

/// One point of an ideal hydration schedule: by this hour, a strategic day
/// would have this much water down.
struct HydrationPlanPoint {
    let hour: Int
    let idealCumulativeML: Int
}

/// Builds "how an ideal day would look": that day's weather-adjusted goal spread
/// across the same candidate hours the notification policy itself chooses
/// reminders from (`PolicyParams.slotHours`), weighted by how strongly the
/// user's own learned policy favors each hour — so the plan reflects the same
/// hour-of-day/weekday/temperature/deficit reasoning that already picks
/// reminder times, not a separate, disconnected guess. Works for any day, not
/// just today: each day gets its own curve from its own weather and goal, so a
/// hot Saturday's plan looks different from a mild Tuesday's.
enum HydrationPlanner {
    /// Deterministic PRNG so a given day's plan is stable across re-renders
    /// (the live policy uses a true RNG because it's making a real decision;
    /// this is illustrative, so it must not flicker every time the sheet redraws).
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /// `nil` when there's no usable policy prior yet (e.g. first launch before
    /// any sync) or the goal is zero — callers should just skip the overlay.
    @MainActor
    static func idealDayCurve(
        profile: UserProfile,
        effectiveGoalML: Int,
        weather: WeatherContext?,
        day: Date,
        calendar: Calendar = .current
    ) -> [HydrationPlanPoint]? {
        guard effectiveGoalML > 0, let params = PolicyStore.shared.loadParams() else { return nil }
        let policy = ThompsonPolicy(params: params, posterior: PolicyStore.shared.loadPosterior())

        let dayStart = calendar.startOfDay(for: day)
        let slots: [Date] = params.slotHours.sorted().compactMap { hour in
            guard let slot = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { return nil }
            return QuietHours.allows(slot, params: params, calendar: calendar) ? slot : nil
        }
        guard !slots.isEmpty else { return nil }

        // Each candidate hour scored on its own, as if it were the only chance to
        // drink that day (deficit fixed at "nothing yet"): the policy's preference
        // for morning vs. evening, weekday vs. weekend, and that day's temperature
        // is what should shape the curve, not a circular guess about the plan's
        // own output.
        var rng = SeededGenerator(state: seed(for: dayStart))
        let weights: [Double] = slots.enumerated().map { index, slot in
            let lastSlot = index > 0 ? slots[index - 1] : nil
            let ctx = SlotContext(
                temperaturaC: weather?.temperaturaC,
                umidadeRelativa: weather?.umidadeRelativa,
                sensacaoTermicaC: weather?.sensacaoTermicaC,
                ocupadoNoMomento: false,
                densidadeEventosDia: 0,
                deficitAcumuladoML: Double(effectiveGoalML),
                metaDiariaML: Double(effectiveGoalML),
                lastIntake: lastSlot,
                idade: profile.idade,
                generoRaw: profile.genero
            )
            let raw = PolicyFeatures.raw(slotDate: slot, context: ctx, calendar: calendar)
            let x = FeatureEncoder.encode(raw, params: params)
            return policy.probabilitySend(x: x, rng: &rng)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        var running = 0
        var points: [HydrationPlanPoint] = []
        for (index, slot) in slots.enumerated() {
            running += Int((weights[index] / totalWeight * Double(effectiveGoalML)).rounded())
            points.append(HydrationPlanPoint(hour: calendar.component(.hour, from: slot), idealCumulativeML: min(running, effectiveGoalML)))
        }
        // Rounding can leave the last point short of the goal by a mL or two; snap it.
        if var last = points.popLast() {
            last = HydrationPlanPoint(hour: last.hour, idealCumulativeML: effectiveGoalML)
            points.append(last)
        }
        return points
    }

    private static func seed(for day: Date) -> UInt64 {
        UInt64(bitPattern: Int64(day.timeIntervalSinceReferenceDate)) &+ 1
    }
}
