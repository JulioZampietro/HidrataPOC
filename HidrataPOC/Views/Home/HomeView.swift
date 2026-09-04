import SwiftData
import SwiftUI

struct HomeView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var isLogging = false
    @State private var pendingPreset: Constants.IntakePreset?
    @State private var pendingDeleteLog: IntakeLog?

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }

    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }
    private var progress: Double {
        guard profile.metaDiariaML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(profile.metaDiariaML))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    progressRing

                    VStack(spacing: 12) {
                        Text("Registrar consumo")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            intakeButton(.glass)
                            intakeButton(.bottle)
                            intakeButton(.gallon)
                            intakeButton(.custom(volumeML: profile.customIntakeML))
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
            .alert(
                pendingPreset.map { "Registrar \($0.label.lowercased())?" } ?? "",
                isPresented: isPresentingPresetConfirm,
                presenting: pendingPreset
            ) { preset in
                Button("Registrar") { logIntake(preset) }
                Button("Cancelar", role: .cancel) {}
            } message: { preset in
                Text("\(preset.volumeML) mL serão adicionados ao seu consumo de hoje.")
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
        }
    }

    private var isPresentingPresetConfirm: Binding<Bool> {
        Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })
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
                    Text("meta: \(profile.metaDiariaML) mL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consumedToday) de \(profile.metaDiariaML) mililitros consumidos hoje")
    }

    private func intakeButton(_ preset: Constants.IntakePreset) -> some View {
        Button {
            pendingPreset = preset
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
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HomeView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
