import AVFoundation
import SwiftUI
import UIKit


struct ActionButtonTutorialView: View {
    var body: some View {
        TankSheet {
            ActionButtonStepsContent(showsMascotLine: false)
                .padding(.bottom, 16)
        }
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
        // O app backgroundeia ao abrir o Ajustes (botão abaixo); sem app de vídeo em
        // background, o sistema pausa o player sozinho, e ele não volta a tocar
        // sozinho quando o usuário retorna — precisa pedir de novo explicitamente.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            player.play()
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

/// Conteúdo compartilhado entre a sheet de tutorial (acessada pelo Perfil) e a
/// página equivalente do onboarding de primeiro uso (`FeatureOnboardingView`) —
/// mesmo vídeo, cópia e botão "Abrir ajustes" nos dois lugares, um único lugar pra editar.
struct ActionButtonStepsContent: View {
    /// A sheet standalone (acessada pelo Perfil) não mostra a fala do mascote —
    /// só o onboarding de primeiro uso, onde ele ainda está "se apresentando".
    var showsMascotLine: Bool = true

    var body: some View {
        VStack(spacing: 14) {
            header()
            cards
        }
    }

    private static let subtitle = "Registre água com um toque lateral — sem desbloquear o iPhone."

    /// Separados pra o onboarding poder desenhar o fundo azul fixo e paginar só
    /// texto/mascote e cards por cima dele. A descrição não entra no header: ela
    /// aparece abaixo do vídeo (ver `cards`).
    func header(showsBackground: Bool = true) -> some View {
        CurrentMascotTankHeader(
            title: "Botão de Ação",
            mascotLine: showsMascotLine ? "Um toque e já era? Isso não é justo." : nil,
            showsBackground: showsBackground
        )
    }

    var cards: some View {
        VStack(spacing: 14) {
            ActionButtonSetupVideoView()
                .padding(.horizontal, 90)
            instructions
                .padding(.horizontal, 20)
            openSettingsButton
                .padding(.horizontal, 90)
        }
    }

    private var instructions: some View {
        VStack(spacing: 6) {
            Text(Self.subtitle)
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
            Text("Abrir ajustes")
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

#Preview {
    ActionButtonTutorialView()
}
