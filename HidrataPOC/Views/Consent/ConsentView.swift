import SwiftUI

struct ConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "drop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
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

                VStack(alignment: .leading, spacing: 12) {
                    consentRow(icon: "person.text.rectangle", text: "Idade, peso, altura e meta diária de hidratação.")
                    consentRow(icon: "drop", text: "Cada registro de consumo de água, manual ou por notificação.")
                    consentRow(icon: "bell.badge", text: "Horário e sua interação com cada notificação enviada.")
                    consentRow(icon: "cloud.sun", text: "Clima local no momento de cada notificação.")
                }

                Text("Nenhum dado de saúde sensível (sono via wearable, batimentos, etc.) é coletado. Os dados ficam associados a um identificador anônimo, não ao seu nome.")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appSecondary)

                Button {
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
                .foregroundStyle(.blue)
        }
        .font(AppFont.subheadline)
    }
}

#Preview {
    ConsentView(onAccept: {})
}
