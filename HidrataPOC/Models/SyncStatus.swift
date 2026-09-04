import Foundation

/// Local sync state for a record awaiting (or having completed) its CloudKit push.
/// Stored as a raw String on each @Model so SwiftData can persist it directly.
enum SyncStatus: String, Codable {
    case pending
    case synced
    case failed
}
