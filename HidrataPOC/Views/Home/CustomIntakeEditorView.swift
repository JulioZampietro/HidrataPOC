import SwiftUI

/// Popup for the volume of the "Personalizado" quick-log button, reached from its
/// pencil icon on the Home screen. The track and the text field share one value so
/// they always agree — the track snaps to 50 mL steps, the text field accepts any
/// integer. Styled like the onboarding screens: gradient wave header with the number
/// centered on it, a pill-shaped water track below.
struct CustomIntakeEditorView: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountML: Double
    @FocusState private var fieldFocused: Bool

    private static let range: ClosedRange<Double> = 50...2000
    private static let step: Double = 50
    private let headerHeight: CGFloat = 300
    private let trackHeight: CGFloat = 56

    init(initialValueML: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _amountML = State(initialValue: Double(initialValueML))
    }

    private var amountField: Binding<Int> {
        Binding(get: { Int(amountML.rounded()) }, set: { amountML = Double($0) })
    }

    /// Fração (0...1) do trilho preenchida; valores digitados fora do intervalo ficam presos nas pontas.
    private var fillFraction: Double {
        let r = Self.range
        return min(max((amountML - r.lowerBound) / (r.upperBound - r.lowerBound), 0), 1)
    }

    /// Cada passo do trilho dá um "clique"; digitar no campo não passa por aqui.
    private func setFromTrack(_ newValue: Double) {
        if newValue != amountML { Haptic.selection.play() }
        amountML = newValue
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 10) {
                track
                HStack {
                    Text("50 mL")
                    Spacer()
                    Text("2.000 mL")
                }
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appSecondary)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 52)

            Spacer(minLength: 0)

            Button {
                onSave(max(Int(Self.range.lowerBound), Int(amountML.rounded())))
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
        .overlay(alignment: .topLeading) {
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
            .accessibilityLabel("Cancelar")
            .padding(.leading, 16)
            .padding(.top, 16)
        }
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
                        let r = Self.range
                        let raw = r.lowerBound + fraction * (r.upperBound - r.lowerBound)
                        setFromTrack((raw / Self.step).rounded() * Self.step)
                    }
            )
        }
        .frame(height: trackHeight)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(amountML.rounded())) mililitros")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? Self.step : -Self.step
            setFromTrack(min(max(amountML + delta, Self.range.lowerBound), Self.range.upperBound))
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CustomIntakeEditorView(initialValueML: 300, onSave: { _ in })
    }
}
