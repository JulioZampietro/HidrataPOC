import Foundation
import Testing
@testable import HidrataPOC

/// `totalsByDay` substituiu o filtro por dia dentro de `currentStreak` (que era
/// O(dias × registros)). Como a sequência passou a ser indexada por `startOfDay`, o
/// contrato da agregação e a equivalência com o caminho antigo precisam ficar presos.
@MainActor
struct HydrationMathTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()

    private func log(_ day: Date, hour: Int, ml: Int) -> IntakeLog {
        let timestamp = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day) ?? day
        return IntakeLog(userID: "test", timestamp: timestamp, volumeML: ml,
                         tipoEntrada: "copo", origem: .manual, source: "app", healthKitUUID: "")
    }

    @Test func totalsByDayAgrupaPorInicioDoDia() throws {
        let today = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let logs = [
            log(today, hour: 8, ml: 250),
            log(today, hour: 20, ml: 500),
            log(yesterday, hour: 9, ml: 1000),
        ]

        let totals = HydrationMath.totalsByDay(logs, calendar: calendar)

        #expect(totals[today] == 750)
        #expect(totals[yesterday] == 1000)
        // Dia sem registro não aparece no dicionário — quem lê precisa usar `?? 0`.
        #expect(totals[try #require(calendar.date(byAdding: .day, value: -2, to: today))] == nil)
    }

    /// A agregação tem de dar o mesmo total que o `totalML` original, que compara datas
    /// com `isDate(inSameDayAs:)` em vez de usar a chave do dicionário.
    @Test func totalsByDayConcordaComTotalML() throws {
        let today = calendar.startOfDay(for: .now)
        let logs = (0..<5).map { log(today, hour: 7 + $0 * 3, ml: 100 * ($0 + 1)) }

        let viaDicionario = HydrationMath.totalsByDay(logs, calendar: calendar)[today] ?? 0
        let viaFiltro = HydrationMath.totalML(logs, on: today, calendar: calendar)

        #expect(viaDicionario == viaFiltro)
        #expect(viaDicionario == 1500)
    }

    /// As duas assinaturas de `currentStreak` (lista crua e totais pré-agregados) têm
    /// de devolver o mesmo número — é a equivalência que a refatoração assume.
    @Test func asDuasVariantesDeStreakConcordam() throws {
        let today = calendar.startOfDay(for: .now)
        var logs: [IntakeLog] = []
        for offset in 0..<4 {
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            logs.append(log(day, hour: 10, ml: 2000))
        }
        let goal: (Date) -> Int = { _ in 2000 }

        let viaLista = HydrationMath.currentStreak(logs, goalML: goal, calendar: calendar, now: today)
        let viaTotais = HydrationMath.currentStreak(
            totalsByDay: HydrationMath.totalsByDay(logs, calendar: calendar),
            goalML: goal, calendar: calendar, now: today
        )

        #expect(viaLista == viaTotais)
        #expect(viaLista == 4)
    }

    /// A sequência caminha para trás somando -1 dia; num fuso com horário de verão isso
    /// pode cair às 23h do dia anterior, uma chave que não existe em `totalsByDay`. O
    /// `startOfDay` no laço é o que impede a sequência de quebrar nessa virada.
    @Test func streakAtravessaViradaDeHorarioDeVerao() throws {
        var saoPaulo = Calendar(identifier: .gregorian)
        saoPaulo.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        // 2018-11-04: último início de horário de verão no Brasil (relógio foi de 00h para 01h).
        let afterChange = try #require(DateComponents(calendar: saoPaulo, year: 2018, month: 11, day: 6).date)

        var logs: [IntakeLog] = []
        for offset in 0..<5 {
            let day = try #require(saoPaulo.date(byAdding: .day, value: -offset, to: afterChange))
            let timestamp = saoPaulo.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            logs.append(IntakeLog(userID: "test", timestamp: timestamp, volumeML: 2000,
                                  tipoEntrada: "copo", origem: .manual, source: "app", healthKitUUID: ""))
        }

        let streak = HydrationMath.currentStreak(
            logs, goalML: { _ in 2000 }, calendar: saoPaulo, now: afterChange
        )
        #expect(streak == 5)
    }

    /// A maior sequência é a que libera os minijogos pra sempre: tem de achar uma sequência
    /// antiga, já quebrada, mesmo que a atual seja menor.
    @Test func longestStreakAchaSequenciaAntigaJaQuebrada() throws {
        let today = calendar.startOfDay(for: .now)
        // Bateu a meta há 10…6 dias (5 seguidos), falhou há 5 e 4 (um pouco abaixo da meta),
        // e bateu de novo há 3…1 (3 seguidos). Hoje ainda não bateu.
        var logs: [IntakeLog] = []
        for offset in 1...10 {
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            logs.append(log(day, hour: 10, ml: (offset == 4 || offset == 5) ? 1500 : 2000))
        }
        let totals = HydrationMath.totalsByDay(logs, calendar: calendar)
        let goal: (Date) -> Int = { _ in 2000 }

        #expect(HydrationMath.currentStreak(totalsByDay: totals, goalML: goal, calendar: calendar, now: today) == 3)
        #expect(HydrationMath.longestStreak(totalsByDay: totals, goalML: goal, calendar: calendar) == 5)
    }

    @Test func longestStreakSemMetaBatidaEZero() {
        let today = calendar.startOfDay(for: .now)
        let totals = HydrationMath.totalsByDay([log(today, hour: 10, ml: 500)], calendar: calendar)
        #expect(HydrationMath.longestStreak(totalsByDay: totals, goalML: { _ in 2000 }, calendar: calendar) == 0)
    }
}
