import SwiftUI

/// Popup for the volume of the "Personalizado" quick-log button, reached from its
/// pencil icon on the Home screen. The slider and the text field share one value so
/// they always agree — the slider snaps to 50 mL steps, the text field accepts any
/// integer.
struct CustomIntakeEditorView: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountML: Double
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 90

    init(initialValueML: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _amountML = State(initialValue: Double(initialValueML))
    }

    private var amountField: Binding<Int> {
        Binding(get: { Int(amountML.rounded()) }, set: { amountML = Double($0) })
    }

    /// Cada passo do controle deslizante dá um "clique"; digitar no campo não passa por aqui.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { amountML },
            set: { newValue in
                if newValue != amountML { Haptic.selection.play() }
                amountML = newValue
            }
        )
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
                            .frame(width: fieldWidth)
                        Text("mL").foregroundStyle(Color.appSecondary)
                    }

                    Slider(value: sliderValue, in: 50...1500, step: 50) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Text("50")
                    } maximumValueLabel: {
                        Text("1.500")
                    }
                }
            }
            .font(AppFont.body)
            .navigationTitle("Volume personalizado")
            .scrollContentBackground(.hidden)
            .appScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", systemImage: "checkmark") {
                        onSave(max(50, Int(amountML.rounded())))
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
