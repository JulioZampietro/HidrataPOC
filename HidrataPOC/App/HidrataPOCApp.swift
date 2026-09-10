import SwiftData
import SwiftUI
import UserNotifications

@main
struct HidrataPOCApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundTimer: Timer?

    // UNUserNotificationCenter keeps only a weak reference to its delegate.
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationScheduler.shared.registerCategories()
        BackgroundRefreshService.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await setUpOnLaunch() }
        }
        .modelContainer(PersistenceController.container)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func setUpOnLaunch() async {
        // Only prompt for permissions once the tester has already accepted the
        // consent screen in a prior session — never on the very first launch, before
        // they've agreed to participate.
        if UserDefaults.standard.bool(forKey: "hasAcceptedConsent") {
            await PermissionsCoordinator.requestAll()
        }
        NotificationScheduler.shared.ensureTodayScheduled()
        await CloudKitSyncService.shared.flushPending(context: PersistenceController.context)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            NotificationScheduler.shared.ensureTodayScheduled()
            Task {
                await CloudKitSyncService.shared.flushPending(context: PersistenceController.context)
                await NotificationScheduler.shared.tick()
                await refreshLiveActivity()
            }
            startForegroundTimer()
        case .background:
            stopForegroundTimer()
            BackgroundRefreshService.scheduleNext()
        default:
            break
        }
    }

    /// FR-9/FR-10 — only meaningful once onboarding has created a profile (mirrors
    /// the guard in `NotificationScheduler.ensureTodayScheduled`).
    private func refreshLiveActivity() async {
        guard let profile = try? PersistenceController.context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        await LiveActivityManager.shared.startIfNeeded(profile: profile, context: PersistenceController.context)
        await LiveActivityManager.shared.restartIfNearingLimit()
    }

    private func startForegroundTimer() {
        guard foregroundTimer == nil else { return }
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await NotificationScheduler.shared.tick()
            }
        }
    }

    private func stopForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }
}
