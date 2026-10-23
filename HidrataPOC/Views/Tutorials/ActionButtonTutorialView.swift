import AVFoundation
import SwiftUI
import UIKit


struct ActionButtonTutorialView: View {
    var body: some View {
        TankSheet {
            VStack(spacing: 14) {
                ActionButtonStepsContent(showsMascotLine: false).header(showsSubtitle: false)
                ActionButtonSetupVideoView()
                    .padding(.horizontal, 90)
                subtitle
                    .padding(.horizontal, 20)
                openSettingsButton
                    .padding(.horizontal, 90)
            }
            .padding(.bottom, 16)
        }
    }

    private var subtitle: some View {
        VStack(spacing: 6) {
            Text(ActionButtonStepsContent.subtitle)
                .font(AppFont.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Acesse Ajustes > Botão de ação > Controle > Escolha um Controle > Pesquise Gole > Adicione uma ação")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openSettingsButton: some View {
        Button(action: openActionButtonSettings) {
            Text("Abrir Ajustes")
                .font(AppFont.calloutStrong)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.gradientProminent)
    }

    private func openActionButtonSettings() {
        Haptic.tap.play()
        // App-Prefs: (sem caminho) abre o Ajustes na raiz.
        // Fallback para a página do próprio app se não funcionar.
        if let url = URL(string: "App-Prefs:") {
            UIApplication.shared.open(url) { success in
                if !success, let fallback = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(fallback)
                }
            }
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Gravação de tela mostrando o passo a passo no Ajustes, no lugar do texto —
/// sem os controles nativos do player (barra de progresso, fundo preto): só a
/// imagem do vídeo, direto sobre o fundo da sheet, em loop contínuo.
struct ActionButtonSetupVideoView: View {
    /// Proporção real da gravação (880×1812) — evita barras pretas de letterbox.
    private static let aspectRatio: CGFloat = 880.0 / 1812.0

    private let player: AVPlayer

    init() {
        if let url = Bundle.main.url(forResource: "action-button-setup", withExtension: "mov") {
            player = AVPlayer(url: url)
        } else {
            player = AVPlayer()
        }
    }

    /// A gravação em si já é um mockup de iPhone fotorrealista sobre fundo preto —
    /// as "pontas pretas" são o fundo vazando nos cantos onde o aparelho (que tem
    /// cantos bem arredondados) não alcança o retângulo do vídeo. Um raio pequeno
    /// não dava conta disso, então o raio aqui acompanha o tamanho real renderizado
    /// (~22% da largura) pra cortar fora o fundo preto inteiro, não só "arredondar".
    private static let cornerRadiusFraction: CGFloat = 0.20

    var body: some View {
        GeometryReader { geo in
            PlayerLayerView(player: player)
                .clipShape(RoundedRectangle(cornerRadius: geo.size.width * Self.cornerRadiusFraction, style: .continuous))
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in player.play() }
        }
    }
}

/// Casca fina sobre `AVPlayerLayer`, sem nenhum controle nativo — o `VideoPlayer`
/// do SwiftUI/AVKit sempre desenha um fundo preto e a barra de play/pause, o que
/// aqui pareceria um player encaixado na sheet em vez de parte dela.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

/// Conteúdo compartilhado entre a sheet de tutorial (esta, mais o botão "Abrir
/// Ajustes") e a página equivalente do onboarding de primeiro uso
/// (`FeatureOnboardingView`) — mesma cópia nos dois lugares, um único lugar pra editar.
struct ActionButtonStepsContent: View {
    /// A sheet standalone (acessada pelo Perfil) não mostra a fala do mascote —
    /// só o onboarding de primeiro uso, onde ele ainda está "se apresentando".
    var showsMascotLine: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            header()
            cards
        }
    }

    /// Mesma string usada no header; exposta pra sheets que preferem mostrá-la fora
    /// dele (ver `ActionButtonTutorialView`), em vez de duplicar o texto.
    static let subtitle = "Registre água com um toque lateral — sem desbloquear o iPhone."

    /// Separados pra o onboarding poder desenhar o fundo azul fixo e paginar só
    /// texto/mascote e cards por cima dele. `showsSubtitle: false` tira a linha de
    /// descrição do header, pra quem vai mostrá-la em outro lugar da tela.
    func header(showsBackground: Bool = true, showsSubtitle: Bool = true) -> some View {
        CurrentMascotTankHeader(
            title: "Botão de Ação",
            subtitle: showsSubtitle ? Self.subtitle : nil,
            mascotLine: showsMascotLine ? "Um toque e já era? Isso não é justo." : nil,
            showsBackground: showsBackground
        )
    }

    var cards: some View {
        stepsCard
            .padding(.horizontal, 20)
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(number: 1,
                    title: "Abra o app Ajustes",
                    detail: "Vá até o aplicativo Ajustes no seu iPhone.",
                    isLast: false)
            stepRow(number: 2,
                    title: "Toque em \"Botão de Ação\"",
                    detail: "Role até encontrar a opção Botão de Ação.",
                    isLast: false)
            stepRow(number: 3,
                    title: "Selecione \"Controles\"",
                    detail: "Deslize as opções até chegar em Controles e toque para selecionar.",
                    isLast: false)
            stepRow(number: 4,
                    title: "Adicione os controles do Gole",
                    detail: "Em \"Controles disponíveis\", encontre Gole e adicione os controles de hidratação que quiser.",
                    isLast: true)
        }
        .panelBackground()
    }

    private func stepRow(number: Int, title: String, detail: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                DropBadge(number: number)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !isLast {
                Divider().padding(.leading, 18 + 26 + 14)
            }
        }
    }
}

#Preview {
    ActionButtonTutorialView()
}
