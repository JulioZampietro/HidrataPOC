import Foundation
import SwiftData

/// Owns the one `ModelContainer`, shared by the app and the `HydrationWidget`
/// extension via an App Group — the extension's `LogIntakeIntent` writes an
/// `IntakeLog` here directly, so a Lock Screen / Dynamic Island tap shows up on the
/// Home screen immediately (there's no CloudKit pull-sync to fall back on). The app's
/// notification delegate callbacks and background refresh task run outside SwiftUI's
/// view hierarchy, so they also can't reach `@Environment(\.modelContext)` — they read
/// `PersistenceController.shared.context` instead.
@MainActor
enum PersistenceController {
    static let container: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            DailyCheckin.self,
            IntakeLog.self,
            NotificationEvent.self,
        ])
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupID) else {
            fatalError("App Group '\(Constants.appGroupID)' is not configured — check entitlements on both the app and HydrationWidget targets.")
        }
        // `cloudKitDatabase: .none` disables SwiftData's own automatic CloudKit
        // mirroring — this app pushes to the CloudKit **public** database manually
        // via CloudKitSyncService instead (SwiftData's built-in integration only
        // mirrors to the private database, and would otherwise also force every
        // attribute optional/defaulted and forbid the `.unique` constraints below).
        let configuration = ModelConfiguration(schema: schema, url: groupURL.appending(path: "HidrataPOC.sqlite"), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}
