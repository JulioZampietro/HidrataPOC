import SwiftUI

struct SiriTutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    VStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.purple)
                            .padding(.top, 24)

                        Text("Como usar a Siri")
                            .font(.title2.bold())

                        Text("Registre água sem tirar o celular do bolso — funciona com a tela bloqueada.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    phrasesCard

                    tipsCard

                    Spacer(minLength: 0)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    private var phrasesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Frases que funcionam")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                PhraseRow(phrase: "\"Bebi 2 garrafas de HidrataPOC\"", result: "+1000 mL")
                PhraseRow(phrase: "\"Tomei 1 copo de HidrataPOC\"",    result: "+250 mL")
                PhraseRow(phrase: "\"Bebi 1 galão de HidrataPOC\"",    result: "+1000 mL")
                PhraseRow(phrase: "\"Bebi 3 copos de HidrataPOC\"",    result: "+750 mL")
            }
        }
        .padding()
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dicas")
                .font(.subheadline.weight(.semibold))

            TipRow(icon: "lock.fill", color: .purple,
                   text: "Funciona com a **tela bloqueada**.")
            TipRow(icon: "questionmark.circle.fill", color: .blue,
                   text: "Se não falar a quantidade, a Siri pergunta.")
            TipRow(icon: "globe", color: .green,
                   text: "Fale normalmente — não precisa de frase exata.")
        }
        .padding()
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Subviews

struct PhraseRow: View {
    let phrase: String
    let result: String

    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.purple)
                .frame(width: 20)
            Text(phrase)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(result)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple, in: Capsule())
        }
    }
}

struct TipRow: View {
    let icon: String
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SiriTutorialView()
}
