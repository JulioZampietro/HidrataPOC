import Foundation
import SwiftData
import Testing
@testable import HidrataPOC

/// `IntakeLogService.record` decide o `origem` de cada registro: se um
/// `NotificationEvent` do mesmo usuário saiu nos últimos
/// `Constants.notificationResponseWindowMinutes`, o gole conta como `"notificacao"`,
/// senão como `"manual"`. É o que permite ao modelo separar "o lembrete causou este
/// gole" de "o usuário beberia de qualquer jeito" — a inferência central do dataset —
/// e não tinha nenhum teste.
///
/// Os pushes ao CloudKit dentro de `record` são best-effort e falham sem iCloud no
/// ambiente de teste, sem afetar o estado local que é o verificado aqui.
@MainActor
struct IntakeOriginTests {
    // Container guardado em propriedade: `ModelContext` referencia o container como
    // `unowned` (mesmo motivo documentado em `InteractionTrackerTests`).
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let userID = "origin-tests"

    init() throws {
        let schema = Schema([UserProfile.self, IntakeLog.self, NotificationEvent.self,
                             UIInteractionEvent.self, DailyGoal.self, SlotDecision.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    private func insertEvent(sentAt: Date, userID overrideUserID: String? = nil) -> NotificationEvent {
        let event = NotificationEvent(
            userID: overrideUserID ?? userID,
            sentAt: sentAt,
            temperaturaC: 25, umidadeRelativa: 0.5, sensacaoTermicaC: 26,
            ocupadoNoMomento: false, densidadeEventosDia: 0,
            deficitAcumuladoML: 1000, tempoDesdeUltimoRegistroMin: 60,
            notificationVariant: .middayNeutral
        )
        context.insert(event)
        return event
    }

    private func record(_ preset: Constants.IntakePreset = .glass) async -> IntakeLog {
        await IntakeLogService.record(
            preset: preset, userID: userID, source: "app", weather: nil,
            context: context, waitForColdStartActivity: false
        ).log
    }

    @Test func semLembreteRecenteOGoleEhManual() async {
        let log = await record()

        #expect(log.origem == OrigemRegistro.manual.rawValue)
        #expect(log.notificationEventID == nil)
    }

    /// Um lembrete dentro da janela de resposta transforma um toque no botão da Home em
    /// `"notificacao"` — mesmo o usuário não tendo tocado na notificação.
    @Test func lembreteDentroDaJanelaMarcaComoNotificacao() async throws {
        let sentAt = Date.now.addingTimeInterval(-2 * 60)
        let event = insertEvent(sentAt: sentAt)

        let log = await record()

        #expect(log.origem == OrigemRegistro.notificacao.rawValue)
        #expect(log.notificationEventID == event.id.uuidString)
        // O evento também passa a constar como "resultou em consumo", com o tempo até agir.
        #expect(event.resultouEmConsumo)
        #expect(event.tempoAteAgirMin == 2)
    }

    @Test func lembreteForaDaJanelaNaoContamina() async {
        let fora = Double(Constants.notificationResponseWindowMinutes + 1) * -60
        let event = insertEvent(sentAt: Date.now.addingTimeInterval(fora))

        let log = await record()

        #expect(log.origem == OrigemRegistro.manual.rawValue)
        #expect(log.notificationEventID == nil)
        #expect(!event.resultouEmConsumo)
    }

    /// O lembrete de outro perfil no mesmo aparelho não pode ser creditado.
    @Test func lembreteDeOutroUsuarioEhIgnorado() async {
        let event = insertEvent(sentAt: Date.now.addingTimeInterval(-60), userID: "outro-usuario")

        let log = await record()

        #expect(log.origem == OrigemRegistro.manual.rawValue)
        #expect(!event.resultouEmConsumo)
    }

    /// Com mais de um lembrete na janela, o crédito vai para o mais recente.
    @Test func comVariosLembretesOMaisRecenteLevaOCredito() async {
        let antigo = insertEvent(sentAt: Date.now.addingTimeInterval(-8 * 60))
        let recente = insertEvent(sentAt: Date.now.addingTimeInterval(-1 * 60))

        let log = await record()

        #expect(log.notificationEventID == recente.id.uuidString)
        #expect(recente.resultouEmConsumo)
        #expect(!antigo.resultouEmConsumo)
    }

    /// O preset define volume e `tipoEntrada` — o rótulo que o botão "Gole" da Home
    /// estava gravando errado (achado A-7).
    @Test func oPresetDefineVolumeERotulo() async {
        let gole = await record(.gole)
        #expect(gole.volumeML == 40)
        #expect(gole.tipoEntrada == "gole")

        let garrafa = await record(.bottle)
        #expect(garrafa.volumeML == 500)
        #expect(garrafa.tipoEntrada == "garrafa")

        let custom = await record(.custom(volumeML: 123))
        #expect(custom.volumeML == 123)
        #expect(custom.tipoEntrada == "personalizado")
    }
}
