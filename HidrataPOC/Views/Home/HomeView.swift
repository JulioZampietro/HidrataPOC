import SwiftData
import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

struct HomeView: View {
    let profile: UserProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var isLogging = false
    @State private var pendingDeleteLog: IntakeLog?
    @State private var isEditingCustomAmount = false
    @State private var showHelp = false
    @State private var showSiriTutorial = false
    @State private var showActionButtonTutorial = false
    @State private var weather: WeatherContext?
    @State private var isLoadingWeather = true
    @State private var tempContext: TemperatureAdjustmentContext?

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }

    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }

    private var effectiveGoalML: Int {
        profile.metaDiariaML + (tempContext?.adjustmentML ?? 0)
    }

    private var progress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(effectiveGoalML))
    }

    private var streak: Int {
        HydrationMath.currentStreak(allLogs.filter { $0.userID == profile.userID }, metaDiariaML: profile.metaDiariaML)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.screenBackground(for: colorScheme), location: 0.0),
                    .init(color: AppTheme.screenBackground(for: colorScheme), location: 0.7),
                    .init(color: .orange.opacity(0.4), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    topSection

                    progressBar
                        .padding(.horizontal, 20)

                    intakeGrid
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
        }
        .task { await loadWeather() }
        .onAppear {
            guard tempContext == nil else { return }
            Task {
                tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
            }
        }
        .confirmationDialog(
            "Excluir este registro?",
            isPresented: isPresentingDeleteConfirm,
            presenting: pendingDeleteLog
        ) { log in
            Button("Excluir", role: .destructive) { deleteLog(log) }
            Button("Cancelar", role: .cancel) {}
        } message: { log in
            Text("\(log.tipoEntrada.capitalized) · \(log.volumeML) mL será removido do seu histórico e da base de dados.")
        }
        .sheet(isPresented: $isEditingCustomAmount) {
            CustomIntakeEditorView(initialValueML: profile.customIntakeML, onSave: saveCustomAmount)
                .trackSheetLifecycle(.customAmountEditor, screen: .home, userID: profile.userID)
        }
        .sheet(isPresented: $showHelp) { HomeHelpView() }
        .sheet(isPresented: $showSiriTutorial) { SiriTutorialView() }
        .sheet(isPresented: $showActionButtonTutorial) { ActionButtonTutorialView() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Button {
                InteractionTracker.log("home_help_tap", screen: .home, userID: profile.userID, context: modelContext)
                showHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(accentBlue)
                Text("\(streak)")
                    .font(.custom("Nunito", size: 15).bold())
                Text("dias")
                    .font(.custom("Nunito", size: 15))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
    }

    private let mascotHeight: CGFloat = 190
    private let headerRowHeight: CGFloat = 48 // botão de 40 pt + 8 pt de respiro no topo

    private var topSection: some View {
        // Recipiente: vai do topo da tela até logo acima da barra de progresso e
        // enche de água conforme o progresso do dia.
        // O cabeçalho fica fora do conteúdo da água: a refração achata o conteúdo
        // numa imagem e o vidro dos botões deixa de enxergar o fundo (fica escuro).
        VStack(spacing: 20) {
            Color.clear.frame(height: headerRowHeight)
            mascotPlaceholder
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .waterContainer(
            level: progress,
            in: UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous),
            bleedsIntoTopSafeArea: true
        )
        .overlay(alignment: .top) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    private var mascotPlaceholder: some View {
        Image(AppTheme.mascotImageName(for: progress))
            .resizable()
            .scaledToFit()
            .frame(height: mascotHeight)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let barWidth = max(geo.size.width * progress, 56)
            let borderDepth: CGFloat = 4

            ZStack(alignment: .leading) {
                // track afundado
                Capsule()
                    .fill(AppTheme.progressTrack(for: colorScheme))
                    .frame(height: 52)

                // borda inferior do azul (efeito elevado)
                Capsule()
                    .fill(Color(red: 0.18, green: 0.35, blue: 0.56))
                    .frame(width: barWidth, height: 52)
                    .offset(y: borderDepth)
                    .animation(.easeOut(duration: 0.4), value: progress)

                // preenchimento azul
                Capsule()
                    .fill(accentBlue)
                    .frame(width: barWidth, height: 52)
                    .animation(.easeOut(duration: 0.4), value: progress)

                Text("\(consumedToday) mL / \(effectiveGoalML) mL")
                    .font(.custom("Nunito", size: 15).weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.leading, 18)
            }
        }
        .frame(height: 52 + 4)
    }

    private var intakeGrid: some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                goleCard
                intakeCard(.glass)
                intakeCard(.bottle)
                customIntakeCard
            }
        }
    }

    private var goleCard: some View {
        Button { logIntake(.custom(volumeML: 40)) } label: {
            IntakeCardContent(
                icon: "drop.fill",
                title: "Gole",
                subtitle: "40 mL"
            )
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
    }

    private func intakeCard(_ preset: Constants.IntakePreset) -> some View {
        Button { logIntake(preset) } label: {
            IntakeCardContent(
                icon: iconName(for: preset),
                title: preset.label,
                subtitle: "\(preset.volumeML) mL"
            )
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
    }

    private var customIntakeCard: some View {
        ZStack(alignment: .topTrailing) {
            Button { logIntake(.custom(volumeML: profile.customIntakeML)) } label: {
                IntakeCardContent(
                    icon: "plus",
                    title: "Outro",
                    subtitle: "\(profile.customIntakeML) mL"
                )
            }
            .buttonStyle(.plain)
            .disabled(isLogging)

            Button {
                isEditingCustomAmount = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(accentBlue)
            }
            .padding(6)
            .accessibilityLabel("Editar volume do botão personalizado")
        }
    }

    // MARK: - Helpers

    private var isPresentingDeleteConfirm: Binding<Bool> {
        Binding(get: { pendingDeleteLog != nil }, set: { if !$0 { pendingDeleteLog = nil } })
    }

    private func iconName(for preset: Constants.IntakePreset) -> String {
        switch preset {
        case .glass: return "waterbottle"
        case .bottle: return "waterbottle.fill"
        case .gole: return "drop.fill"
        case .custom: return "plus"
        }
    }

    private func loadWeather() async {
        weather = await WeatherContextService.shared.currentContext()
        isLoadingWeather = false
    }

    private func logIntake(_ preset: Constants.IntakePreset) {
        isLogging = true
        Task {
            await NotificationScheduler.shared.recordManualIntake(preset: preset, userID: profile.userID, context: modelContext)
            isLogging = false
        }
    }

    private func deleteLog(_ log: IntakeLog) {
        Task { await NotificationScheduler.shared.deleteIntake(log, context: modelContext) }
    }

    private func saveCustomAmount(_ newValue: Int) {
        profile.customIntakeML = newValue
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
        InteractionTracker.log("custom_amount_editor_save", screen: .home, userID: profile.userID, metadata: ["amountML": "\(newValue)"], context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
            await LiveActivityManager.shared.updateCustomAmount(newValue)
        }
    }
}

// MARK: - IntakeCardContent

struct IntakeCardContent: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accentBlue)
                .padding(.bottom, 28)

            Text(title)
                .font(.custom("Nunito", size: 17).weight(.heavy))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HomeView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
