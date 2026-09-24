import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("hasAcceptedConsent") private var hasAcceptedConsent = false
    @AppStorage("hasSeenFeatureOnboarding") private var hasSeenFeatureOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var selectedTab = 0

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Group {
            if !hasAcceptedConsent {
                ConsentView(onAccept: {
                    hasAcceptedConsent = true
                    Task { await PermissionsCoordinator.requestAll() }
                })
            } else if let profile {
                mainContent(profile: profile)
                    .onAppear { startLiveActivityIfNeeded(for: profile) }
                    .onChange(of: profile.userID) { startLiveActivityIfNeeded(for: profile) }
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasSeenFeatureOnboarding },
                        set: { _ in }
                    )) {
                        FeatureOnboardingView { hasSeenFeatureOnboarding = true }
                    }
            } else {
                OnboardingView()
            }
        }
    }

    /// Tab bar nativa: no iOS 26 ela já é Liquid Glass (flutuante, com o realce
    /// de seleção e o comportamento de scroll do sistema).
    private func mainContent(profile: UserProfile) -> some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "drop.fill", value: 0) {
                HomeView(profile: profile)
            }
            Tab("Histórico", systemImage: "square.grid.3x3.fill", value: 1) {
                HistoricoView(profile: profile)
            }
            Tab("Perfil", systemImage: "person.fill", value: 2) {
                ProfileView(profile: profile)
            }
        }
        .tint(tabBarBlue)
    }

    private func startLiveActivityIfNeeded(for profile: UserProfile) {
        Task {
            await LiveActivityManager.shared.startIfNeeded(profile: profile, context: modelContext)
        }
    }
}

private let tabBarBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
