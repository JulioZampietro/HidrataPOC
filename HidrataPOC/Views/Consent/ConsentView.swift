import SwiftUI

/// Primeira tela que qualquer pessoa vê — antes de perfil, antes de qualquer dado
/// do app existir. Usa a mesma linguagem visual de marca dos tutoriais (`TankHeader`:
/// gradiente de água + onda + mascote), em vez de um ícone de sistema solto, pra essa
/// primeira impressão já parecer o Gole, não uma tela de termos genérica.
struct ConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TankHeader(
                    title: "Gole",
                    subtitle: "Antes de começar",
                    mascotLine: "Pronto pra começar?",
                    mascotName: "mascote3"
                )

                intro
                    .padding(.horizontal, 20)

                collectedCard
                    .padding(.horizontal, 20)

                destinationCard
                    .padding(.horizontal, 20)

                healthKitNote
                    .padding(.horizontal, 20)

                acceptButton
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .appScreenBackground()
    }

    private var intro: some View {
        Text("""
        Para te lembrar de beber água nos melhores horários pra você, o Gole \
        aprende com o seu uso do app, em vez de seguir só um cronograma fixo. \
        Veja abaixo o que coletamos pra isso e como cuidamos desses dados.
        """)
        .font(AppFont.body)
        .foregroundStyle(.primary)
    }

    private var collectedCard: some View {
        VStack(spacing: 0) {
            cardHeader("O que é coletado")
            Divider().padding(.horizontal, 18)
            dataRow(icon: "heart.text.square", text: "Dados de saúde: seu sexo, sua idade, seu peso, sua altura e sua meta diária de hidratação.", isLast: false)
            dataRow(icon: "drop", text: "Cada registro de consumo de água, com data e hora, manual ou por notificação.", isLast: false)
            dataRow(icon: "bell.badge", text: "Horário e sua interação com cada notificação enviada.", isLast: false)
            dataRow(icon: "cloud.sun", text: "Temperatura e umidade do seu local nesses momentos. Sua localização é usada apenas para consultar o clima e nunca é enviada nem armazenada.", isLast: false)
            dataRow(icon: "hand.tap", text: "Quais telas e botões você abre dentro do app.", isLast: true)
        }
        .panelBackground()
    }

    private var destinationCard: some View {
        VStack(spacing: 0) {
            cardHeader("Para onde vai")
            Divider().padding(.horizontal, 18)
            dataRow(icon: "icloud", text: "Para uma base de dados no iCloud, à qual a equipe do Gole tem acesso para aprimorar o app e os lembretes.", isLast: false)
            dataRow(icon: "person.badge.shield.checkmark", text: "Associados a um identificador anônimo da sua conta iCloud, nunca ao seu nome, e-mail ou telefone.", isLast: true)
        }
        .panelBackground()
    }

    private var healthKitNote: some View {
        Text("""
        Se você conectar o app Saúde (opcional), ele passa a ler e escrever \
        somente seus registros de água. Nada do app Saúde é enviado para a base \
        de pesquisa.
        """)
        .font(AppFont.footnote)
        .foregroundStyle(Color.appSecondary)
    }

    private var acceptButton: some View {
        Button {
            Haptic.primary.play()
            onAccept()
        } label: {
            Text("Entendi, continuar")
                .font(AppFont.calloutStrong)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.gradientProminent)
    }

    private func cardHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func dataRow(icon: String, text: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: 20)
                Text(text)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            if !isLast {
                Divider().padding(.leading, 18 + 20 + 12)
            }
        }
    }
}

#Preview {
    ConsentView(onAccept: {})
}
