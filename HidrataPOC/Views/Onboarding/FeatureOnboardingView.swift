import SwiftUI


struct FeatureOnboardingView: View {
    let onDismiss: () -> Void

    /// Posição do pager (id da página visível). Opcional porque é assim que o
    /// `scrollPosition(id:)` funciona; `currentPage` dá o valor já resolvido.
    @State private var scrolledPage: Int? = 0

    private let pages: [FeaturePage] = [.actionButton, .siri]

    /// Altura do bloco azul (da base da status bar até o ponto mais baixo da onda).
    /// É a mesma nas duas páginas e o fundo é único e fixo — só o texto e os cards
    /// deslizam —, então o azul lê como uma imagem só durante o arrasto.
    private let headerHeight: CGFloat = 250

    private var currentPage: Int { scrolledPage ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                headerBackground
                pager
            }

            footer
        }
        .appScreenBackground()
        .haptic(.selection, on: currentPage) // vale para o arrasto e para o botão "Próximo"
    }

    // MARK: - Pager

    /// Fundo azul fixo, sangrando até o topo real da tela (por baixo da status bar).
    private var headerBackground: some View {
        Color.clear
            .frame(height: headerHeight)
            .background(alignment: .top) {
                LinearGradient.waterHeader
                    .clipShape(WaveShape())
                    .ignoresSafeArea(edges: .top)
            }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    page(pages[index])
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content.opacity(1 - abs(phase.value) * 0.6)
                        }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledPage)
        .scrollIndicators(.hidden)
    }

    private func page(_ page: FeaturePage) -> some View {
        VStack(spacing: 0) {
            page.header
                .frame(height: headerHeight - 16, alignment: .center) // 16 = amplitude da onda

            ScrollView {
                page.cards
                    .padding(.top, 32)
                    .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            // Ao rolar, os cards somem rente à onda em vez de passar por cima do azul.
            .mask(BelowWaveShape())
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            // Dot indicator
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.appAccent : Color.appControlOutline)
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Settings hint (nas duas páginas)
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Color.appAccentText)
                Text("Acesse **Configurações** para ver isso novamente.")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appSecondary)
            }
            .padding(.horizontal, 32)
            .multilineTextAlignment(.center)

            // Primary button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation(.smooth) { scrolledPage = currentPage + 1 }
                } else {
                    Haptic.success.play()
                    onDismiss()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Próximo" : "Começar")
                    .font(AppFont.calloutStrong)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent)
            .animation(.easeInOut, value: currentPage)
        }
        // Negativo de propósito: o rodapé inteiro (pontos, dica e botão) desce um
        // pouco pra dentro da área da barra de início, na mesma altura em que a tab
        // bar flutuante do sistema fica — sem encostar no indicador.
        .padding(.bottom, -14)
        .padding(.top, 12)
    }
}

// MARK: - Page definitions

@MainActor
private enum FeaturePage {
    case actionButton
    case siri

    /// Texto + mascote, sem fundo — o fundo azul é do `FeatureOnboardingView`.
    var header: some View {
        Group {
            switch self {
            case .actionButton: ActionButtonStepsContent().header(showsBackground: false)
            case .siri: SiriStepsContent().header(showsBackground: false)
            }
        }
    }

    var cards: some View {
        Group {
            switch self {
            case .actionButton: ActionButtonStepsContent().cards
            case .siri: SiriStepsContent().cards
            }
        }
    }
}

#Preview {
    FeatureOnboardingView(onDismiss: {})
}
