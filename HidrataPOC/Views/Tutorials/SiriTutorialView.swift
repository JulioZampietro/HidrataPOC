import SwiftUI


struct SiriTutorialView: View {
    @ScaledMetric(relativeTo: .callout) private var iconTileSize: CGFloat = 36
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
                        icon: "mug.fill",
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                        .foregroundStyle(Color.appAccentText)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.appAccentText)
            }
            .padding(.top, 8)

            Text("Como usar a Siri")
                .font(AppFont.title)
                .foregroundStyle(.primary)

            Text("Registre água sem tirar o celular do bolso — funciona com a tela bloqueada.")
                .font(AppFont.subheadline)
                .foregroundStyle(Color.appSecondary)
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
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: iconTileSize, height: iconTileSize)
                    Image(systemName: icon)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Color.appAccentText)
                }

                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(volume)
                    .font(AppFont.footnoteStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccent, in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10000, y: 0))
            }
            .stroke(
                Color.appDivider,
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
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
    }

    private func phraseRow(text: String, result: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: 18)

                Text("\"\(text)\"")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text(result)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.appAccentText)
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
                    .font(AppFont.headline)
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
                Color.appDivider,
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
            .frame(height: 1)
            .padding(.horizontal, 18)

            tipRow(icon: "lock.fill", color: Color.appSuccess, text: "Funciona com a **tela bloqueada**.", isLast: false)
            tipRow(icon: "questionmark.circle.fill", color: Color.appAccentText, text: "Se não falar a quantidade, a Siri pergunta.", isLast: false)
            tipRow(icon: "mic.fill", color: Color.appWarning, text: "Não precisa de frase exata — fale naturalmente.", isLast: false)
            tipRow(icon: "number", color: Color.appAccentText, text: "Funciona com números: \"3 copos\", \"dois goles\".", isLast: true)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
    }

    private func tipRow(icon: String, color: Color, text: LocalizedStringKey, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)
                    .padding(.top, 1)

                Text(text)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appSecondary)
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
