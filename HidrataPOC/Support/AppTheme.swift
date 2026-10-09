import SwiftUI

/// Fundo de tela compartilhado entre as telas principais do app (Home e
/// Histórico), para que ambas fiquem alinhadas visualmente em light e dark
/// mode — um tom hardcoded único não funciona nos dois modos, então cada
/// modo tem sua própria cor explícita.
enum AppTheme {
    // As cores do app ficam em `Color.app*` (abaixo) — trocar uma cor é mexer só ali.
    static let screenBackgroundLight = Color(red: 0.90, green: 0.94, blue: 0.98)
    static let screenBackgroundDark = Color(red: 0.06, green: 0.08, blue: 0.13)

    static func screenBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? screenBackgroundDark : screenBackgroundLight
    }

    /// Retorna o nome do asset do mascote correspondente ao progresso diário,
    /// trocando a cada 20%: 0–20% → mascote5, 20–40% → mascote4, 40–60% → mascote3,
    /// 60–80% → mascote2, 80–<100% → mascote1. Em 100% (meta batida) retorna nil —
    /// o mascote some da tela.
    static func mascotImageName(for progress: Double) -> String? {
        switch progress {
        case ..<0.20: return "mascote5"
        case ..<0.40: return "mascote4"
        case ..<0.60: return "mascote3"
        case ..<0.80: return "mascote2"
        case ..<1.0:  return "mascote1"
        default:      return nil
        }
    }

    /// As imagens dos mascotes foram recortadas exatamente no contorno do
    /// personagem (sem fundo transparente). Como cada uma tinha uma proporção
    /// diferente de espaço vazio ao redor do personagem, recortar fez com que
    /// `scaledToFit()` as exibisse maiores do que antes. Este fator (altura do
    /// conteúdo ÷ altura do canvas original) é aplicado à altura do frame para
    /// que o mascote apareça do mesmo tamanho de antes do recorte.
    static func mascotSizeCorrection(for imageName: String) -> CGFloat {
        switch imageName {
        case "mascote1": return 0.6548
        case "mascote2": return 0.5224
        case "mascote3": return 0.7021
        case "mascote4": return 0.8446
        case "mascote5": return 0.9028
        default: return 1.0
        }
    }
}

private struct AppScreenBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(AppTheme.screenBackground(for: colorScheme).ignoresSafeArea())
    }
}

extension View {
    func appScreenBackground() -> some View {
        modifier(AppScreenBackgroundModifier())
    }
}

extension AppTheme {
    /// Trilha da barra de progresso: cinza-claro no light, azul-acinzentado bem escuro no
    /// dark. Os dois tons foram escolhidos para o preenchimento `appAccent` se destacar
    /// da trilha com ≥ 3:1 (WCAG 1.4.11) — 3,4:1 no claro e 3,2:1 no escuro — e o texto
    /// branco/escuro por cima seguir acima de 10:1.
    static func progressTrack(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.13, blue: 0.20)
            : Color(red: 0.80, green: 0.83, blue: 0.87)
    }

    static let trackLight = Color(red: 0.75, green: 0.78, blue: 0.82)
}

/// Vertical layout shared by Home and Histórico: header, water container, then the
/// screen's own content, with the same `spacing` between every block and below the
/// last one (above the tab bar). Sizes derive from the visible height, so the water
/// container is identical on both tabs and the bottom content fills exactly what's
/// left. Below the minimums (very short screens, large text) the screens scroll.
enum TabScreenLayout {
    static let spacing: CGFloat = 20
    /// 44 pt: o menor alvo de toque do HIG (o botão de compartilhar do cabeçalho).
    static let headerHeight: CGFloat = 44
    /// Space between the mascot and the container's bottom edge.
    static let mascotBottomPadding: CGFloat = 0
    /// Space between the container's top edge and the mascot at full size.
    static let mascotTopPadding: CGFloat = 20
    static let maxMascotHeight: CGFloat = 190
    /// Extra height added only to the container (as slack below the mascot's own
    /// padded area), so the water container can grow without the mascot growing
    /// with it — `mascotHeight` subtracts this back out before sizing the mascot.
    /// Sized to swallow exactly the space the header (streak + share button) used
    /// to take as its own row (`headerHeight + spacing`): the header now floats as
    /// an overlay on top of the container instead, so the container grows up into
    /// that reclaimed space and reaches near the top safe area.
    static let extraContainerHeight: CGFloat = headerHeight + spacing
    /// Altura a mais no aquário (tirada dos cartões de baixo), só como água acima do
    /// mascote — `mascotHeight` também desconta isso, então o mascote não cresce.
    static let extraTankHeight: CGFloat = 40

