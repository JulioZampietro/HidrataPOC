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
                onSave: save
            )
        }
    }

    private func save(_ values: ProfileFormValues) {
        Task {
            let userID = await CloudKitSyncService.shared.resolvedUserID()
            let profile = UserProfile(
                userID: userID,
                idade: values.idade,
                genero: values.genero == .naoInformar ? nil : values.genero.rawValue,
                pesoKg: values.pesoKg,
                alturaCm: values.alturaCm,
                fusoHorario: TimeZone.current.identifier,
                metaDiariaML: values.metaDiariaML,
                customIntakeML: values.customIntakeML
            )
            modelContext.insert(profile)
            try? modelContext.save()
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
