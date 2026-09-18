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
