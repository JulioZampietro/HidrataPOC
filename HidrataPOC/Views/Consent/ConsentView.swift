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
                    .font(.largeTitle.bold())

                Text("""
                Este é um app de teste (POC) usado para coletar dados de pesquisa. \
                O objetivo é aprender os melhores horários para lembrar você de beber \
                água — os dados coletados vão treinar, no futuro, um modelo que escolhe \
                esses horários automaticamente.
                """)
                .font(.body)

                VStack(alignment: .leading, spacing: 12) {
                    consentRow(icon: "person.text.rectangle", text: "Idade, peso, altura e meta diária de hidratação.")
                    consentRow(icon: "drop", text: "Cada registro de consumo de água, manual ou por notificação.")
                    consentRow(icon: "bell.badge", text: "Horário e sua interação com cada notificação enviada.")
                    consentRow(icon: "cloud.sun", text: "Clima local e se você está ocupado (sem detalhes da sua agenda) no momento de cada notificação.")
                }

                Text("Nenhum dado de saúde sensível (sono via wearable, batimentos, etc.) é coletado. Os dados ficam associados a um identificador anônimo, não ao seu nome.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Concordo em participar") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private func consentRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.blue)
        }
        .font(.subheadline)
    }
}

#Preview {
    ConsentView(onAccept: {})
}
