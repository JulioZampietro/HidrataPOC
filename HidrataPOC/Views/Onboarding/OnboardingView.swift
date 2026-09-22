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
            let userID = await CloudKitSyncService.shared.resolvedUserID()
            let profile = UserProfile(
                userID: userID,
                idade: values.idade,
                genero: values.genero == .naoInformar ? nil : values.genero.rawValue,
                generoAutoDeclarado: values.normalizedGeneroAutoDeclarado,
                pesoKg: values.pesoKg,
                alturaCm: values.alturaCm,
                fusoHorario: TimeZone.current.identifier,
                metaDiariaML: UserProfile.suggestedGoalML(gender: values.genero.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm),
                customIntakeML: values.customIntakeML
            )
            modelContext.insert(profile)
            try? modelContext.save()
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()

            // Garante autorização de água (no-op se já autorizado via "Preencher com
            // dados do Saúde"; mostra o dialog de água se o usuário foi direto em Concluir).
            _ = await HealthKitService.shared.requestAuthorization()
            if HealthKitService.shared.isAuthorized {
                await HealthKitService.shared.syncFromHealthKit(userID: userID, context: modelContext)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
