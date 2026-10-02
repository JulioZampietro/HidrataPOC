import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

/// Biological sex ("Sexo" in the UI). Still persisted under `UserProfile.genero`;
/// legacy values from the old gender options (nonbinary, self-identify, decline to
/// state) don't parse and are treated as "not set".
enum Genero: String, CaseIterable, Identifiable {
    case masculino, feminino

    var id: String { rawValue }

    var label: String {
        switch self {
        case .masculino: return "Masculino"
        case .feminino: return "Feminino"
        }
    }

    /// Maps to `WaterIntakeCalculator`'s `Gender`.
    var gender: Gender {
        switch self {
        case .feminino: return .female
        case .masculino: return .male
        }
    }

    init?(stored: String?) {
        guard let stored else { return nil }
        self.init(rawValue: stored)
    }
}

struct ProfileFormValues {
    var idade: Int
    /// `nil` when not set (new or legacy profile) — the goal then averages male/female.
    var genero: Genero?
    var pesoKg: Double
    var alturaCm: Double
    var customIntakeML: Int
    /// Current persisted goal — nil during onboarding (no stored value yet).
    var storedGoalML: Int?
    /// When true, save() recalculates the goal from the formula instead of preserving a manual value.
    var resetGoalToCalculated: Bool = false

    static var new: ProfileFormValues {
        ProfileFormValues(idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, customIntakeML: 300, storedGoalML: nil, resetGoalToCalculated: false)
    }

    static func from(_ profile: UserProfile) -> ProfileFormValues {
        ProfileFormValues(
            idade: profile.idade,
            genero: Genero(stored: profile.genero),
            pesoKg: profile.pesoKg,
            alturaCm: profile.alturaCm,
            customIntakeML: profile.customIntakeML,
            storedGoalML: profile.metaDiariaML
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
    @State private var idadeText: String
    @State private var genero: Genero?
    @State private var pesoKg: Double
    @State private var pesoText: String
    @State private var alturaCm: Double
    @State private var alturaText: String
    @State private var customIntakeML: Int
    @State private var isFetchingFromHealth = false
    @State private var resetGoal = false

    /// Read-only — recommended from the profile fields via `WaterIntakeCalculator`;
    /// no longer directly editable (see spec discussion on the heuristic model).
    private var metaDiariaML: Int {
        UserProfile.suggestedGoalML(gender: genero?.gender, idade: idade, pesoKg: pesoKg, alturaCm: alturaCm)
    }

    init(title: String, confirmLabel: String, initialValues: ProfileFormValues, showsCustomIntakeField: Bool, onSave: @escaping (ProfileFormValues) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialValues = initialValues
        self.showsCustomIntakeField = showsCustomIntakeField
        self.onSave = onSave
        _idade = State(initialValue: initialValues.idade)
        _idadeText = State(initialValue: "\(initialValues.idade)")
        _genero = State(initialValue: initialValues.genero)
        _pesoKg = State(initialValue: initialValues.pesoKg)
        _pesoText = State(initialValue: Self.formatDecimal(initialValues.pesoKg))
        _alturaCm = State(initialValue: initialValues.alturaCm)
        _alturaText = State(initialValue: Self.formatDecimal(initialValues.alturaCm))
        _customIntakeML = State(initialValue: initialValues.customIntakeML)
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Button {
                    Task { await fillFromHealth() }
                } label: {
                    HStack(spacing: 12) {
                        if isFetchingFromHealth {
                            ProgressView().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                                .frame(width: 22)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sincronizar com Saúde")
                                .foregroundStyle(.primary)
                            Text("Importa sexo biológico, nascimento, peso e altura")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isFetchingFromHealth)
            }

            Section("Sobre você") {
                HStack {
                    Text("Idade")
                    Spacer()
                    TextField("anos", text: $idadeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .onChange(of: idadeText) { _, val in
                            if let n = Int(val), (10...120).contains(n) { idade = n }
                        }
                    Text("anos").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Peso")
                    Spacer()
                    TextField("kg", text: $pesoText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: pesoText) { _, val in
                            if let n = Self.parseDecimal(val) { pesoKg = n }
                        }
                    Text("kg").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Altura")
                    Spacer()
                    TextField("cm", text: $alturaText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: alturaText) { _, val in
                            if let n = Self.parseDecimal(val) { alturaCm = n }
                        }
                    Text("cm").foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Sexo", selection: $genero) {
                    ForEach(Genero.allCases) { option in
                        Text(option.label).tag(Optional(option))
                    }
                }
            } footer: {
                Text("Usado apenas para calcular sua necessidade diária de água.")
            }

            Section {
                let displayedGoal = resetGoal ? metaDiariaML : (initialValues.storedGoalML ?? metaDiariaML)
                LabeledContent("Meta diária", value: "\(displayedGoal) mL")

                if let stored = initialValues.storedGoalML, stored != metaDiariaML {
                    if resetGoal {
                        Button("Manter meta manual — \(stored) mL") { resetGoal = false }
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Redefinir para meta calculada — \(metaDiariaML) mL") { resetGoal = true }
                    }
                }
            } footer: {
                if resetGoal {
                    Text("A meta será redefinida para \(metaDiariaML) mL ao salvar.")
                }
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
                    let finalIdade = Int(idadeText).map { max(10, min(120, $0)) } ?? idade
                    let finalPeso = Self.parseDecimal(pesoText) ?? pesoKg
                    let finalAltura = Self.parseDecimal(alturaText) ?? alturaCm
                    onSave(ProfileFormValues(idade: finalIdade, genero: genero, pesoKg: finalPeso, alturaCm: finalAltura, customIntakeML: customIntakeML, storedGoalML: initialValues.storedGoalML, resetGoalToCalculated: resetGoal))
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .listRowBackground(accentBlue)
            }
            .id("confirmSection")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isFetchingFromHealth) { _, isFetching in
            guard !isFetching else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo("confirmSection", anchor: .bottom)
            }
        }
        } // ScrollViewReader
    }

    private func fillFromHealth() async {
        isFetchingFromHealth = true
        let data = await HealthKitService.shared.fetchProfileData()
        if let age = data.idade { idade = age; idadeText = "\(age)" }
        if let g = data.genero { genero = g }
        if let w = data.pesoKg { pesoKg = w.rounded(); pesoText = Self.formatDecimal(w.rounded()) }
        if let h = data.alturaCm { alturaCm = h.rounded(); alturaText = Self.formatDecimal(h.rounded()) }
        isFetchingFromHealth = false
    }

    private static func parseDecimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private static func formatDecimal(_ value: Double) -> String {
        let formatted = String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", value)
        return formatted
    }
}

#Preview {
    NavigationStack {
        ProfileFormView(title: "Bem-vindo(a)", confirmLabel: "Concluir", initialValues: .new, showsCustomIntakeField: true, onSave: { _ in })
    }
}
