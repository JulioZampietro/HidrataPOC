import SwiftUI
import WeatherKit

/// Exigida pela Apple (guideline 5.2.5) em qualquer tela que mostre dado derivado do
/// WeatherKit: a marca "Weather" e um link para a página legal de atribuição, perto
/// do dado exibido. Usada no `GoalExplainerView`, onde a meta ajustada pelo clima
/// aparece para o usuário.
struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        if let attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
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
