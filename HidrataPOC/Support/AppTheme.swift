import SwiftUI

/// Fundo de tela compartilhado entre as telas principais do app (Home e
/// Histórico), para que ambas fiquem alinhadas visualmente em light e dark
/// mode — um tom hardcoded único não funciona nos dois modos, então cada
/// modo tem sua própria cor explícita.
enum AppTheme {
    static let screenBackgroundLight = Color(red: 0.90, green: 0.94, blue: 0.98)
    static let screenBackgroundDark = Color(red: 0.06, green: 0.08, blue: 0.13)

    static func screenBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? screenBackgroundDark : screenBackgroundLight
    }

    /// Retorna o nome do asset do mascote correspondente ao progresso diário.
    /// 0–25% → mascote5, 25–50% → mascote4, 50–75% → mascote3,
    /// 75–<100% → mascote2, 100% → mascote1 (meta batida).
    static func mascotImageName(for progress: Double) -> String {
        switch progress {
        case ..<0.25: return "mascote5"
        case ..<0.50: return "mascote4"
        case ..<0.75: return "mascote3"
        case ..<1.0:  return "mascote2"
        default:      return "mascote1"
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
            : Color(red: 0.75, green: 0.78, blue: 0.82)
    }
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
    static let mascotTopPadding: CGFloat = 15
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
