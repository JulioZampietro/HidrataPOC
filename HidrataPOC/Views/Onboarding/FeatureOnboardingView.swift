import SwiftUI


struct FeatureOnboardingView: View {
    let onDismiss: () -> Void

    @State private var currentPage = 0

    private let pages: [FeaturePage] = [.actionButton, .siri]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index].view
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            footer
        }
        .appScreenBackground()
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

            // Profile hint (only on last page)
            if currentPage == pages.count - 1 {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.appAccentText)
                    Text("Acesse **Perfil** para ver isso novamente a qualquer momento.")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.appSecondary)
                }
                .padding(.horizontal, 32)
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Primary button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
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
        .padding(.bottom, 36)
        .padding(.top, 12)
    }
}

// MARK: - Page definitions

private enum FeaturePage {
    case actionButton
    case siri

    var view: some View {
        Group {
            switch self {
            case .actionButton:
                ScrollView(showsIndicators: false) {
                    ActionButtonStepsContent()
                        .padding(.bottom, 8)
                }
            case .siri:
                ScrollView(showsIndicators: false) {
                    SiriStepsContent()
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

#Preview {
    FeatureOnboardingView(onDismiss: {})
}
