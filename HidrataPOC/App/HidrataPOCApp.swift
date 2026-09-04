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
            }
            startForegroundTimer()
        case .background:
            stopForegroundTimer()
            BackgroundRefreshService.scheduleNext()
        default:
            break
        }
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
