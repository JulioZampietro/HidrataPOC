import SwiftUI

struct ConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "drop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.appAccentText)
                    .accessibilityHidden(true)

                Text("Antes de começar")
                    .font(AppFont.largeTitle)

                Text("""
                Este é um app de teste (POC) usado para coletar dados de pesquisa. \
                O objetivo é aprender os melhores horários para lembrar você de beber \
                água — os dados coletados vão treinar, no futuro, um modelo que escolhe \
                esses horários automaticamente.
                """)
                .font(AppFont.body)

                Text("O QUE É COLETADO")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.appAccentText)
                    .tracking(1)

                VStack(alignment: .leading, spacing: 12) {
                    consentRow(icon: "heart.text.square", text: "Dados de saúde: seu sexo, uma faixa de idade (ex.: 30–34), seu IMC e sua meta diária de hidratação.")
                    consentRow(icon: "drop", text: "Cada registro de consumo de água, com data e hora, manual ou por notificação.")
                    consentRow(icon: "bell.badge", text: "Horário e sua interação com cada notificação enviada.")
                    consentRow(icon: "cloud.sun", text: "Temperatura e umidade do seu local nesses momentos. Sua localização é usada apenas para consultar o clima e nunca é enviada nem armazenada.")
                    consentRow(icon: "hand.tap", text: "Quais telas e botões você abre dentro do app.")
                }

                Text("PARA ONDE VAI")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.appAccentText)
                    .tracking(1)

                VStack(alignment: .leading, spacing: 12) {
                    consentRow(icon: "icloud", text: "Para uma base de pesquisa no iCloud, compartilhada entre os participantes do teste, à qual a equipe do estudo tem acesso.")
                    consentRow(icon: "person.badge.shield.checkmark", text: "Associados a um identificador anônimo da sua conta iCloud, nunca ao seu nome, e-mail ou telefone.")
                    consentRow(icon: "ruler", text: "Seu peso e sua altura exatos ficam só neste aparelho: a base de pesquisa recebe apenas o IMC calculado a partir deles.")
                }

                Text("""
                Você pode ver, exportar e apagar tudo que foi coletado a qualquer \
                momento, em Configurações ▸ Meus dados. Apagar remove os dados deste \
                aparelho e da base de pesquisa.

                Se você conectar o app Saúde (opcional), ele passa a ler e escrever \
                somente seus registros de água. Nada do app Saúde é enviado para a base \
                de pesquisa.
                """)
                .font(AppFont.footnote)
                .foregroundStyle(Color.appSecondary)

                Button {
                    Haptic.primary.play()
                    onAccept()
                } label: {
                    Text("Concordo em participar")
                        .font(AppFont.calloutStrong)
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding()
        }
        .appScreenBackground()
    }

    private func consentRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.appAccentText)
        }
        .font(AppFont.subheadline)
    }
}

#Preview {
    ConsentView(onAccept: {})
}
