import Foundation
import SwiftData

/// Owns the one `ModelContainer` for the app. Notification delegate callbacks and the
/// background refresh task run outside SwiftUI's view hierarchy, so they can't reach
/// `@Environment(\.modelContext)` — they read `PersistenceController.shared.context`
/// instead, which is the same container the app's `.modelContainer(_:)` scene
/// modifier uses, so both paths see the same data.
@MainActor
enum PersistenceController {
    static let container: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            DailyCheckin.self,
            IntakeLog.self,
            NotificationEvent.self,
        ])
        // `cloudKitDatabase: .none` disables SwiftData's own automatic CloudKit
        // mirroring — this app pushes to the CloudKit **public** database manually
        // via CloudKitSyncService instead (SwiftData's built-in integration only
        // mirrors to the private database, and would otherwise also force every
        // attribute optional/defaulted and forbid the `.unique` constraints below).
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}
