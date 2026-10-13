import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ProfileFormView(
                title: "Bem-vindo(a)",
                confirmLabel: "Concluir",
                initialValues: .new,
                showsCustomIntakeField: true,
                onSave: save
            )
        }
    }

    private func save(_ values: ProfileFormValues) {
        Task {
            // A restauração do iCloud pode ter terminado depois do usuário pular a
            // espera — não cria um segundo perfil por cima do restaurado.
            guard ((try? modelContext.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) == 0 else { return }
            let userID = await CloudKitSyncService.shared.resolvedUserID()
            let profile = UserProfile(
                userID: userID,
                idade: values.idade,
                genero: values.genero?.rawValue,
                pesoKg: values.pesoKg,
                alturaCm: values.alturaCm,
                fusoHorario: TimeZone.current.identifier,
                metaDiariaML: UserProfile.suggestedGoalML(gender: values.genero?.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm),
                customIntakeML: values.customIntakeML
            )
            modelContext.insert(profile)
            try? modelContext.save()
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }
}

/// Shown on first launch while `CloudKitSyncService.syncPrivateDatabase` looks for an
/// existing backup. CloudKit fails fast offline, but a slow network could hang here,
/// so a skip button appears after a few seconds.
struct ICloudRestoreView: View {
    let onSkip: () -> Void
    @State private var showsSkip = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Procurando seus dados no iCloud…")
                .font(.headline)
                .multilineTextAlignment(.center)
            if showsSkip {
                Button("Começar do zero", action: onSkip)
                    .buttonStyle(.bordered)
                    .transition(.opacity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showsSkip = true }
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
