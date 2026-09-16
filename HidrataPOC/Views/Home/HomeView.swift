import SwiftData
import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)
private let appBackground = Color(red: 0.906, green: 0.937, blue: 0.961)

struct HomeView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var isLogging = false
    @State private var pendingDeleteLog: IntakeLog?
    @State private var isEditingCustomAmount = false
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
        let cal = Calendar.current
        var count = 0
        var checkDate = cal.startOfDay(for: .now)
        for _ in 0..<365 {
            let dayTotal = allLogs
                .filter { $0.userID == profile.userID && cal.isDate($0.timestamp, inSameDayAs: checkDate) }
                .reduce(0) { $0 + $1.volumeML }
            if dayTotal >= profile.metaDiariaML {
                count += 1
                checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        return count
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    mascotPlaceholder

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
        }
        .sheet(isPresented: $showSiriTutorial) { SiriTutorialView() }
        .sheet(isPresented: $showActionButtonTutorial) { ActionButtonTutorialView() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Button {
                // TODO: ajuda / info
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
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
            .background(.white, in: Capsule())
        }
    }

    private var mascotPlaceholder: some View {
        ZStack {
            Ellipse()
                .fill(accentBlue.opacity(0.15))
                .frame(width: 220, height: 150)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
        }
        .frame(height: 190)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let barWidth = max(geo.size.width * progress, 56)
            let borderDepth: CGFloat = 4

            ZStack(alignment: .leading) {
                // track afundado
                Capsule()
                    .fill(Color(red: 0.75, green: 0.78, blue: 0.82))
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
                    .background(Circle().fill(.white))
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
        case .gallon: return "cylinder.fill"
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
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HomeView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
