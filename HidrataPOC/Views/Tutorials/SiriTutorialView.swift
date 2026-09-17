import SwiftUI

private let siriPurple = Color(red: 0.286, green: 0.498, blue: 0.714)

struct SiriTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    intakeCard(
                        icon: "drop.fill",
                        title: "Gole",
                        volume: "40 mL",
                        phrases: [
                            ("Bebi um gole de HidrataPOC", "40 mL"),
                            ("Tomei um gole de HidrataPOC", "40 mL"),
                            ("Dei um gole de HidrataPOC", "40 mL"),
                            ("Bebi 3 goles de HidrataPOC", "120 mL"),
                            ("Bebi água no HidrataPOC", "40 mL"),
                        ]
                    )
                    intakeCard(
                        icon: "cup.and.saucer.fill",
                        title: "Copo",
                        volume: "250 mL",
                        phrases: [
                            ("Bebi um copo de HidrataPOC", "250 mL"),
                            ("Tomei um copo de HidrataPOC", "250 mL"),
                            ("Registra um copo no HidrataPOC", "250 mL"),
                            ("Acabei de tomar um copo de HidrataPOC", "250 mL"),
                            ("Bebi 2 copos de HidrataPOC", "500 mL"),
                        ]
                    )
                    intakeCard(
                        icon: "waterbottle.fill",
                        title: "Garrafa",
                        volume: "500 mL",
                        phrases: [
                            ("Bebi uma garrafa de HidrataPOC", "500 mL"),
                            ("Tomei uma garrafa de HidrataPOC", "500 mL"),
                            ("Terminei uma garrafa de HidrataPOC", "500 mL"),
                            ("Acabei minha garrafa no HidrataPOC", "500 mL"),
                            ("Bebi 2 garrafas de HidrataPOC", "1000 mL"),
                        ]
                    )
                    tipsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .appScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(siriPurple)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(siriPurple.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(siriPurple)
            }
            .padding(.top, 8)

            Text("Como usar a Siri")
                .font(.custom("Nunito", size: 24).weight(.heavy))
                .foregroundStyle(.primary)

            Text("Registre água sem tirar o celular do bolso — funciona com a tela bloqueada.")
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Intake Card

    private func intakeCard(icon: String, title: String, volume: String, phrases: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(siriPurple.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(siriPurple)
                }

                Text(title)
                    .font(.custom("Nunito", size: 17).weight(.heavy))
                    .foregroundStyle(.primary)

                Spacer()

                Text(volume)
                    .font(.custom("Nunito", size: 13).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(siriPurple, in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10000, y: 0))
            }
            .stroke(
                Color(red: 0.75, green: 0.78, blue: 0.82).opacity(0.6),
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
            .frame(height: 1)
            .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    phraseRow(text: phrase.0, result: phrase.1, isLast: index == phrases.count - 1)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func phraseRow(text: String, result: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(siriPurple)
                    .frame(width: 18)

                Text("\"\(text)\"")
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text(result)
                    .font(.custom("Nunito", size: 12).weight(.bold))
                    .foregroundStyle(siriPurple)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if !isLast {
                Divider()
                    .padding(.leading, 46)
            }
        }
    }

    // MARK: - Tips Card

    private var tipsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dicas")
                    .font(.custom("Nunito", size: 17).weight(.heavy))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10000, y: 0))
            }
            .stroke(
                Color(red: 0.75, green: 0.78, blue: 0.82).opacity(0.6),
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
            .frame(height: 1)
            .padding(.horizontal, 18)

            tipRow(icon: "lock.fill", color: .green, text: "Funciona com a **tela bloqueada**.", isLast: false)
            tipRow(icon: "questionmark.circle.fill", color: siriPurple, text: "Se não falar a quantidade, a Siri pergunta.", isLast: false)
            tipRow(icon: "mic.fill", color: .orange, text: "Não precisa de frase exata — fale naturalmente.", isLast: false)
            tipRow(icon: "number", color: .blue, text: "Funciona com números: \"3 copos\", \"dois goles\".", isLast: true)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func tipRow(icon: String, color: Color, text: LocalizedStringKey, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)
                    .padding(.top, 1)

                Text(text)
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            if !isLast {
                Divider()
                    .padding(.leading, 50)
            }
        }
    }
}

#Preview {
    SiriTutorialView()
}
