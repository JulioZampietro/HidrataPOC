import SwiftData
import SwiftUI

struct HomeView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var isLogging = false
    @State private var pendingDeleteLog: IntakeLog?
    @State private var isEditingCustomAmount = false
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    progressRing
                    weatherDiagnostic

                    VStack(spacing: 12) {
                        Text("Registrar consumo")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            intakeButton(.glass)
                            intakeButton(.bottle)
                            intakeButton(.gallon)
                            customIntakeButton
                        }
                    }
                    .padding(.horizontal)

                    if !todayLogs.isEmpty {
                        recentLogsList
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Hidratação")
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
        }
    }

    private var isPresentingDeleteConfirm: Binding<Bool> {
        Binding(get: { pendingDeleteLog != nil }, set: { if !$0 { pendingDeleteLog = nil } })
    }

    private var progressRing: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.blue.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)

                VStack(spacing: 4) {
                    Text("\(consumedToday) mL")
                        .font(.title.bold())
                    Text("meta: \(effectiveGoalML) mL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let ctx = tempContext, ctx.adjustmentML > 0 {
                        Text("+\(ctx.adjustmentML) mL por calor")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 180, height: 180)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consumedToday) de \(effectiveGoalML) mililitros consumidos hoje")
    }

    /// Diagnostic row so a tester can see at a glance whether WeatherKit is actually
    /// returning data (vs. silently failing — see `WeatherContextService`'s
    /// location/network error logging) — not part of the product spec, just a visible
    /// health check.
    private var weatherDiagnostic: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.medium")
            if isLoadingWeather {
                Text("Consultando clima…")
            } else if let weather {
                Text("\(weather.temperaturaC.formatted(.number.precision(.fractionLength(1))))°C · \(Int(weather.umidadeRelativa * 100))% umidade")
            } else {
                Text("Clima indisponível (WeatherKit)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func loadWeather() async {
        weather = await WeatherContextService.shared.currentContext()
        isLoadingWeather = false
    }

    private func intakeButton(_ preset: Constants.IntakePreset) -> some View {
        Button {
            logIntake(preset)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: iconName(for: preset))
                    .font(.title2)
                Text(preset.label)
                    .font(.caption.bold())
                Text("\(preset.volumeML) mL")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLogging)
    }

    /// The 4th quick-log tile, with a small pencil button overlaid in its top-trailing
    /// corner (its own tap target) to open `CustomIntakeEditorView`. Editing this
    /// volume now happens only here — it's no longer part of the profile form.
    private var customIntakeButton: some View {
        ZStack(alignment: .topTrailing) {
            intakeButton(.custom(volumeML: profile.customIntakeML))

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

    private func iconName(for preset: Constants.IntakePreset) -> String {
        switch preset {
        case .glass: return "waterbottle"
        case .bottle: return "waterbottle.fill"
        case .gallon: return "cylinder.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    private var recentLogsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hoje")
                .font(.headline)
            ForEach(todayLogs.sorted { $0.timestamp > $1.timestamp }) { log in
                HStack {
                    Text(log.tipoEntrada.capitalized)
                    Spacer()
                    Text("\(log.volumeML) mL")
                        .foregroundStyle(.secondary)
                    Text(log.timestamp, style: .time)
                        .foregroundStyle(.secondary)
                    Button {
                        pendingDeleteLog = log
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                    .accessibilityLabel("Excluir registro de \(log.tipoEntrada), \(log.volumeML) mililitros")
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
    }

    private func logIntake(_ preset: Constants.IntakePreset) {
        isLogging = true
        Task {
            await NotificationScheduler.shared.recordManualIntake(preset: preset, userID: profile.userID, context: modelContext)
            isLogging = false
        }
    }

    private func deleteLog(_ log: IntakeLog) {
        Task {
            await NotificationScheduler.shared.deleteIntake(log, context: modelContext)
        }
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

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HomeView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
