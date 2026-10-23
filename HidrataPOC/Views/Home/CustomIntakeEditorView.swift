import SwiftUI

/// Popup de volume compartilhado pelo botão "Personalizado" da Home (pencil icon) e
/// pelo "Alterar meta" do Perfil — mesmo visual (header em onda com o número
/// centralizado, trilho de água em pílula), diferenciados pelo título, o intervalo
/// arrastável e o destino do valor salvo. O trilho e o campo de texto compartilham um
/// valor só, então sempre concordam — o trilho anda em passos de `step`, o campo
/// aceita qualquer inteiro (clampado em `range` só ao salvar, pra deixar a pessoa
/// digitar livremente enquanto edita).
struct CustomIntakeEditorView: View {
    let title: String
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountML: Double
    @FocusState private var fieldFocused: Bool

    private let range: ClosedRange<Double>
    private let step: Double
    private let headerHeight: CGFloat = 300
    private let trackHeight: CGFloat = 56

    init(title: String, initialValueML: Int, range: ClosedRange<Double> = 50...2000, step: Double = 50, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.onSave = onSave
        self.range = range
        self.step = step
        _amountML = State(initialValue: Double(initialValueML))
    }

    private var amountField: Binding<Int> {
        Binding(get: { Int(amountML.rounded()) }, set: { amountML = Double($0) })
    }

    /// Fração (0...1) do trilho preenchida; valores digitados fora do intervalo ficam presos nas pontas.
    private var fillFraction: Double {
        min(max((amountML - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// Cada passo do trilho dá um "clique"; digitar no campo não passa por aqui.
    private func setFromTrack(_ newValue: Double) {
        if newValue != amountML { Haptic.selection.play() }
        amountML = newValue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                VStack(spacing: 10) {
                    track
                    HStack {
                        Text("\(Int(range.lowerBound), format: .number) mL")
                        Spacer()
                        Text("\(Int(range.upperBound), format: .number) mL")
                    }
                    .font(AppFont.footnoteStrong)
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)

                Spacer(minLength: 0)

                Button {
                    let clamped = min(max(amountML.rounded(), range.lowerBound), range.upperBound)
                    onSave(Int(clamped))
                    dismiss()
                } label: {
                    Text("Salvar")
                        .font(AppFont.calloutStrong)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.appAccent)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appScreenBackground()
            .keyboardDoneToolbar()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // Título branco, como o "X": os dois ficam em cima do gradiente do header.
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(.headline))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Haptic.dismiss.play()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Cancelar")
                }
            }
        }
        .presentationDetents([.fraction(0.8)])
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            LinearGradient.waterHeader
                .clipShape(WaveShape())
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 6) {
                // O texto invisível dá ao campo a largura exata dos dígitos (o campo sozinho
                // se espremia e quebrava a partir de 4 dígitos); o campo fica por cima.
                Text(verbatim: String(max(Int(amountML.rounded()), 0)))
                    .font(AppFont.numberHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .hidden()
                    .padding(.horizontal, 12)
                    .frame(minWidth: 100)
                    .overlay {
                        TextField("mL", value: amountField, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                            .multilineTextAlignment(.center)
                            .font(AppFont.numberHero)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .accessibilityLabel("Volume em mililitros")
                    }
                    .overlay(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.55)).frame(height: 3)
                    }
                    .padding(.horizontal, 24)
                Text("mL")
                    .font(AppFont.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 20)
        }
        .frame(height: headerHeight)
    }

    // MARK: - Track

    /// Trilho em pílula: o preenchimento em gradiente tem a borda direita reta e some
    /// recortado pela pílula na esquerda. Arrastar em qualquer ponto muda o valor.
    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appAccent.opacity(0.10))
                Rectangle()
                    .fill(LinearGradient.waterHeader)
                    .frame(width: geo.size.width * fillFraction)
                    .animation(.easeOut(duration: 0.12), value: fillFraction)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.appAccent.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        fieldFocused = false
                        let fraction = min(max(drag.location.x / geo.size.width, 0), 1)
                        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                        setFromTrack((raw / step).rounded() * step)
                    }
            )
        }
        .frame(height: trackHeight)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(amountML.rounded())) mililitros")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            setFromTrack(min(max(amountML + delta, range.lowerBound), range.upperBound))
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CustomIntakeEditorView(title: "Outro", initialValueML: 300, onSave: { _ in })
    }
}
