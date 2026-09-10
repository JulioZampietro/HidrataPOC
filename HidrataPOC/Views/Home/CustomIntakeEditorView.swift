import SwiftUI

/// Popup for the volume of the "Personalizado" quick-log button, reached from its
/// pencil icon on the Home screen. The slider and the text field share one value so
/// they always agree — the slider snaps to 50 mL steps, the text field accepts any
/// integer.
struct CustomIntakeEditorView: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountML: Double

    init(initialValueML: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _amountML = State(initialValue: Double(initialValueML))
    }

    private var amountField: Binding<Int> {
        Binding(get: { Int(amountML.rounded()) }, set: { amountML = Double($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Volume")
                        Spacer()
                        TextField("mL", value: amountField, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mL").foregroundStyle(.secondary)
                    }

                    Slider(value: $amountML, in: 0...1500, step: 50) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("1.500")
                    }
                }
            }
            .navigationTitle("Volume personalizado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(Int(amountML.rounded()))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    CustomIntakeEditorView(initialValueML: 300, onSave: { _ in })
}
