import Foundation

/// Per-user posterior, persisted in the App Group (see PolicyStore).
struct PolicyPosterior: Codable, Equatable {
    var policyVersion: String
    var mean: [Double]
    var precision: [Double]      // diagonal
    var lastUpdateDays: Double?  // days since 1970 of the last decay step
}

/// Swift port of python/policy.py. Keep the two in lockstep; ThompsonPolicyTests
/// checks this one against fixtures produced by the Python code.
struct ThompsonPolicy {
    let params: PolicyParams
    private(set) var posterior: PolicyPosterior
    private let priorPrecision: [Double]

    init(params: PolicyParams, posterior: PolicyPosterior? = nil) {
        self.params = params
        self.priorPrecision = params.priorVar.map { 1.0 / $0 }
        if let p = posterior, p.policyVersion == params.policyVersion,
           p.mean.count == params.priorMean.count, p.precision.count == params.priorMean.count {
            self.posterior = p
        } else {
            self.posterior = PolicyPosterior(policyVersion: params.policyVersion, mean: params.priorMean,
                                             precision: priorPrecision, lastUpdateDays: nil)
        }
    }

    static func days(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 }

    // MARK: Forgetting

    /// Precision decays toward the prior precision; means are kept. The user's
    /// learned preferences persist but become less certain, so new evidence can
    /// move them when routines change. Effective memory ~ 1 / (1 - dailyDecay) days.
    mutating func decay(to tDays: Double) {
        if let last = posterior.lastUpdateDays, tDays > last {
            let g = pow(params.dailyDecay, tDays - last)
            for i in posterior.precision.indices {
                posterior.precision[i] = priorPrecision[i] + g * (posterior.precision[i] - priorPrecision[i])
            }
        }
        posterior.lastUpdateDays = max(posterior.lastUpdateDays ?? tDays, tDays)
    }

    // MARK: Decide

    /// nil for a quiet slot: nothing is sent and no decision is logged.
    /// Otherwise (send, propensity of the chosen action under this policy).
    mutating func decide<G: RandomNumberGenerator>(raw: [String: Double], slotDate: Date, now: Date,
                                                   calendar: Calendar = .current,
                                                   rng: inout G) -> (send: Bool, propensity: Double)? {
        guard !params.isQuiet(minuteOfDay: QuietHours.minuteOfDay(slotDate, calendar: calendar)) else { return nil }
        decay(to: Self.days(now))
        let pSend = probabilitySend(x: FeatureEncoder.encode(raw, params: params), rng: &rng)
        let send = Double.random(in: 0..<1, using: &rng) < pSend
        return (send, send ? pSend : 1 - pSend)
    }

    /// P(send | x): Monte Carlo over Thompson draws, mixed with epsilon, clipped to the floor.
    func probabilitySend<G: RandomNumberGenerator>(x: [Double], rng: inout G) -> Double {
        let sendPhi = Self.phi(x, send: true), skipPhi = Self.phi(x, send: false)
        var count = 0
        var w = posterior.mean
        for _ in 0..<params.mcSamples {
            for i in w.indices {
                w[i] = posterior.mean[i] + Self.gaussian(&rng) / posterior.precision[i].squareRoot()
            }
            if prefersSend(w: w, sendPhi: sendPhi, skipPhi: skipPhi) { count += 1 }
        }
        let pTS = Double(count) / Double(max(params.mcSamples, 1))
        let p = params.epsilon * 0.5 + (1 - params.epsilon) * pTS
        return min(max(p, params.propensityFloor), 1 - params.propensityFloor)
    }

    private func prefersSend(w: [Double], sendPhi: [Double], skipPhi: [Double]) -> Bool {
        let pSend = Self.sigmoid(Self.dot(w, sendPhi))
        let skipScore = params.objective == "uplift" ? Self.sigmoid(Self.dot(w, skipPhi)) : 0
        return pSend - params.lambda > skipScore
    }

    // MARK: Update

    /// Exact single-observation MAP under a diagonal Gaussian prior + Laplace precision update.
    mutating func update(raw: [String: Double], send: Bool, outcome: Bool, at date: Date) {
        decay(to: Self.days(date))
        let f = Self.phi(FeatureEncoder.encode(raw, params: params), send: send)
        let a = Self.dot(posterior.mean, f)
        var s = 0.0
        for i in f.indices { s += f[i] * f[i] / posterior.precision[i] }
        let y = outcome ? 1.0 : 0.0
        var lo = 0.0, hi = 1.0
        for _ in 0..<60 {                                   // g(p) = p - sigmoid(a + (y - p) s) is increasing
            let mid = 0.5 * (lo + hi)
            if mid - Self.sigmoid(a + (y - mid) * s) > 0 { hi = mid } else { lo = mid }
        }
        let p = 0.5 * (lo + hi)
        for i in f.indices { posterior.mean[i] += (y - p) * f[i] / posterior.precision[i] }
        for i in f.indices { posterior.precision[i] += p * (1 - p) * f[i] * f[i] }
    }

    /// New prior arrived: start from it and replay the user's resolved decisions.
    static func rebuilt(params: PolicyParams,
                        history: [(raw: [String: Double], send: Bool, outcome: Bool, at: Date)]) -> ThompsonPolicy {
        var policy = ThompsonPolicy(params: params)
        for h in history.sorted(by: { $0.at < $1.at }) {
            policy.update(raw: h.raw, send: h.send, outcome: h.outcome, at: h.at)
        }
        return policy
    }

    // MARK: Math

    static func phi(_ x: [Double], send: Bool) -> [Double] {
        x + (send ? x : [Double](repeating: 0, count: x.count))
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in a.indices { s += a[i] * b[i] }
        return s
    }

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }

    static func gaussian<G: RandomNumberGenerator>(_ rng: inout G) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
