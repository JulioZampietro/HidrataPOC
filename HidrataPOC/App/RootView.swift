import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("hasAcceptedConsent") private var hasAcceptedConsent = false
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
            } else {
                OnboardingView()
            }
        }
    }

    @ViewBuilder
    private func mainContent(profile: UserProfile) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: HomeView(profile: profile)
                case 1: HistoricoView(profile: profile)
                default: ProfileView(profile: profile)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }

            AppTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func startLiveActivityIfNeeded(for profile: UserProfile) {
        Task {
            await LiveActivityManager.shared.startIfNeeded(profile: profile, context: modelContext)
        }
    }
}

// MARK: - AppTabBar

private let tabBarBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

struct AppTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("drop.fill", "Home"),
        ("square.grid.3x3.fill", "Histórico"),
        ("person.fill", "Perfil"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                tabItem(index: index)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func tabItem(index: Int) -> some View {
        let item = items[index]
        let isSelected = selectedTab == index

        return Button {
            selectedTab = index
        } label: {
            if isSelected {
                VStack(spacing: 3) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(item.label)
                        .font(.custom("Nunito", size: 12).weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tabBarBlue, in: RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 3) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18))
                    Text(item.label)
                        .font(.custom("Nunito", size: 12))
                }
                .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.63))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
