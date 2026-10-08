import SwiftUI

/// Popup for the daily hydration goal, reached from the "Editar" button on the goal
/// card. This edits `metaDiariaML` directly — separate from "Dados pessoais", which
/// still recalculates the goal from body stats on save (per product decision: no
/// manual-override flag in this version, so a later personal-data edit will
/// overwrite a custom goal set here). The warning below exists to make that
/// resettable-on-next-edit behavior clear at the point the user sets a custom value.
struct EditGoalView: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    private let initialValueML: Int

    private static let maxML = 10000

    init(initialValueML: Int, onSave: @escaping (Int) -> Void) {
        self.initialValueML = initialValueML
        self.onSave = onSave
        _text = State(initialValue: "\(initialValueML)")
    }

    private var parsedValue: Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Meta diária")
                        Spacer()
                        TextField("mL", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mL").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Se você editar seus dados pessoais (idade, peso, altura ou gênero) depois, a meta diária será recalculada automaticamente e substituirá este valor.")
                }
            }
            .navigationTitle("Editar meta diária")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", systemImage: "checkmark") {
                        let value = parsedValue.map { min(max($0, 0), Self.maxML) } ?? initialValueML
                        onSave(value)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    EditGoalView(initialValueML: 2450, onSave: { _ in })
}
