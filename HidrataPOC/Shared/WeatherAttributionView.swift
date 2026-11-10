import SwiftUI
import WeatherKit

/// Exigida pela Apple (guideline 5.2.5) em qualquer tela que mostre dado derivado do
/// WeatherKit: a marca "Weather" e um link para a página legal de atribuição, perto
/// do dado exibido. Usada em todo lugar em que a meta ajustada pelo clima aparece
/// (`ProfileView.goalCard` e `GoalExplainerView`).
struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    /// `nil` segue o esquema de cores do sistema (telas com fundo claro/escuro normal).
    /// Passe `true`/`false` em fundos com cor fixa (ex.: o cartão com gradiente azul
    /// da Home/Profile), que não acompanham o modo claro/escuro do sistema.
    var onDarkBackground: Bool? = nil
    @State private var attribution: WeatherAttribution?

    private var usesDarkMark: Bool {
        onDarkBackground ?? (colorScheme == .dark)
    }

    var body: some View {
        if let attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(url: usesDarkMark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    EmptyView()
                }
                .frame(height: 12)
            }
        } else {
            Color.clear
                .frame(height: 12)
                .task {
                    attribution = try? await WeatherService.shared.attribution
                }
        }
    }
}
