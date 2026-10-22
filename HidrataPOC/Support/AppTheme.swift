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
        mascotStage(for: progress).map { "mascote\($0)" }
    }

    /// Estágio do mascote para o progresso: 5 (abaixo de 20%, o mais forte) a 1 (80–<100%,
    /// quase derrotado). nil em 100% (meta batida). Os thresholds ficam só aqui.
    static func mascotStage(for progress: Double) -> Int? {
        switch progress {
        case ..<0.20: return 5
        case ..<0.40: return 4
        case ..<0.60: return 3
        case ..<0.80: return 2
        case ..<1.0:  return 1
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

/// Vertical layout shared by Home and Histórico. There's no tab bar: the water
/// container is drawn once by `RootView`, fixed on top of both pages, starting `spacing`
/// below the Dynamic Island, with the header buttons on its top edge; below it, after
/// `spacing`, comes the page's own content, which ends `spacing` above the bottom safe
/// area. The content keeps the size it had when the tab bar existed and the water
/// container stretches to fill the rest, so both pages match. Below the minimums (very
/// short screens, large text) the container shrinks instead of the pages scrolling.
enum TabScreenLayout {
    static let spacing: CGFloat = 20
    /// 44 pt: o menor alvo de toque do HIG (os botões do cabeçalho).
    static let headerHeight: CGFloat = 44
    /// Inset of the header buttons from the container's edges.
    static let containerInset: CGFloat = 10
    /// Space between the mascot and the container's bottom edge.
    static let mascotBottomPadding: CGFloat = 0
    /// Space between the container's top edge and the mascot at full size.
    static let mascotTopPadding: CGFloat = 20
    static let maxMascotHeight: CGFloat = 190
    /// Room above the mascot for its speech bubble.
    static let speechBubbleAllowance: CGFloat = 38
    /// How far the Dynamic Island (or notch / status bar) ends above the top safe-area
    /// edge. There's no API for its frame; this matches the current iPhones.
    static let dynamicIslandClearance: CGFloat = 12
    /// Height the removed tab bar took above the bottom safe area. The content below
    /// the container is still sized as if it were there, so cards don't grow.
    static let removedTabBarHeight: CGFloat = 49
    /// Smallest content that fits below the container: Histórico's calendar card (and
    /// Home's bar + two rows of cards at their minimum).
    static let minContentHeight: CGFloat = 330
    /// Height the container held before the tab bar went away, as a share of the screen.
    private static let legacyWaterShare: CGFloat = 0.42
    private static let legacyExtraHeight: CGFloat = headerHeight + spacing + 40

    /// Distance from the top of the screen to the top of the water container.
    static func waterTop(safeAreaTop: CGFloat) -> CGFloat {
        max(safeAreaTop - dynamicIslandClearance, 0) + spacing
    }

    /// Height of the water container: everything between `waterTop` and the content
    /// below it. `visibleHeight` is the height between the safe areas.
    static func waterHeight(forVisibleHeight visibleHeight: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        let bottom = safeAreaTop + visibleHeight - spacing * 2 - contentHeight(forVisibleHeight: visibleHeight)
        return max(bottom - waterTop(safeAreaTop: safeAreaTop), minWaterHeight)
    }

    /// Home's progress bar and the grid of intake cards under it.
    static let progressBarHeight: CGFloat = 52
    static let intakeGridSpacing: CGFloat = 12

    /// Height of one row of intake cards (the two rows share what's left below the bar).
    static func intakeCardHeight(forVisibleHeight visibleHeight: CGFloat) -> CGFloat {
        let gridHeight = contentHeight(forVisibleHeight: visibleHeight) - progressBarHeight - spacing
        return max((gridHeight - intakeGridSpacing) / 2, 116)
    }

    /// Height of the water container on the minigame screen: it stretches down to a single
    /// row of buttons (one card row high), `spacing` above them. The bar and the first row of
    /// cards are gone, so the tank takes their room.
    static func gameWaterHeight(forVisibleHeight visibleHeight: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        waterHeight(forVisibleHeight: visibleHeight, safeAreaTop: safeAreaTop)
            + contentHeight(forVisibleHeight: visibleHeight)
            - intakeCardHeight(forVisibleHeight: visibleHeight)
    }

    /// The mascot fills the container below the header buttons (and the room its speech
    /// bubble needs above it), never past 190 pt.
    static func mascotHeight(forWaterHeight waterHeight: CGFloat) -> CGFloat {
        let slot = waterHeight - headerHeight - containerInset - speechBubbleAllowance
        return min(max(slot - mascotTopPadding - mascotBottomPadding, 110), maxMascotHeight)
    }

    /// Height for the page's own content below the water container — the same it had
    /// with the tab bar, so it only moves down instead of growing.
    static func contentHeight(forVisibleHeight visibleHeight: CGFloat) -> CGFloat {
        let tabBarHeight = visibleHeight - removedTabBarHeight
        let legacyHeight = tabBarHeight - legacyWaterHeight(forVisibleHeight: tabBarHeight) - spacing * 2
        return max(legacyHeight, minContentHeight)
    }

    private static let minWaterHeight: CGFloat = headerHeight + containerInset + speechBubbleAllowance + mascotTopPadding + 110

    /// The container's height in the old layout (tab bar below, header overlaid on it).
    private static func legacyWaterHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        let fullHeight = mascotTopPadding + maxMascotHeight + mascotBottomPadding + legacyExtraHeight
        return min(max(height * legacyWaterShare, 160), fullHeight)
    }
}

/// Botão redondo de Liquid Glass usado no topo do recipiente de água (compartilhar,
/// cosméticos e perfil). Fica por cima da água: o vidro enxerga a água atrás dele e não
/// ondula com a refração.
struct GlassCircleButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // o ícone cabe no círculo de 44 pt
                .foregroundStyle(Color.appAccentText)
                .frame(width: TabScreenLayout.headerHeight, height: TabScreenLayout.headerHeight)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .accessibilityLabel(accessibilityLabel)
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

    /// Mesmo azul de `appAccentText` no claro, mas FIXO (não adapta no escuro) — pra
    /// texto sobre uma superfície que também é sempre branca nos dois modos (ex.: o
    /// botão "Entender minha meta"). `appAccentText` ficaria claro demais no escuro
    /// contra esse branco fixo, já que foi calibrado pra contrastar com o fundo
    /// adaptável do app, não com branco literal.
    static let appAccentTextOnWhite = Color(red: 0.05, green: 0.34, blue: 0.82)

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

    /// Laranja e verde de aviso/sucesso legíveis sobre fundo claro.
    static let appWarning = adaptive(light: Color(red: 0.65, green: 0.32, blue: 0.0), dark: .orange)
    static let appSuccess = adaptive(light: Color(red: 0.08, green: 0.45, blue: 0.22), dark: .green)

    /// Dourado de destaque — não é o `appWarning` (pensado pra texto sobre fundo
    /// claro): este é fixo, calibrado pra chamar atenção especificamente sobre o
    /// gradiente de marca (ex. o "+ X mL" do clima no cartão da meta), onde um
    /// laranja escurecido pro claro ficaria apagado.
    static let appGoldHighlight = Color(red: 1.0, green: 0.78, blue: 0.30)

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

extension Color {
    /// As três paradas do gradiente de marca, nomeadas pra não duplicar os valores
    /// entre `LinearGradient.waterHeader` (as três, pra superfícies grandes) e
    /// `LinearGradient.waterHeaderCompact` (só as duas primeiras, pra selos
    /// pequenos — ver o comentário de `waterHeaderCompact`).
    fileprivate static let waterDeep = adaptive(
        light: Color(red: 0.06, green: 0.22, blue: 0.55),
        dark: Color(red: 0.05, green: 0.15, blue: 0.34)
    )
    fileprivate static let waterMid = adaptive(
        light: Color(red: 0.08, green: 0.40, blue: 0.93), // appAccent
        dark: Color(red: 0.12, green: 0.38, blue: 0.86)
    )
    fileprivate static let waterLight = adaptive(
        light: Color(red: 0.40, green: 0.70, blue: 0.99),
        dark: Color(red: 0.32, green: 0.56, blue: 0.90)
    )
}

extension LinearGradient {
    /// "Água profunda → superfície" — o gradiente de marca do app: cabeçalhos de
    /// tela cheia (`TankHeader`) e qualquer superfície que hoje seria um azul chapado
    /// (botões primários, barra de progresso). Cada parada é uma cor adaptável —
    /// resolve sozinha pro claro ou pro escuro, sem precisar de uma função ciente do
    /// `colorScheme`. No escuro as paradas são um pouco mais contidas (não só o
    /// claro escurecido) pra não "brilhar" demais sobre o fundo já escuro do app.
    static let waterHeader = LinearGradient(
        colors: [.waterDeep, .waterMid, .waterLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Só as duas primeiras paradas (sem a ponta clara) — pra selos pequenos como o
    /// `DropBadge`. Num `.fill()`, o gradiente se estica pra caber na própria forma,
    /// então numa forma de ~26×32 pt a versão de três paradas cobria a faixa inteira
    /// dentro de um espaço minúsculo e a ponta clara (`waterLight`) deixava o número
    /// branco sem contraste nenhum ali (~2,2:1, abaixo do mínimo). Com só
    /// `waterDeep`→`waterMid`, o texto branco fica em ≥5:1 em qualquer ponto da forma,
    /// nos dois modos.
    static let waterHeaderCompact = LinearGradient(
        colors: [.waterDeep, .waterMid],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Estilo de botão primário em gradiente — a versão "molhada" do `.borderedProminent`
/// de sempre, pros botões de ação principal que antes eram um azul chapado
/// (`Color.appAccent`). Respeita `isEnabled` (cinza sólido quando desabilitado, o
/// mesmo tratamento que `.tint(.gray)` dava antes) e dá feedback de toque por opacidade.
struct GradientProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(LinearGradient.waterHeader) : AnyShapeStyle(Color.gray))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == GradientProminentButtonStyle {
    static var gradientProminent: GradientProminentButtonStyle { GradientProminentButtonStyle() }
}

// MARK: - Cartões

extension View {
    /// Cartão "molhado": fundo azul bem claro com contorno fino, em vez de sombra —
    /// usado nas telas de marca forte (`TankHeader`) pra combinar com o gradiente do
    /// cabeçalho em vez do cartão neutro padrão do resto do app.
    func panelBackground(cornerRadius: CGFloat = 20, isVisible: Bool = true) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.appAccent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.appAccent.opacity(0.16), lineWidth: 1)
                )
                .opacity(isVisible ? 1 : 0)
        )
    }
}