    /// The container hugs the full-size mascot (plus `extraContainerHeight` of
    /// slack, reclaimed from the header's old row); it only gets shorter on
    /// screens too short to fit everything else.
    static func waterHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        let fullHeight = mascotTopPadding + maxMascotHeight + mascotBottomPadding + extraContainerHeight + extraTankHeight
        return min(max(height * 0.42, 160), fullHeight)
    }

    /// The mascot shrinks with the container on short screens, never past 190 pt.
    /// `extraContainerHeight` is removed first so the extra slack never reaches the mascot.
    static func mascotHeight(forWaterHeight waterHeight: CGFloat) -> CGFloat {
        min(max(waterHeight - mascotTopPadding - mascotBottomPadding - extraContainerHeight - extraTankHeight, 110), maxMascotHeight)
    }

    /// Height left for the screen's own content below the water container. The
    /// header no longer has its own row (it overlays the container), so only the
    /// container and two gaps (above and below it) are subtracted.
    static func contentHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        height - waterHeight(forVisibleHeight: height) - spacing * 2
    }
}

// MARK: - Scroll sem bounce

extension View {
    /// Impede que o usuário arraste a tela inteira para baixo (o "bounce" do
    /// `UIScrollView` por trás do `ScrollView`). Quando o conteúdo não cabe na
    /// tela, o scroll continua funcionando normalmente — só some o elástico.
    func disableScrollBounce() -> some View {
        background(ScrollBounceDisabler())
    }
}

/// Sobe na hierarquia de views até achar o `UIScrollView` do `ScrollView` que
/// envolve esta view e desliga o `bounces` dele.
private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var current = uiView.superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    scrollView.bounces = false
                    return
                }
                current = view.superview
            }
        }
    }
}

// MARK: - Paleta

extension Color {
    /// Cor dinâmica: `light` no modo claro, `dark` no escuro.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    /// Azul de marca para **preenchimentos** (barra, cartões, botões, calendário).
    /// Com texto branco por cima dá 5,0:1.
    static let appAccent = Color(red: 0.08, green: 0.40, blue: 0.93)

    /// Azul para **texto e ícones** sobre o fundo do app / cartões (≥ 4,5:1 nos dois
    /// modos). Mais escuro que `appAccent` no claro e mais claro no escuro.
    static let appAccentText = adaptive(
        light: Color(red: 0.05, green: 0.34, blue: 0.82),
        dark: Color(red: 0.45, green: 0.70, blue: 1.0)
    )

    /// Texto secundário: no claro é mais escuro que o `.secondary` do sistema (que dá
    /// ~3,3:1 sobre os cartões); no escuro é o próprio `.secondary`.
    static let appSecondary = adaptive(
        light: Color(red: 0.33, green: 0.35, blue: 0.40),
        dark: Color(red: 0.60, green: 0.60, blue: 0.64)
    )

    /// Texto secundário "de marca" (azul-acinzentado) dos cartões de ingestão.
    static let appMutedInk = adaptive(
        light: Color(red: 0.28, green: 0.36, blue: 0.50),
        dark: Color(red: 0.60, green: 0.60, blue: 0.64)
    )

    /// Texto/ícone por cima da trilha da barra de progresso (parte ainda não preenchida).
    static let appOnTrack = adaptive(
        light: Color(red: 0.06, green: 0.08, blue: 0.13),
        dark: .white
    )

    /// Laranja e verde de aviso/sucesso legíveis sobre fundo claro.
    static let appWarning = adaptive(light: Color(red: 0.65, green: 0.32, blue: 0.0), dark: .orange)
    static let appSuccess = adaptive(light: Color(red: 0.08, green: 0.45, blue: 0.22), dark: .green)

    /// Vermelho de ações destrutivas (apagar): o `.red` do sistema dá ~3,3:1 sobre os
    /// cartões; estes passam de 4,5:1 nos dois modos.
    static let appDestructive = adaptive(
        light: Color(red: 0.745, green: 0.098, blue: 0.078),
        dark: Color(red: 1.0, green: 0.51, blue: 0.47)
    )

    /// Bolinhas de página inativas e contornos de controles: precisam de ≥ 3:1 contra o
    /// fundo (elemento gráfico, WCAG 1.4.11) — o `.secondary` a 30% dava ~1,5:1.
    static let appControlOutline = appSecondary.opacity(0.7)

    /// Cinza de ícones decorativos secundários (chevrons).
    static let appChevron = appSecondary

    /// Tracejado que separa linhas dos cartões do Perfil e dos tutoriais.
    static let appDivider = AppTheme.trackLight.opacity(0.6)
}

// MARK: - Cartões

extension View {
    /// Cartão de conteúdo padrão do app: fundo secundário do sistema com a sombra suave
    /// dos cartões do Perfil. Conteúdo não usa Liquid Glass — o vidro fica para controles
    /// e navegação (HIG).
    func appCardBackground(cornerRadius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}
