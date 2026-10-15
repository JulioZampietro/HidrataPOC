import Foundation
import SwiftData

/// One row per policy decision on a non-quiet slot, whether it sent or skipped.
/// This is the bandit's training table: context at decision time, the action, the
/// probability the policy had of taking it, and the outcome.
///
/// Compiled into both targets, like the other models: `PersistenceController`'s
/// schema (shared with the HydrationWidget extension) lists it. New model + optional
/// fields only, so SwiftData migrates lightly. Raw strings, as elsewhere: never
/// rename values.
@Model
final class SlotDecision {
    @Attribute(.unique) var id: UUID
    var userID: String
    var slotFiresAt: Date
    var decidedAt: Date
    var slotHour: Int
    var actionRaw: String            // "send" | "skip"
    var propensity: Double           // P(chosen action | context) under the logging policy
    var policyVersion: String
    var featuresJSON: String         // raw features exactly as the policy saw them
    var notificationVariant: String? // set by the scheduler once a "send" was shown
    var notificationEventID: String? // linked when the outcome is resolved

    /// Decisions are made ahead of time, but the one-reminder-at-a-time rule can still
    /// hold a slot back (an earlier reminder sat unanswered). Set by the scheduler once
    /// the slot's time passes: false = the rule let it through (the send was shown, or
    /// the skip would have been), true = the rule blocked it, so the logged action
    /// never reached the user. Only `false` rows are learned from; `true` and nil rows
    /// never get an outcome, so the Python pipeline drops them as unresolved too.
    var suppressed: Bool?
    var intakeInWindow: Bool?        // nil = not resolved yet
    var resolvedAt: Date?

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var ckSystemFields: Data?

    var isSend: Bool { actionRaw == "send" }

    init(userID: String, slotFiresAt: Date, decidedAt: Date, slotHour: Int, send: Bool,
         propensity: Double, policyVersion: String, featuresJSON: String) {
        self.id = UUID()
        self.userID = userID
        self.slotFiresAt = slotFiresAt
        self.decidedAt = decidedAt
        self.slotHour = slotHour
        self.actionRaw = send ? "send" : "skip"
        self.propensity = propensity
        self.policyVersion = policyVersion
        self.featuresJSON = featuresJSON
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}
