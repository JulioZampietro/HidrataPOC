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
    /// Trilha da barra de progresso: cinza-claro no light, azul-acinzentado escuro no dark.
    static func progressTrack(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.24, green: 0.30, blue: 0.40)
            : trackLight
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
    static let headerHeight: CGFloat = 40
    /// Space between the mascot and the container's bottom edge.
    static let mascotBottomPadding: CGFloat = 16
    /// Space between the container's top edge and the mascot at full size.
    static let mascotTopPadding: CGFloat = 20
    static let maxMascotHeight: CGFloat = 190

    /// The container hugs the full-size mascot; it only gets shorter on screens too
    /// short to fit everything else.
    static func waterHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        let fullHeight = mascotTopPadding + maxMascotHeight + mascotBottomPadding
        return min(max(height * 0.376, 160), fullHeight)
    }

    /// The mascot shrinks with the container on short screens, never past 190 pt.
    static func mascotHeight(forWaterHeight waterHeight: CGFloat) -> CGFloat {
        min(max(waterHeight - mascotTopPadding - mascotBottomPadding, 110), maxMascotHeight)
    }

    /// Height left for the screen's own content below the water container.
    static func contentHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        height - headerHeight - waterHeight(forVisibleHeight: height) - spacing * 3
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

    /// Cinza de ícones decorativos secundários (chevrons).
    static let appChevron = appSecondary

    /// Tracejado que separa linhas dos cartões do Perfil e dos tutoriais.
    static let appDivider = AppTheme.trackLight.opacity(0.6)
}
