import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("hasAcceptedConsent") private var hasAcceptedConsent = false
    @Query private var profiles: [UserProfile]
    @Query private var checkins: [DailyCheckin]

    @State private var showingCheckin = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Group {
            if !hasAcceptedConsent {
                ConsentView(onAccept: {
                    hasAcceptedConsent = true
                    Task { await PermissionsCoordinator.requestAll() }
                })
            } else if let profile {
                TabView {
                    HomeView(profile: profile)
                        .tabItem { Label("Início", systemImage: "drop.fill") }
                    ProfileView(profile: profile)
                        .tabItem { Label("Perfil", systemImage: "person.fill") }
                }
                .sheet(isPresented: $showingCheckin) {
                    DailyCheckinView(userID: profile.userID, onDone: { showingCheckin = false })
                }
                .onAppear { evaluateCheckin(for: profile) }
                .onChange(of: profile.userID) { evaluateCheckin(for: profile) }
            } else {
                OnboardingView()
            }
        }
    }

    private func evaluateCheckin(for profile: UserProfile) {
        let hasToday = checkins.contains {
            $0.userID == profile.userID && Calendar.current.isDateInToday($0.dataReferencia)
        }
        showingCheckin = !hasToday
    }
}

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self, DailyCheckin.self], inMemory: true)
}
