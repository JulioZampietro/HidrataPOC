import Foundation
import Testing
@testable import HidrataPOC

/// Confere a política em Swift contra a referência em Python (python/policy.py do
/// pacote do modelo). `policy_parity_vectors.json` (fixture deste target) e o
/// `policy_params.json` que vai no app precisam vir da MESMA execução do
/// build_prior.py — rode de novo depois de qualquer mudança em um dos lados.
struct ThompsonPolicyTests {
    private struct Case: Decodable {
        let raw: [String: Double]
        let send: Bool
        let y: Bool
        let tDays: Double
        let encoded: [Double]
        let meanAfter: [Double]
        let precisionAfter: [Double]
    }

    private struct Fixture: Decodable {
        let policyVersion: String
        let cases: [Case]
        let quiet: [String: Bool]
    }

    private final class BundleToken {}

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    /// O prior que vai no app (o teste roda hospedado nele).
    private func bundledParams() throws -> PolicyParams {
        let url = try #require(Bundle.main.url(forResource: "policy_params", withExtension: "json"))
        return try JSONDecoder().decode(PolicyParams.self, from: Data(contentsOf: url))
    }

    private func fixture() throws -> Fixture {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "policy_parity_vectors", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func matchesPythonReference() throws {
        let params = try bundledParams()
        let fixture = try fixture()
        #expect(params.isValid)
        try #require(params.policyVersion == fixture.policyVersion, "fixtures from a different build_prior run")

        var policy = ThompsonPolicy(params: params)
        for (i, c) in fixture.cases.enumerated() {
            expectClose(FeatureEncoder.encode(c.raw, params: params), c.encoded, "encode case \(i)")
            policy.update(raw: c.raw, send: c.send, outcome: c.y, at: Date(timeIntervalSince1970: c.tDays * 86_400))
            expectClose(policy.posterior.mean, c.meanAfter, "mean case \(i)")
            expectClose(policy.posterior.precision, c.precisionAfter, "precision case \(i)")
        }
    }

    @Test func quietHours() throws {
        let params = try bundledParams()
        for (minute, expected) in try fixture().quiet {
            #expect(params.isQuiet(minuteOfDay: Int(minute)!) == expected, "minute \(minute)")
        }
        #expect(!params.slotHours.contains(22), "22h slot must not be a candidate")
        #expect(!Constants.notificationFixedHours.contains(22))
    }

    @Test func neverDecidesInQuietHours() throws {
        let params = try bundledParams()
        var policy = ThompsonPolicy(params: params)
        var rng = SystemRandomNumberGenerator()
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 22))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 7, minute: 30))!
        for slot in [night, early] {
            #expect(policy.decide(raw: [:], slotDate: slot, now: slot, calendar: calendar, rng: &rng) == nil)
            #expect(!QuietHours.allows(slot, params: params, calendar: calendar))
        }
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))!
        #expect(policy.decide(raw: [:], slotDate: morning, now: morning, calendar: calendar, rng: &rng) != nil)
    }

    /// Sem params, vale a janela padrão 22h–8h.
    @Test func quietHoursHoldWithoutParams() {
        let at = { (hour: Int, minute: Int) in
            self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour, minute: minute))!
        }
        #expect(!QuietHours.allows(at(7, 59), params: nil, calendar: calendar))
        #expect(QuietHours.allows(at(8, 0), params: nil, calendar: calendar))
        #expect(QuietHours.allows(at(21, 59), params: nil, calendar: calendar))
        #expect(!QuietHours.allows(at(22, 0), params: nil, calendar: calendar))
    }

    private func expectClose(_ a: [Double], _ b: [Double], _ message: String, tolerance: Double = 1e-7) {
        #expect(a.count == b.count, "\(message): count")
        for (u, v) in zip(a, b) {
            #expect(abs(u - v) <= tolerance * max(1, abs(v)), "\(message): \(u) vs \(v)")
        }
    }
}
