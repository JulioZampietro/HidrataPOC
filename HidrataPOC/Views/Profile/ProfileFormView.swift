import SwiftUI

enum Genero: String, CaseIterable, Identifiable {
    case feminino, masculino, naoInformar = "prefiro_nao_informar"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feminino: return "Feminino"
        case .masculino: return "Masculino"
        case .naoInformar: return "Prefiro não informar"
        }
    }
}

struct ProfileFormValues {
    var idade: Int
    var genero: Genero
    var pesoKg: Double
    var alturaCm: Double
    var metaDiariaML: Int
    var customIntakeML: Int

    static var new: ProfileFormValues {
        ProfileFormValues(idade: 25, genero: .naoInformar, pesoKg: 70, alturaCm: 170, metaDiariaML: UserProfile.suggestedGoalML(pesoKg: 70), customIntakeML: 300)
    }

    static func from(_ profile: UserProfile) -> ProfileFormValues {
        ProfileFormValues(
            idade: profile.idade,
            genero: Genero(rawValue: profile.genero ?? Genero.naoInformar.rawValue) ?? .naoInformar,
            pesoKg: profile.pesoKg,
            alturaCm: profile.alturaCm,
            metaDiariaML: profile.metaDiariaML,
            customIntakeML: profile.customIntakeML
        )
    }
}

/// Shared between onboarding and the profile-edit sheet — same fields, different title/action.
struct ProfileFormView: View {
    let title: String
    let confirmLabel: String
    let initialValues: ProfileFormValues
    let onSave: (ProfileFormValues) -> Void

    @State private var idade: Int
    @State private var genero: Genero
    @State private var pesoKg: Double
    @State private var alturaCm: Double
    @State private var metaDiariaML: Int
    @State private var metaManuallyEdited = false
    @State private var customIntakeML: Int

    init(title: String, confirmLabel: String, initialValues: ProfileFormValues, onSave: @escaping (ProfileFormValues) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialValues = initialValues
        self.onSave = onSave
        _idade = State(initialValue: initialValues.idade)
        _genero = State(initialValue: initialValues.genero)
        _pesoKg = State(initialValue: initialValues.pesoKg)
        _alturaCm = State(initialValue: initialValues.alturaCm)
        _metaDiariaML = State(initialValue: initialValues.metaDiariaML)
        _customIntakeML = State(initialValue: initialValues.customIntakeML)
    }

    var body: some View {
        Form {
            Section("Sobre você") {
                Stepper("Idade: \(idade) anos", value: $idade, in: 10...100)

                Picker("Gênero", selection: $genero) {
                    ForEach(Genero.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                HStack {
                    Text("Peso")
                    Spacer()
                    TextField("kg", value: $pesoKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Altura")
                    Spacer()
                    TextField("cm", value: $alturaCm, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("cm").foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Meta diária")
                    Spacer()
                    TextField("mL", value: $metaDiariaML, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onChange(of: metaDiariaML) { metaManuallyEdited = true }
                    Text("mL").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Sugerida a partir do seu peso — edite se quiser um valor diferente.")
            }

            Section {
                HStack {
                    Text("Botão personalizado")
                    Spacer()
                    TextField("mL", value: $customIntakeML, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("mL").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Volume do 4º botão de registro rápido na tela inicial.")
            }

            Section {
                Button(confirmLabel) {
                    onSave(ProfileFormValues(idade: idade, genero: genero, pesoKg: pesoKg, alturaCm: alturaCm, metaDiariaML: metaDiariaML, customIntakeML: customIntakeML))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
        .onChange(of: pesoKg) { _, newValue in
            guard !metaManuallyEdited else { return }
            metaDiariaML = UserProfile.suggestedGoalML(pesoKg: newValue)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileFormView(title: "Bem-vindo(a)", confirmLabel: "Concluir", initialValues: .new, onSave: { _ in })
    }
}
