import SwiftUI


struct SiriTutorialView: View {
    var body: some View {
        TankSheet {
            SiriStepsContent(showsMascotLine: false)
                .padding(.bottom, 40)
        }
    }
}

/// Conteúdo compartilhado entre esta sheet e a página equivalente do onboarding de
/// primeiro uso (`FeatureOnboardingView`) — mesma cópia nos dois lugares, um único
/// lugar pra editar.
struct SiriStepsContent: View {
    /// A sheet standalone (acessada pelo Perfil) não mostra a fala do mascote —
    /// só o onboarding de primeiro uso, onde ele ainda está "se apresentando".
    var showsMascotLine: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            header()
            cards
        }
    }

    /// Separados pra o onboarding poder desenhar o fundo azul fixo e paginar só
    /// texto/mascote e cards por cima dele.
    func header(showsBackground: Bool = true) -> some View {
        CurrentMascotTankHeader(
            title: "Siri",
            subtitle: "Registre água sem tirar o celular do bolso — funciona com a tela bloqueada.",
            mascotLine: showsMascotLine ? "Agora nem precisa olhar pra mim pra me vencer." : nil,
            showsBackground: showsBackground
        )
    }

    var cards: some View {
        VStack(spacing: 20) {
            intakeCard(title: "Gole", volume: "40 mL", phrases: [
                ("Bebi um gole de Gole", "40 mL"),
                ("Tomei um gole de Gole", "40 mL"),
                ("Dei um gole de Gole", "40 mL"),
                ("Bebi 3 goles de Gole", "120 mL"),
                ("Bebi água no Gole", "40 mL"),
            ])
            intakeCard(title: "Copo", volume: "250 mL", phrases: [
                ("Bebi um copo de Gole", "250 mL"),
                ("Tomei um copo de Gole", "250 mL"),
                ("Registra um copo no Gole", "250 mL"),
                ("Acabei de tomar um copo de Gole", "250 mL"),
                ("Bebi 2 copos de Gole", "500 mL"),
            ])
            intakeCard(title: "Garrafa", volume: "500 mL", phrases: [
                ("Bebi uma garrafa de Gole", "500 mL"),
                ("Tomei uma garrafa de Gole", "500 mL"),
                ("Terminei uma garrafa de Gole", "500 mL"),
                ("Acabei minha garrafa no Gole", "500 mL"),
                ("Bebi 2 garrafas de Gole", "1000 mL"),
            ])
            tipsCard
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Intake Card

    private func intakeCard(title: String, volume: String, phrases: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(volume)
                    .font(AppFont.footnoteStrong)
                    .foregroundStyle(Color.appSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    phraseRow(text: phrase.0, result: phrase.1, isLast: index == phrases.count - 1)
                }
            }
        }
        .panelBackground()
    }

    private func phraseRow(text: String, result: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
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
                Divider().padding(.leading, 18)
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

            Divider().padding(.horizontal, 18)

            tipRow(text: "Funciona com a **tela bloqueada**.", isLast: false)
            tipRow(text: "Se não falar a quantidade, a Siri pergunta.", isLast: false)
            tipRow(text: "Não precisa de frase exata — fale naturalmente.", isLast: false)
            tipRow(text: "Funciona com números: \"3 copos\", \"dois goles\".", isLast: true)
        }
        .panelBackground()
    }

    private func tipRow(text: LocalizedStringKey, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(text)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            if !isLast {
                Divider().padding(.leading, 18)
            }
        }
    }
}

#Preview {
    SiriTutorialView()
}
