import SwiftUI
import UserNotifications

/// Tela do cartão "Configurar lembretes", que antes não abria nada.
///
/// Não inventa controles: quem decide os horários é a política de envio
/// (`PolicyCoordinator`), que aprende por usuário, e o único ajuste que existe de fato
/// é a permissão de notificação do sistema. Então a tela explica como o horário é
/// escolhido, mostra o estado da permissão e leva aos Ajustes do iOS quando ela está
/// negada — que é o caso em que o usuário realmente não recebe nada.
struct RemindersView: View {
    @State private var authorizationStatus: UNAuthorizationStatus?

    private var slotHours: [Int] {
        PolicyStore.shared.loadParams()?.slotHours.sorted() ?? Constants.notificationFixedHours
    }

    private var quietWindowText: String {
        let params = PolicyStore.shared.loadParams()
        let start = (params?.quietStartMinute ?? QuietHours.defaultStartMinute) / 60
        let end = (params?.quietEndMinute ?? QuietHours.defaultEndMinute) / 60
        return "\(start)h às \(end)h"
    }

    var body: some View {
        TankSheet {
            VStack(spacing: 20) {
                CurrentMascotTankHeader(
                    title: "Lembretes",
                    subtitle: "O monstro te provoca quando você esquece de beber — e aprende a hora em que isso funciona com você."
                )

                VStack(alignment: .leading, spacing: 16) {
                    permissionSection
                    howItWorksSection
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .task { authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    // MARK: - Permissão

    @ViewBuilder
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERMISSÃO")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.appAccentText)
                .tracking(1)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAllowed ? Color.appSuccess : Color.appWarning)
                        .frame(width: 7, height: 7)
                    Text(permissionLabel)
                        .font(AppFont.callout)
                        .foregroundStyle(.primary)
                }

                if authorizationStatus != nil, !isAllowed {
                    Text("Sem a permissão, nenhum lembrete é entregue — e os horários não têm como ser aprendidos.")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Haptic.tap.play()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Abrir os Ajustes")
                            .font(AppFont.calloutStrong)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.gradientProminent)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground()
        }
    }

    private var isAllowed: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case nil: "Verificando…"
        case .notDetermined: "Ainda não pedida"
        case .denied: "Negada nos Ajustes"
        default: isAllowed ? "Liberada" : "Indisponível"
        }
    }

    // MARK: - Como funciona

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMO O HORÁRIO É ESCOLHIDO")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.appAccentText)
                .tracking(1)

            VStack(spacing: 0) {
                infoRow(
                    icon: "clock",
                    text: "Os lembretes só podem sair nestes horários: \(slotHours.map { "\($0)h" }.joined(separator: ", "))."
                )
                Divider().padding(.leading, 50)
                infoRow(
                    icon: "wand.and.stars",
                    text: "Entre eles, o app aprende com o seu histórico quais realmente te fazem beber água — e deixa de mandar nos que não funcionam."
                )
                Divider().padding(.leading, 50)
                infoRow(
                    icon: "moon.zzz",
                    text: "Nada é enviado entre \(quietWindowText)."
                )
                Divider().padding(.leading, 50)
                infoRow(
                    icon: "bell.badge",
                    text: "Um lembrete por vez: enquanto você não responde a um, o próximo não é enviado. O primeiro da manhã sempre sai."
                )
                Divider().padding(.leading, 50)
                infoRow(
                    icon: "thermometer.sun",
                    text: "A frase e o mascote mudam com o clima, a hora e o quanto você já bebeu no dia."
                )
            }
            .panelBackground()
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
