import SwiftData
import SwiftUI


struct HealthConnectView: View {
    let profile: UserProfile

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
        TankSheet {
            VStack(spacing: 20) {
                CurrentMascotTankHeader(
                    title: "App Saúde",
                    subtitle: "Seu consumo de água, sincronizado com o resto do seu histórico de saúde."
                )

                VStack(alignment: .leading, spacing: 16) {
                    statusRow
                    if isAuthorized { connectedSection }
                    else if service.isAvailable { connectSection }
                    else { unavailableSection }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .task { isAuthorized = service.isAuthorized }
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isAuthorized ? Color.appSuccess : Color.appWarning)
                .frame(width: 7, height: 7)
            Text(isAuthorized ? "Conectado" : "Não conectado")
                .font(AppFont.subheadline)
                .foregroundStyle(Color.appSecondary)
        }
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoCard([
                ("arrow.down.circle.fill", "Importa água registrada em outros apps (MyFitnessPal, Apple Watch…)"),
                ("arrow.up.circle.fill", "Envia cada gole registrado aqui para o seu histórico no Saúde"),
            ])

            Button {
                Task { await authorize() }
            } label: {
                Text("Conectar ao Saúde")
                    .font(AppFont.calloutStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.gradientProminent)
        }
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoCard([
                ("checkmark.circle.fill", "Seus registros de água são enviados automaticamente ao Saúde"),
                ("arrow.triangle.2.circlepath", "Água adicionada por outros apps é importada ao abrir o Gole"),
            ])

            if let lastSync = lastSyncFormatted {
                Text("Última sincronização \(lastSync)")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.appSecondary)
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
                            .font(AppFont.calloutStrong)
                    } else {
                        Text("Sincronizar agora")
                            .font(AppFont.calloutStrong)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.gradientProminent)
            .disabled(isSyncing || justSynced)
        }
    }

    private var unavailableSection: some View {
        Text("O app Saúde não está disponível neste dispositivo.")
            .font(AppFont.subheadline)
            .foregroundStyle(Color.appSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoCard(_ rows: [(icon: String, text: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.subheadline)
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 20)
                            .padding(.top, 1)
                        Text(row.text)
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.appSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if index < rows.count - 1 {
                        Divider().padding(.leading, 18 + 20 + 12)
                    }
                }
            }
        }
        .panelBackground()
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
