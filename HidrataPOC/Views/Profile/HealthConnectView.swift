import SwiftData
import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

struct HealthConnectView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]

    @State private var isAuthorized = false
    @State private var isSyncing = false
    @State private var justSynced = false

    private let service = HealthKitService.shared

    private var lastSyncFormatted: String? {
        guard let date = service.lastSyncDate else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    healthIcon
                    statusSection
                    if isAuthorized { connectedSection }
                    else if service.isAvailable { connectSection }
                    else { unavailableSection }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .appScreenBackground()
            .navigationTitle("Saúde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                }
            }
            .task { isAuthorized = service.isAuthorized }
        }
    }

    // MARK: - Subviews

    private var healthIcon: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.12))
                .frame(width: 88, height: 88)
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(.pink)
        }
    }

    private var statusSection: some View {
        VStack(spacing: 6) {
            Text("App Saúde")
                .font(.custom("Nunito", size: 22).weight(.heavy))

            HStack(spacing: 6) {
                Circle()
                    .fill(isAuthorized ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isAuthorized ? "Conectado" : "Não conectado")
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                infoRow(icon: "arrow.down.circle.fill", color: .blue,
                        text: "Importa água registrada em outros apps (MyFitnessPal, Apple Watch…)")
                infoRow(icon: "arrow.up.circle.fill", color: accentBlue,
                        text: "Envia cada gole registrado aqui para o seu histórico no Saúde")
            }

            Button {
                Task { await authorize() }
            } label: {
                Text("Conectar ao Saúde")
                    .font(.custom("Nunito", size: 16).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(accentBlue)
        }
    }

    private var connectedSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                infoRow(icon: "checkmark.circle.fill", color: .green,
                        text: "Seus registros de água são enviados automaticamente ao Saúde")
                infoRow(icon: "arrow.triangle.2.circlepath", color: accentBlue,
                        text: "Água adicionada por outros apps é importada ao abrir o Hidrата")
            }

            if let lastSync = lastSyncFormatted {
                Text("Última sincronização \(lastSync)")
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await syncNow() }
            } label: {
                Group {
                    if isSyncing {
                        ProgressView()
                            .tint(.white)
                    } else if justSynced {
                        Label("Sincronizado", systemImage: "checkmark")
                            .font(.custom("Nunito", size: 16).weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("Sincronizar agora")
                            .font(.custom("Nunito", size: 16).weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(isSyncing ? Color.gray : accentBlue)
            .disabled(isSyncing || justSynced)
        }
    }

    private var unavailableSection: some View {
        Text("O app Saúde não está disponível neste dispositivo.")
            .font(.custom("Nunito", size: 15))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.custom("Nunito", size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    private func authorize() async {
        let granted = await service.requestAuthorization()
        isAuthorized = granted
        if granted {
            isSyncing = true
            // Backfill: envia histórico existente do app para o Health
            let userLogs = allLogs.filter { $0.userID == profile.userID }
            await service.backfill(logs: userLogs)
            // Importa registros que já existiam no Health de outros apps
            await service.syncFromHealthKit(userID: profile.userID, context: modelContext)
            isSyncing = false
            justSynced = true
            try? await Task.sleep(for: .seconds(2))
            justSynced = false
        }
    }

    private func syncNow() async {
        isSyncing = true
        let userLogs = allLogs.filter { $0.userID == profile.userID }
        await service.backfill(logs: userLogs)
        await service.syncFromHealthKit(userID: profile.userID, context: modelContext)
        isSyncing = false
        justSynced = true
        try? await Task.sleep(for: .seconds(2))
        justSynced = false
    }
}
