import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("hasAcceptedConsent") private var hasAcceptedConsent = false
    @Environment(\.modelContext) private var modelContext
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
                .onAppear {
                    evaluateCheckin(for: profile)
                    startLiveActivityIfNeeded(for: profile)
                }
                .onChange(of: profile.userID) {
                    evaluateCheckin(for: profile)
                    startLiveActivityIfNeeded(for: profile)
                }
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

    /// FR-9: this view only ever shows once a profile exists, so `onAppear`/
    /// `onChange` here cover both a cold launch straight into the Home tab and the
    /// moment onboarding just created the profile — `HidrataPOCApp`'s scenePhase
    /// handler alone would miss both, since SwiftUI's `onChange(of: scenePhase)`
    /// doesn't fire for the phase already active at launch.
    private func startLiveActivityIfNeeded(for profile: UserProfile) {
        Task {
            await LiveActivityManager.shared.startIfNeeded(profile: profile, context: modelContext)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self, DailyCheckin.self], inMemory: true)
}
