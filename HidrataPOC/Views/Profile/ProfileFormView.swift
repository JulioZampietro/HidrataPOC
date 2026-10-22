import SwiftUI


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
    /// Output only: the goal to save — the manual value if the user typed one in the form,
    /// otherwise the one calculated from the other fields.
    var goalML: Int = 0

    static var new: ProfileFormValues {
        ProfileFormValues(idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, customIntakeML: 300, storedGoalML: nil)
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
/// Styled like the other onboarding-style popups: gradient wave header whose hero is the
/// (editable) daily goal, then tiles for the body data, all numbers underlined to read as editable.
struct ProfileFormView: View {
    let title: String
    let confirmLabel: String
    let initialValues: ProfileFormValues
    /// Onboarding sets the initial custom quick-log volume here; once a profile
    /// exists, that volume is edited from its pencil icon on the Home screen instead
    /// (see `CustomIntakeEditorView`), so the profile-edit sheet hides this field.
    let showsCustomIntakeField: Bool
    /// Mostra um "X" pra fechar sem salvar. `false` no onboarding (não é uma sheet
    /// dispensável, é uma etapa obrigatória) — `true` na edição a partir do Perfil.
    let showsCancelButton: Bool
    let onSave: (ProfileFormValues) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var idade: Int
    @State private var idadeText: String
    @State private var genero: Genero?
    @State private var pesoKg: Double
    @State private var pesoText: String
    @State private var alturaCm: Double
    @State private var alturaText: String
    @State private var customIntakeML: Int
    @State private var isFetchingFromHealth = false
    /// Meta digitada pelo usuário; `nil` enquanto ela acompanha o valor calculado.
    @State private var goalOverride: String?

    private enum Field: Hashable { case goal, idade, peso, altura, custom }

    private static let maxGoalML = 10000

    /// Recommended from the profile fields via `WaterIntakeCalculator`; follows the fields live.
    private var calculatedGoalML: Int {
        UserProfile.suggestedGoalML(gender: genero?.gender, idade: idade, pesoKg: pesoKg, alturaCm: alturaCm)
    }

    private var manualGoalML: Int? {
        guard let text = goalOverride, let value = Int(text), value > 0 else { return nil }
        return min(value, Self.maxGoalML)
    }

    private var goalBinding: Binding<String> {
        Binding(
            get: { goalOverride ?? String(calculatedGoalML) },
            set: { goalOverride = String($0.filter(\.isNumber).prefix(5)) }
        )
    }

    init(title: String, confirmLabel: String, initialValues: ProfileFormValues, showsCustomIntakeField: Bool, showsCancelButton: Bool = false, onSave: @escaping (ProfileFormValues) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialValues = initialValues
        self.showsCustomIntakeField = showsCustomIntakeField
        self.showsCancelButton = showsCancelButton
        self.onSave = onSave
        _idade = State(initialValue: initialValues.idade)
        _idadeText = State(initialValue: "\(initialValues.idade)")
        _genero = State(initialValue: initialValues.genero)
        _pesoKg = State(initialValue: initialValues.pesoKg)
        _pesoText = State(initialValue: Self.formatDecimal(initialValues.pesoKg))
        _alturaCm = State(initialValue: initialValues.alturaCm)
        _alturaText = State(initialValue: Self.formatDecimal(initialValues.alturaCm))
        _customIntakeML = State(initialValue: initialValues.customIntakeML)

        // Uma meta guardada diferente da calculada foi editada à mão: continua valendo.
        let calculated = UserProfile.suggestedGoalML(gender: initialValues.genero?.gender, idade: initialValues.idade, pesoKg: initialValues.pesoKg, alturaCm: initialValues.alturaCm)
        if let stored = initialValues.storedGoalML, stored != calculated {
            _goalOverride = State(initialValue: "\(stored)")
        } else {
            _goalOverride = State(initialValue: nil)
        }
    }

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 0) {
                header(topInset: geo.safeAreaInsets.top)

                VStack(spacing: 16) {
                    syncButton

                    HStack(spacing: 10) {
                        tile("Idade", unit: "anos", text: $idadeText, field: .idade, keyboard: .numberPad)
                            .onChange(of: idadeText) { _, val in
                                if let n = Int(val), (10...120).contains(n) { idade = n }
                            }
                        tile("Peso", unit: "kg", text: $pesoText, field: .peso, keyboard: .decimalPad)
                            .onChange(of: pesoText) { _, val in
                                if let n = Self.parseDecimal(val) { pesoKg = n }
                            }
                        tile("Altura", unit: "cm", text: $alturaText, field: .altura, keyboard: .decimalPad)
                            .onChange(of: alturaText) { _, val in
                                if let n = Self.parseDecimal(val) { alturaCm = n }
                            }
                    }

                    sexSection

                    if showsCustomIntakeField { customIntakeRow }

                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top) // o gradiente do cabeçalho sobe até o topo da tela
        } // GeometryReader
        .appScreenBackground()
        .navigationTitle(title)
        .toolbar(.hidden, for: .navigationBar)
        // Number/decimal pads have no return key, so let a tap outside or a scroll dismiss the keyboard.
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneToolbar()
        .background(DismissKeyboardOnTap())
        .overlay(alignment: .topLeading) {
            if showsCancelButton {
                Button {
                    Haptic.dismiss.play()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel("Fechar")
                .padding(.leading, 16)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Header

    /// `topInset` é a área da barra de status (0 numa sheet): o conteúdo do cabeçalho desce\n    /// esse tanto, e o gradiente ocupa a tela até o topo.
    private func header(topInset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text("Meta diária")
                .font(AppFont.subheadlineStrong)
                .foregroundStyle(.white.opacity(0.85))

            // O texto invisível dá ao campo a largura exata dos dígitos; o campo fica por cima.
            Text(verbatim: goalBinding.wrappedValue)
                .font(AppFont.numberLarge)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .hidden()
                .padding(.horizontal, 10)
                .frame(minWidth: 100)
                .overlay {
                    TextField("mL", text: goalBinding)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .goal)
                        .multilineTextAlignment(.center)
                        .font(AppFont.numberLarge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .accessibilityLabel("Meta diária em mililitros")
                }
                .overlay(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.55)).frame(height: 3)
                }

            Text("mL")
                .font(AppFont.title3)
                .foregroundStyle(.white.opacity(0.9))

            if let manual = manualGoalML, manual != calculatedGoalML {
                Button {
                    Haptic.selection.play()
                    goalOverride = nil
                } label: {
                    Text("Redefinir para meta calculada")
                        .font(AppFont.footnoteStrong)
                        .foregroundStyle(.white)
                        .underline()
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 56 + topInset)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            LinearGradient.waterHeader
                .clipShape(WaveShape())
        }
    }

    // MARK: - Sync

    private var syncButton: some View {
        Button {
            Haptic.tap.play()
            Task { await fillFromHealth() }
        } label: {
            HStack(spacing: 8) {
                if isFetchingFromHealth {
                    ProgressView()
                } else {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
                Text("Sincronizar com Saúde")
                    .font(AppFont.subheadlineStrong)
                    .foregroundStyle(Color.appAccentTextOnWhite)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.appAccent.opacity(0.12), radius: 5, y: 2)
        }
        .disabled(isFetchingFromHealth)
    }

    // MARK: - Tiles

    private func tile(_ label: String, unit: String, text: Binding<String>, field: Field, keyboard: UIKeyboardType) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appSecondary)

            Text(verbatim: text.wrappedValue.isEmpty ? "0" : text.wrappedValue)
                .font(AppFont.numberTile)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .hidden()
                .padding(.horizontal, 6)
                .frame(minWidth: 44)
                .overlay {
                    TextField("0", text: text)
                        .keyboardType(keyboard)
                        .focused($focusedField, equals: field)
                        .multilineTextAlignment(.center)
                        .font(AppFont.numberTile)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Color.appAccentText)
                        .accessibilityLabel(label)
                }
                .overlay(alignment: .bottom) {
                    Capsule().fill(Color.appAccent.opacity(0.3)).frame(height: 3)
                }

            Text(unit)
                .font(AppFont.subheadlineStrong)
                .foregroundStyle(Color.appSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .panelBackground(cornerRadius: 22)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    // MARK: - Sexo

    private var sexSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sexo")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appSecondary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                ForEach(Genero.allCases) { option in
                    sexOption(option)
                }
            }
        }
        .haptic(.selection, on: genero)
    }

    private func sexOption(_ option: Genero) -> some View {
        let isSelected = genero == option
        return Button {
            genero = option
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option == .masculino ? "figure.stand" : "figure.stand.dress")
                    .font(.system(.title2, weight: .semibold))
                Text(option.label)
                    .font(AppFont.calloutStrong)
            }
            .foregroundStyle(isSelected ? Color.white : Color.appSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient.waterHeader)
                        .shadow(color: Color.appAccent.opacity(0.35), radius: 6, y: 3)
                }
            }
            .panelBackground(cornerRadius: 22, isVisible: !isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Onboarding-only field

    private var customIntakeRow: some View {
        HStack {
            Text("Botão personalizado")
                .font(AppFont.calloutStrong)
            Spacer()
            TextField("mL", value: $customIntakeML, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .custom)
                .multilineTextAlignment(.trailing)
                .font(AppFont.calloutStrong)
                .foregroundStyle(Color.appAccentText)
                .frame(width: 80)
            Text("mL").foregroundStyle(Color.appSecondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .panelBackground(cornerRadius: 22)
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            focusedField = nil
            let finalIdade = Int(idadeText).map { max(10, min(120, $0)) } ?? idade
            let finalPeso = Self.parseDecimal(pesoText) ?? pesoKg
            let finalAltura = Self.parseDecimal(alturaText) ?? alturaCm
            let finalGoal = manualGoalML
                ?? UserProfile.suggestedGoalML(gender: genero?.gender, idade: finalIdade, pesoKg: finalPeso, alturaCm: finalAltura)
            onSave(ProfileFormValues(idade: finalIdade, genero: genero, pesoKg: finalPeso, alturaCm: finalAltura, customIntakeML: customIntakeML, storedGoalML: initialValues.storedGoalML, goalML: finalGoal))
        } label: {
            Text(confirmLabel)
                .font(AppFont.calloutStrong)
                .padding(.horizontal, 32)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.appAccent)
        .padding(.top, 4)
    }

    private func fillFromHealth() async {
        isFetchingFromHealth = true
        let data = await HealthKitService.shared.fetchProfileData()
        if let age = data.idade { idade = age; idadeText = "\(age)" }
        if let g = data.genero { genero = g }
        if let w = data.pesoKg { pesoKg = w.rounded(); pesoText = Self.formatDecimal(w.rounded()) }
        if let h = data.alturaCm { alturaCm = h.rounded(); alturaText = Self.formatDecimal(h.rounded()) }
        isFetchingFromHealth = false
        if data.idade != nil || data.genero != nil || data.pesoKg != nil || data.alturaCm != nil {
            Haptic.success.play()
        } else {
            Haptic.warning.play()
        }
    }

    private static func parseDecimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private static func formatDecimal(_ value: Double) -> String {
        let formatted = String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", value)
        return formatted
    }
}

extension View {
    /// Botão "Concluído" acima do teclado. Os teclados numéricos (`numberPad`, `decimalPad`)
    /// não têm tecla de retorno, então sem isso só dava para fechar tocando fora ou rolando
    /// — o HIG pede uma saída explícita na barra do teclado.
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Concluído") {
                    Haptic.tap.play()
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(AppFont.calloutStrong)
            }
        }
    }
}

/// Fecha o teclado ao tocar fora de um campo de texto. Usa um reconhecedor de UIKit na
/// janela (sem cancelar toques) em vez de um gesto do SwiftUI no `Form`, que pode
/// engolir os toques dos botões das linhas.
private struct DismissKeyboardOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> TapAttachingView { TapAttachingView() }
    func updateUIView(_ uiView: TapAttachingView, context: Context) {}

    final class TapAttachingView: UIView, UIGestureRecognizerDelegate {
        private lazy var recognizer: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            return tap
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(touch.view is UITextField || touch.view is UITextView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

#Preview {
    NavigationStack {
        ProfileFormView(title: "Bem-vindo(a)", confirmLabel: "Concluir", initialValues: .new, showsCustomIntakeField: true, onSave: { _ in })
    }
}
