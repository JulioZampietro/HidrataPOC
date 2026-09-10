import SwiftUI

enum Genero: String, CaseIterable, Identifiable {
    case feminino, masculino, naoBinario = "nao_binario", autoDeclarado = "autodeclarado", naoInformar = "prefiro_nao_informar"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feminino: return "Feminino"
        case .masculino: return "Masculino"
        case .naoBinario: return "Não binário"
        case .autoDeclarado: return "Autodeclarado"
        case .naoInformar: return "Prefiro não informar"
        }
    }

    /// Maps to `WaterIntakeCalculator`'s `Gender` — only male/female follow the
    /// formula's own baseline; every other option (`nil` here) is treated by
    /// `UserProfile.suggestedGoalML` as a male/female average.
    var gender: Gender? {
        switch self {
        case .feminino: return .female
        case .masculino: return .male
        case .naoBinario, .autoDeclarado, .naoInformar: return nil
        }
    }
}

struct ProfileFormValues {
    var idade: Int
    var genero: Genero
    /// Free-text label for `.autoDeclarado` ("self-identify"); ignored otherwise.
    var generoAutoDeclarado: String
    var pesoKg: Double
    var alturaCm: Double
    var customIntakeML: Int

    /// `generoAutoDeclarado` trimmed to `nil` when blank or not applicable — what
    /// actually gets persisted to `UserProfile.generoAutoDeclarado`.
    var normalizedGeneroAutoDeclarado: String? {
        guard genero == .autoDeclarado else { return nil }
        let trimmed = generoAutoDeclarado.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var new: ProfileFormValues {
        ProfileFormValues(idade: 25, genero: .naoInformar, generoAutoDeclarado: "", pesoKg: 70, alturaCm: 170, customIntakeML: 300)
    }

    static func from(_ profile: UserProfile) -> ProfileFormValues {
        ProfileFormValues(
            idade: profile.idade,
            genero: Genero(rawValue: profile.genero ?? Genero.naoInformar.rawValue) ?? .naoInformar,
            generoAutoDeclarado: profile.generoAutoDeclarado ?? "",
            pesoKg: profile.pesoKg,
            alturaCm: profile.alturaCm,
            customIntakeML: profile.customIntakeML
        )
    }
}

/// Shared between onboarding and the profile-edit sheet — same fields, different title/action.
struct ProfileFormView: View {
    let title: String
    let confirmLabel: String
    let initialValues: ProfileFormValues
    /// Onboarding sets the initial custom quick-log volume here; once a profile
    /// exists, that volume is edited from its pencil icon on the Home screen instead
    /// (see `CustomIntakeEditorView`), so the profile-edit sheet hides this field.
    let showsCustomIntakeField: Bool
    let onSave: (ProfileFormValues) -> Void

    @State private var idade: Int
    @State private var genero: Genero
    @State private var generoAutoDeclarado: String
    @State private var pesoKg: Double
    @State private var alturaCm: Double
    @State private var customIntakeML: Int

    /// Read-only — recommended from the profile fields via `WaterIntakeCalculator`;
    /// no longer directly editable (see spec discussion on the heuristic model).
    private var metaDiariaML: Int {
        UserProfile.suggestedGoalML(gender: genero.gender, idade: idade, pesoKg: pesoKg, alturaCm: alturaCm)
    }

    init(title: String, confirmLabel: String, initialValues: ProfileFormValues, showsCustomIntakeField: Bool, onSave: @escaping (ProfileFormValues) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialValues = initialValues
        self.showsCustomIntakeField = showsCustomIntakeField
        self.onSave = onSave
        _idade = State(initialValue: initialValues.idade)
        _genero = State(initialValue: initialValues.genero)
        _generoAutoDeclarado = State(initialValue: initialValues.generoAutoDeclarado)
        _pesoKg = State(initialValue: initialValues.pesoKg)
        _alturaCm = State(initialValue: initialValues.alturaCm)
        _customIntakeML = State(initialValue: initialValues.customIntakeML)
    }

    var body: some View {
        Form {
            Section("Sobre você") {
                Stepper("Idade: \(idade) anos", value: $idade, in: 10...100)

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
                Picker("Gênero", selection: $genero) {
                    ForEach(Genero.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                if genero == .autoDeclarado {
                    TextField("Como você se identifica", text: $generoAutoDeclarado)
                }
            } footer: {
                Text("Usado apenas para calcular sua necessidade diária de água.")
            }

            Section {
                LabeledContent("Meta diária", value: "\(metaDiariaML) mL")
            }

            if showsCustomIntakeField {
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
                }
            }

            Section {
                Button(confirmLabel) {
                    onSave(ProfileFormValues(idade: idade, genero: genero, generoAutoDeclarado: generoAutoDeclarado, pesoKg: pesoKg, alturaCm: alturaCm, customIntakeML: customIntakeML))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
    }
}

#Preview {
    NavigationStack {
        ProfileFormView(title: "Bem-vindo(a)", confirmLabel: "Concluir", initialValues: .new, showsCustomIntakeField: true, onSave: { _ in })
    }
}
