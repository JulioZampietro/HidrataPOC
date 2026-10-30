import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Cumpre as duas promessas do `ConsentView`: ver/exportar tudo que foi coletado e
/// apagar tudo — neste aparelho, na base de pesquisa do iCloud e no app Saúde.
///
/// A exportação é local (nada sai do aparelho sem o usuário escolher para onde);
/// a exclusão é intencionalmente irreversível e pede confirmação explícita.
struct MyDataView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var counts: DataCounts?
    @State private var export: DataExportFile?
    @State private var isConfirmingDelete = false
    @State private var deletion: DeletionState = .idle

    private enum DeletionState: Equatable {
        case idle
        case running
        /// `remoteComplete == false`: o local foi apagado, mas algo não chegou ao
        /// iCloud/Saúde — o usuário precisa saber disso.
        case done(remoteComplete: Bool)
    }

    var body: some View {
        TankSheet {
            VStack(spacing: 20) {
                CurrentMascotTankHeader(
                    title: "Meus dados",
                    subtitle: "Tudo que o app coletou de você, para ver, levar embora ou apagar."
                )

                VStack(alignment: .leading, spacing: 16) {
                    collectedSection
                    exportSection
                    deleteSection
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .task { counts = DataCounts(context: modelContext) }
    }

    // MARK: - O que existe

    private var collectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLETADO ATÉ AGORA")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.appAccentText)
                .tracking(1)

            VStack(spacing: 0) {
                countRow("Registros de consumo", counts?.intakeLogs)
                Divider().padding(.leading, 18)
                countRow("Lembretes enviados", counts?.notificationEvents)
                Divider().padding(.leading, 18)
                countRow("Metas diárias", counts?.dailyGoals)
                Divider().padding(.leading, 18)
                countRow("Decisões de horário", counts?.slotDecisions)
                Divider().padding(.leading, 18)
                countRow("Interações na tela", counts?.interactionEvents)
            }
            .panelBackground()
        }
    }

    private func countRow(_ label: String, _ value: Int?) -> some View {
        HStack {
            Text(label)
                .font(AppFont.callout)
                .foregroundStyle(.primary)
            Spacer()
            Text(value.map(String.init) ?? "—")
                .font(AppFont.calloutStrong)
                .foregroundStyle(Color.appSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Exportar

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let export {
                ShareLink(item: export, preview: SharePreview("Meus dados do Gole")) {
                    Text("Exportar meus dados")
                        .font(AppFont.calloutStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.gradientProminent)
                .simultaneousGesture(TapGesture().onEnded { Haptic.tap.play() })
            } else {
                Button {
                    Haptic.tap.play()
                    export = DataExportFile(context: modelContext)
                } label: {
                    Text("Preparar exportação")
                        .font(AppFont.calloutStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.gradientProminent)
            }

            Text("Um arquivo JSON com seu perfil, cada registro de consumo, cada lembrete, as metas diárias, as decisões de horário e suas interações com o app.")
                .font(AppFont.caption)
                .foregroundStyle(Color.appSecondary)
        }
    }

    // MARK: - Apagar

    @ViewBuilder
    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch deletion {
            case .idle:
                Button(role: .destructive) {
                    Haptic.warning.play()
                    isConfirmingDelete = true
                } label: {
                    Text("Apagar todos os meus dados")
                        .font(AppFont.calloutStrong)
                        .foregroundStyle(Color.appDestructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Text("Remove tudo deste aparelho, da base de pesquisa no iCloud e as amostras de água que este app escreveu no Saúde. Não dá para desfazer.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.appSecondary)

            case .running:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Apagando…")
                        .font(AppFont.callout)
                        .foregroundStyle(Color.appSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

            case .done(let remoteComplete):
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        remoteComplete ? "Tudo apagado." : "Apagado neste aparelho.",
                        systemImage: remoteComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(remoteComplete ? Color.appSuccess : Color.appWarning)

                    if !remoteComplete {
                        Text("Parte dos dados não pôde ser removida do iCloud agora (provavelmente sem conexão). O app tentará de novo automaticamente.")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog(
            "Apagar todos os seus dados?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Apagar tudo", role: .destructive) {
                Task { await deleteEverything() }
            }
            Button("Cancelar", role: .cancel) { Haptic.dismiss.play() }
        } message: {
            Text("Seu perfil, seu histórico de consumo e todos os registros de pesquisa serão removidos deste aparelho e do iCloud, junto com a água que o Gole escreveu no app Saúde. Não dá para desfazer.")
        }
    }

    /// Ordem importa: o iCloud e o Saúde precisam das linhas locais para saber o que
    /// apagar, então o banco local é o último a cair.
    private func deleteEverything() async {
        deletion = .running

        let healthOK = await HealthKitService.shared.deleteAllOurSamples()
        let cloudOK = await CloudKitSyncService.shared.deleteAllRemoteRecords(context: modelContext)

        for log in (try? modelContext.fetch(FetchDescriptor<IntakeLog>())) ?? [] { modelContext.delete(log) }
        for event in (try? modelContext.fetch(FetchDescriptor<NotificationEvent>())) ?? [] { modelContext.delete(event) }
        for event in (try? modelContext.fetch(FetchDescriptor<UIInteractionEvent>())) ?? [] { modelContext.delete(event) }
        for goal in (try? modelContext.fetch(FetchDescriptor<DailyGoal>())) ?? [] { modelContext.delete(goal) }
        for decision in (try? modelContext.fetch(FetchDescriptor<SlotDecision>())) ?? [] { modelContext.delete(decision) }
        for profile in (try? modelContext.fetch(FetchDescriptor<UserProfile>())) ?? [] { modelContext.delete(profile) }
        try? modelContext.save()

        AppStateReset.eraseLocalState()
        WidgetSync.reloadWaterTank()
        await IntakeLogService.endLiveActivity(waitForColdStart: false)

        Haptic.success.play()
        deletion = .done(remoteComplete: healthOK && cloudOK)
        counts = DataCounts(context: modelContext)
    }
}

// MARK: - Contagens

private struct DataCounts {
    let intakeLogs: Int
    let notificationEvents: Int
    let dailyGoals: Int
    let slotDecisions: Int
    let interactionEvents: Int

    @MainActor
    init(context: ModelContext) {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        intakeLogs = count(IntakeLog.self)
        notificationEvents = count(NotificationEvent.self)
        dailyGoals = count(DailyGoal.self)
        slotDecisions = count(SlotDecision.self)
        interactionEvents = count(UIInteractionEvent.self)
    }
}

// MARK: - Exportação

/// O JSON exportado. `Transferable` para o `ShareLink` entregar como arquivo, no mesmo
/// padrão de `SharePNG` em `ShareProgressView`.
struct DataExportFile: Transferable {
    let data: Data
    let fileName: String

    @MainActor
    init(context: ModelContext) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let snapshot = DataExportSnapshot(context: context)
        data = (try? encoder.encode(snapshot)) ?? Data("{}".utf8)

        let stamp = DailyGoal.dayKey(for: .now)
        fileName = "gole-meus-dados-\(stamp).json"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

/// Espelha o que existe no banco local, com os mesmos nomes de campo dos modelos, para
/// o arquivo ser legível por quem exportou sem precisar de um dicionário à parte.
private struct DataExportSnapshot: Encodable {
    struct Profile: Encodable {
        let userID: String
        let idade: Int
        let genero: String?
        let pesoKg: Double
        let alturaCm: Double
        let fusoHorario: String
        let metaDiariaML: Int
        let customIntakeML: Int
        let criadoEm: Date
        let atualizadoEm: Date
    }

    struct Intake: Encodable {
        let id: UUID
        let timestamp: Date
        let volumeML: Int
        let tipoEntrada: String
        let origem: String
        let source: String
        let temperaturaC: Double?
        let umidadeRelativa: Double?
        let sensacaoTermicaC: Double?
    }

    struct Reminder: Encodable {
        let id: UUID
        let sentAt: Date
        let notificationVariant: String
        let statusInteracao: String?
        let tempoAteAgirMin: Int?
        let resultouEmConsumo: Bool
        let temperaturaC: Double
        let umidadeRelativa: Double
        let deficitAcumuladoML: Int
    }

    struct Goal: Encodable {
        let dayKey: String
        let baseGoalML: Int
        let adjustmentML: Int
    }

    struct Decision: Encodable {
        let slotFiresAt: Date
        let slotHour: Int
        let acao: String
        let propensity: Double
        let intakeInWindow: Bool?
    }

    struct Interaction: Encodable {
        let timestamp: Date
        let eventName: String
        let screen: String
        let metadataJSON: String?
    }

    let exportadoEm: Date
    let perfil: Profile?
    let registrosDeConsumo: [Intake]
    let lembretes: [Reminder]
    let metasDiarias: [Goal]
    let decisoesDeHorario: [Decision]
    let interacoes: [Interaction]

    @MainActor
    init(context: ModelContext) {
        exportadoEm = .now

        let profileRow = try? context.fetch(FetchDescriptor<UserProfile>()).first
        perfil = profileRow.map {
            Profile(userID: $0.userID, idade: $0.idade, genero: $0.genero, pesoKg: $0.pesoKg,
                    alturaCm: $0.alturaCm, fusoHorario: $0.fusoHorario, metaDiariaML: $0.metaDiariaML,
                    customIntakeML: $0.customIntakeML, criadoEm: $0.criadoEm, atualizadoEm: $0.atualizadoEm)
        }

        let logs = (try? context.fetch(FetchDescriptor<IntakeLog>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        registrosDeConsumo = logs.map {
            Intake(id: $0.id, timestamp: $0.timestamp, volumeML: $0.volumeML, tipoEntrada: $0.tipoEntrada,
                   origem: $0.origem, source: $0.source, temperaturaC: $0.temperaturaC,
                   umidadeRelativa: $0.umidadeRelativa, sensacaoTermicaC: $0.sensacaoTermicaC)
        }

        let events = (try? context.fetch(FetchDescriptor<NotificationEvent>(sortBy: [SortDescriptor(\.sentAt)]))) ?? []
        lembretes = events.map {
            Reminder(id: $0.id, sentAt: $0.sentAt, notificationVariant: $0.notificationVariant,
                     statusInteracao: $0.statusInteracao, tempoAteAgirMin: $0.tempoAteAgirMin,
                     resultouEmConsumo: $0.resultouEmConsumo, temperaturaC: $0.temperaturaC,
                     umidadeRelativa: $0.umidadeRelativa, deficitAcumuladoML: $0.deficitAcumuladoML)
        }

        let goals = (try? context.fetch(FetchDescriptor<DailyGoal>(sortBy: [SortDescriptor(\.dayKey)]))) ?? []
        metasDiarias = goals.map { Goal(dayKey: $0.dayKey, baseGoalML: $0.baseGoalML, adjustmentML: $0.adjustmentML) }

        let decisions = (try? context.fetch(FetchDescriptor<SlotDecision>(sortBy: [SortDescriptor(\.slotFiresAt)]))) ?? []
        decisoesDeHorario = decisions.map {
            Decision(slotFiresAt: $0.slotFiresAt, slotHour: $0.slotHour, acao: $0.actionRaw,
                     propensity: $0.propensity, intakeInWindow: $0.intakeInWindow)
        }

        let interactions = (try? context.fetch(FetchDescriptor<UIInteractionEvent>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        interacoes = interactions.map {
            Interaction(timestamp: $0.timestamp, eventName: $0.eventName, screen: $0.screen, metadataJSON: $0.metadataJSON)
        }
    }
}
