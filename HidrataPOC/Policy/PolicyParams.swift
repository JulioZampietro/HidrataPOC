import Foundation

/// Mirror of python/build_prior.py's policy_params.json. Decoded from the
/// PolicyParams CloudKit record ("current"), a cached copy, or the bundled file.
struct PolicyParams: Codable, Equatable {
    struct Feature: Codable, Equatable {
        let name: String
        let kind: String        // "numeric" | "binary"
        let mean: Double
        let std: Double
        let impute: Double      // raw-scale value used when the feature is missing
    }

    let policyVersion: String
    let features: [Feature]
    let priorMean: [Double]     // [base: 1, f1..fn | send: 1, f1..fn]
    let priorVar: [Double]
    let objective: String       // "response" | "uplift"
    let lambda: Double          // cost of one reminder, in units of P(intake)
    let epsilon: Double
    let propensityFloor: Double
    let mcSamples: Int
    let dailyDecay: Double
    let quietStartMinute: Int
    let quietEndMinute: Int
    let windowMinutes: Int
    let slotHours: [Int]

    var isValid: Bool {
        priorMean.count == 2 * (features.count + 1)
            && priorVar.count == priorMean.count
            && priorVar.allSatisfy { $0 > 0 }
            && features.allSatisfy { $0.std > 0 }
            && (0.0...1.0).contains(dailyDecay)
    }

    func isQuiet(minuteOfDay m: Int) -> Bool {
        QuietHours.contains(minuteOfDay: m, start: quietStartMinute, end: quietEndMinute)
    }
}

// MARK: - Quiet hours (hard rule: no reminder fires in [22:00, 08:00) local time)

enum QuietHours {
    /// Used before any params exist, so the rule holds from the first launch.
    static let defaultStartMinute = 22 * 60
    static let defaultEndMinute = 8 * 60

    static func contains(minuteOfDay m: Int, start: Int, end: Int) -> Bool {
        start > end ? (m >= start || m < end) : (m >= start && m < end)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The single check every code path must pass before adding a notification request.
    static func allows(_ fireDate: Date, params: PolicyParams?, calendar: Calendar = .current) -> Bool {
        let m = minuteOfDay(fireDate, calendar: calendar)
        let s = params?.quietStartMinute ?? defaultStartMinute
        let e = params?.quietEndMinute ?? defaultEndMinute
        return !contains(minuteOfDay: m, start: s, end: e)
    }
}

// MARK: - Raw features (names and formulas must match python/dataset.py)

/// Everything the policy needs to know about one candidate slot, gathered by the
/// app from its existing services (weather cache/forecast, CalendarContext,
/// HydrationMath, UserProfile). Use the SAME helpers that fill NotificationEvent,
/// so the semantics match the training data.
struct SlotContext {
    var temperaturaC: Double?
    var umidadeRelativa: Double?
    var sensacaoTermicaC: Double?
    var ocupadoNoMomento: Bool?       // busy at the slot time (EventKit can answer for the future)
    var densidadeEventosDia: Int?
    var deficitAcumuladoML: Double?
    var metaDiariaML: Double?
    var lastIntake: Date?
    var idade: Int?
    var generoRaw: String?            // Genero raw value: "masculino" / "feminino"
}

enum PolicyFeatures {
    /// Raw (unstandardized) features. Missing values are simply absent; the encoder
    /// imputes them. This dictionary is what SlotDecision.featuresJSON stores.
    static func raw(slotDate: Date, context c: SlotContext, calendar: Calendar = .current) -> [String: Double] {
        var f: [String: Double] = [:]
        let comps = calendar.dateComponents([.hour, .minute, .weekday], from: slotDate)
        let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
        let w = 2 * Double.pi * hour / 24
        f["hour_sin"] = sin(w)
        f["hour_cos"] = cos(w)
        f["hour_sin2"] = sin(2 * w)
        f["hour_cos2"] = cos(2 * w)
        let weekday = comps.weekday ?? 2                       // 1 = Sunday, 7 = Saturday
        f["weekend"] = (weekday == 1 || weekday == 7) ? 1 : 0

        if let t = c.sensacaoTermicaC ?? c.temperaturaC { f["apparent_temp"] = t }
        if let h = c.umidadeRelativa { f["humidity"] = h }
        if let b = c.ocupadoNoMomento { f["busy"] = b ? 1 : 0 }
        if let d = c.densidadeEventosDia { f["event_density"] = Double(d) }
        if let deficit = c.deficitAcumuladoML, let goal = c.metaDiariaML, goal > 0 {
            f["deficit_frac"] = min(max(deficit / goal, -1.0), 1.5)
        }
        if let last = c.lastIntake {
            let minutes = max(0, slotDate.timeIntervalSince(last) / 60)
            f["log_min_since_last"] = log1p(minutes)
            f["no_intake_yet"] = 0
        } else {
            f["no_intake_yet"] = 1
        }
        if let age = c.idade { f["age"] = Double(age) }
        switch c.generoRaw {
        case "feminino": f["female"] = 1
        case "masculino": f["female"] = 0
        default: break
        }
        return f
    }

    static func json(_ raw: [String: Double]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(raw)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decode(_ json: String) -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(json.utf8))) ?? [:]
    }
}

enum FeatureEncoder {
    /// Raw dictionary -> [1, standardized features...] in the params' feature order.
    static func encode(_ raw: [String: Double], params: PolicyParams) -> [Double] {
        var x: [Double] = [1.0]
        x.reserveCapacity(params.features.count + 1)
        for f in params.features {
            var v = raw[f.name] ?? f.impute
            if v.isNaN { v = f.impute }
            x.append((v - f.mean) / f.std)
        }
        return x
    }
}
