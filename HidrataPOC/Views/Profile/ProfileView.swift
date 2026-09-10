import SwiftData
import SwiftUI

struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var isEditing = false

    private var myLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID }
    }

    private var dailyTotals: [(day: Date, totalML: Int)] {
        HydrationMath.dailyTotals(myLogs, days: 7)
    }

    private var generoDisplay: String {
        let genero = Genero(rawValue: profile.genero ?? Genero.naoInformar.rawValue) ?? .naoInformar
        if genero == .autoDeclarado, let texto = profile.generoAutoDeclarado, !texto.isEmpty {
            return texto
        }
        return genero.label
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Consumo — últimos 7 dias") {
                    HydrationChartView(dailyTotals: dailyTotals, metaDiariaML: profile.metaDiariaML)
                        .listRowInsets(EdgeInsets())
                        .padding()
                }

                Section("Dados") {
                    LabeledContent("Idade", value: "\(profile.idade) anos")
                    LabeledContent("Gênero", value: generoDisplay)
                    LabeledContent("Peso", value: "\(profile.pesoKg.formatted()) kg")
                    LabeledContent("Altura", value: "\(profile.alturaCm.formatted()) cm")
                    LabeledContent("Meta diária", value: "\(profile.metaDiariaML) mL")
                }

                Section {
                    Button("Editar perfil") { isEditing = true }
                }
            }
            .navigationTitle("Perfil")
            .sheet(isPresented: $isEditing) {
                NavigationStack {
                    ProfileFormView(
                        title: "Editar perfil",
                        confirmLabel: "Salvar",
                        initialValues: .from(profile),
                        showsCustomIntakeField: false,
                        onSave: save
                    )
                }
            }
        }
    }

    private func save(_ values: ProfileFormValues) {
        profile.idade = values.idade
        profile.genero = values.genero == .naoInformar ? nil : values.genero.rawValue
        profile.generoAutoDeclarado = values.normalizedGeneroAutoDeclarado
        profile.pesoKg = values.pesoKg
        profile.alturaCm = values.alturaCm
        profile.metaDiariaML = UserProfile.suggestedGoalML(gender: values.genero.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm)
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
        isEditing = false
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return ProfileView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
