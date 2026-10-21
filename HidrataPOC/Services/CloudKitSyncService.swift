import CloudKit
import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.hidratapoc", category: "CloudKitSyncService")

/// Pushes local SwiftData records to the CloudKit **public** database, one record type
/// per method. SwiftData is the source of truth on-device; this service is a thin,
/// best-effort sync layer on top of it — every push failure just leaves the local
/// `syncStatus` as `.pending`/`.failed` for `flushPending` to retry later.
///
/// Uses the public database (not private) because the goal is a dataset the developer
/// can read across every TestFlight tester, aggregated in one place — see the CloudKit
/// Dashboard Security Roles setup in the project README for the corresponding
/// "Authenticated: Create only, no Read" role, which must be configured manually in
/// the dashboard (not something this app can do from code).
///
/// The same records also back the restore after a reinstall or on another device
/// (`syncFromCloud`): CloudKit's default **Creator** role keeps read/write on the
/// records a user created, so a device can query its own user's rows by `userID`
/// even though the Authenticated role has no Read.
///
/// Note: the "Create only, no Read" role also means a device can't *fetch* someone
/// else's record to delete it — but `CKDatabase.delete(withRecordID:)` doesn't need
/// read access to the record, only its ID, which every device already has locally.
@MainActor
final class CloudKitSyncService {
    static let shared = CloudKitSyncService()

    private let container: CKContainer
    private var cachedUserID: String?

    /// A delete that failed (offline, etc.) — retried by `flushPending`. Unlike a
    /// failed push, the local row is already gone by the time this is queued, so it
    /// can't be recovered by re-scanning SwiftData; it has to be tracked separately.
    private struct PendingDeletion: Codable {
        let recordType: String
        let recordName: String
    }
    private let pendingDeletionsKey = "pendingCloudKitDeletions"

    private init() {
        container = CKContainer(identifier: Constants.cloudKitContainerID)
    }

    /// Stable, anonymous per-user identifier from CloudKit — no login system needed.
    func currentUserID() async throws -> String {
        if let cachedUserID { return cachedUserID }
        let recordID = try await container.userRecordID()
        cachedUserID = recordID.recordName
        return recordID.recordName
    }

    /// Same as `currentUserID()`, but falls back to a locally-generated, cached UUID
    /// when no iCloud account is available (e.g. testing without sign-in), so
    /// onboarding never blocks on CloudKit being reachable. Data tagged with the
    /// fallback ID still syncs once pushed — it just won't match a real iCloud user.
    func resolvedUserID() async -> String {
        do {
            return try await currentUserID()
        } catch {
            logger.error("currentUserID() failed, falling back to a local-only ID: \(String(describing: error), privacy: .public)")
        }
        let key = "localFallbackUserID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    // MARK: - Per-type pushes

    /// Pseudonymized on purpose: this record lands in the **public** database, so it
    /// carries only what the offline model actually consumes (see
    /// `ml/python/dataset.py::_profile_features` — `bmi`, `age`, `female`, `goal_l`),
    /// never the raw anthropometrics. Exact weight + height + age + sex together are a
    /// quasi-identifier; BMI and a 5-year age band keep the model's inputs while
    /// dropping the combination that singles a participant out. `generoAutoDeclarado`
    /// (free text) is never pushed at all.
    ///
    /// Consequence for restore (`applyProfile`): a fresh install recovers the goal,
    /// sex, time zone and custom amount, but not exact weight/height/age — those stay
    /// on-device only. The age band's midpoint is used as an approximation.
    func push(_ profile: UserProfile) async {
        let record = existingOrNewRecord(type: "UserProfile", id: profile.id, systemFields: profile.ckSystemFields)
        record["userID"] = profile.userID
        record["faixaIdade"] = Self.ageBand(profile.idade)
        record["genero"] = profile.genero
        record["bmi"] = Self.bmi(pesoKg: profile.pesoKg, alturaCm: profile.alturaCm)
        record["fusoHorario"] = profile.fusoHorario
        record["metaDiariaML"] = profile.metaDiariaML
        record["customIntakeML"] = profile.customIntakeML
        record["criadoEm"] = profile.criadoEm
        record["atualizadoEm"] = profile.atualizadoEm

        do {
            let saved = try await saveResolvingConflict(record)
            profile.ckSystemFields = archivedSystemFields(saved)
            profile.syncStatus = .synced
        } catch let error as CKError where error.code == .serverRecordChanged && error.serverRecord != nil {
            // Another device (same iCloud account) updated this record since our last
            // save — adopt the server's change tag and let the next flush overwrite it.
            profile.ckSystemFields = error.serverRecord.map(archivedSystemFields)
            profile.syncStatus = .failed
        } catch {
            logger.error("Failed to push UserProfile \(profile.id, privacy: .public): \(String(describing: error), privacy: .public)")
            profile.syncStatus = .failed
        }
    }

    func push(_ log: IntakeLog) async {
        guard log.syncStatus != .synced else { return }
        let record = CKRecord(recordType: "IntakeLog", recordID: recordID(for: log.id))
        record["userID"] = log.userID
        record["timestamp"] = log.timestamp
        record["volumeML"] = log.volumeML
        record["tipoEntrada"] = log.tipoEntrada
        record["origem"] = log.origem
        record["notificationEventID"] = log.notificationEventID
        record["temperaturaC"] = log.temperaturaC
        record["umidadeRelativa"] = log.umidadeRelativa
        record["sensacaoTermicaC"] = log.sensacaoTermicaC
        record["source"] = log.source
        record["healthKitUUID"] = log.healthKitUUID

        do {
            _ = try await container.publicCloudDatabase.save(record)
            log.syncStatus = .synced
        } catch let error as CKError where error.code == .serverRecordChanged {
            // O registro já existe no servidor com este ID — outro push chegou antes.
            // Para IntakeLog (imutável após criação), isso equivale a "sincronizado".
            log.syncStatus = .synced
        } catch {
            logger.error("Failed to push IntakeLog \(log.id, privacy: .public): \(String(describing: error), privacy: .public)")
            log.syncStatus = .failed
        }
    }

    func push(_ event: NotificationEvent) async {
        let record = existingOrNewRecord(type: "NotificationEvent", id: event.id, systemFields: event.ckSystemFields)
        record["userID"] = event.userID
        record["sentAt"] = event.sentAt
        record["diaSemana"] = event.diaSemana
        record["fimDeSemana"] = event.fimDeSemana
        record["feriado"] = event.feriado
        record["temperaturaC"] = event.temperaturaC
        record["umidadeRelativa"] = event.umidadeRelativa
        record["sensacaoTermicaC"] = event.sensacaoTermicaC
        record["ocupadoNoMomento"] = event.ocupadoNoMomento
        record["densidadeEventosDia"] = event.densidadeEventosDia
        record["deficitAcumuladoML"] = event.deficitAcumuladoML
        record["tempoDesdeUltimoRegistroMin"] = event.tempoDesdeUltimoRegistroMin
        record["statusInteracao"] = event.statusInteracao
        record["tempoAteAgirMin"] = event.tempoAteAgirMin
        record["resultouEmConsumo"] = event.resultouEmConsumo
        record["notificationVariant"] = event.notificationVariant

        do {
            let saved = try await saveResolvingConflict(record)
            event.ckSystemFields = archivedSystemFields(saved)
            event.syncStatus = .synced
        } catch {
            logger.error("Failed to push NotificationEvent \(event.id, privacy: .public): \(String(describing: error), privacy: .public)")
            event.syncStatus = .failed
        }
    }

    func push(_ event: UIInteractionEvent) async {
        let record = existingOrNewRecord(type: "UIInteractionEvent", id: event.id, systemFields: event.ckSystemFields)
        record["userID"] = event.userID
        record["timestamp"] = event.timestamp
        record["eventName"] = event.eventName
        record["screen"] = event.screen
        record["metadataJSON"] = event.metadataJSON

        do {
            let saved = try await saveResolvingConflict(record)
            event.ckSystemFields = archivedSystemFields(saved)
            event.syncStatus = .synced
        } catch {
            logger.error("Failed to push UIInteractionEvent \(event.id, privacy: .public): \(String(describing: error), privacy: .public)")
            event.syncStatus = .failed
        }
    }

    /// Upserts by a deterministic record name (one row per user per day), saved with
    /// `.allKeys` — last writer wins, and the Creator role allows the overwrite.
    func push(_ goals: [DailyGoal]) async {
        guard !goals.isEmpty else { return }
        let records = goals.map { goal -> CKRecord in
            let record = CKRecord(recordType: "DailyGoal", recordID: CKRecord.ID(recordName: dailyGoalRecordName(goal)))
            record["userID"] = goal.userID
            record["dayKey"] = goal.dayKey
            record["baseGoalML"] = goal.baseGoalML
            record["adjustmentML"] = goal.adjustmentML
            // Saved with `.allKeys` below, so an omitted field would be nulled on the
            // server — and a restore would bring every row back unlocked, letting a
            // later forecast rewrite a goal the user may already have met (the exact
            // thing `DailyGoal.adjustmentLocked` exists to prevent).
            record["adjustmentLocked"] = goal.adjustmentLocked ? 1 : 0
            record["atualizadoEm"] = goal.atualizadoEm
            return record
        }
        var saved: Set<String> = []
        do {
            for start in stride(from: 0, to: records.count, by: 300) {
                let chunk = Array(records[start..<min(start + 300, records.count)])
                let (results, _) = try await container.publicCloudDatabase.modifyRecords(
                    saving: chunk, deleting: [], savePolicy: .allKeys, atomically: false
                )
                for (id, result) in results {
                    if case .success = result { saved.insert(id.recordName) }
                }
            }
        } catch {
            logger.error("Failed to push DailyGoals: \(String(describing: error), privacy: .public)")
        }
        for goal in goals {
            goal.syncStatus = saved.contains(dailyGoalRecordName(goal)) ? .synced : .failed
        }
    }

    private func dailyGoalRecordName(_ goal: DailyGoal) -> String {
        "DailyGoal-\(goal.userID)-\(goal.dayKey)"
    }

    // MARK: - Pseudonymization (public-database fields)

    /// 5-year band, e.g. 32 -> "30-34"; everything from 80 up collapses into "80+", so
    /// the oldest participants aren't singled out by a narrow band. Non-private so
    /// `CloudKitPseudonymizationTests` can cover the boundaries.
    static func ageBand(_ idade: Int) -> String {
        guard idade > 0 else { return "desconhecida" }
        guard idade < 80 else { return "80+" }
        let lower = (idade / 5) * 5
        return "\(lower)-\(lower + 4)"
    }

    /// kg/m², one decimal — what the model uses in place of raw weight and height.
    /// nil when height is missing/zero, so a bad profile pushes no value instead of
    /// an infinity.
    static func bmi(pesoKg: Double, alturaCm: Double) -> Double? {
        let meters = alturaCm / 100
        guard meters > 0, pesoKg > 0 else { return nil }
        return ((pesoKg / (meters * meters)) * 10).rounded() / 10
    }

    /// Midpoint of an `ageBand` string, for the restore path. nil when unparseable.
    static func ageFromBand(_ band: String) -> Int? {
        if band == "80+" { return 82 }
        let parts = band.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0] + parts[1]) / 2
    }

    /// Pushed again whenever the scheduler or the policy updates the row (closing the
    /// slot, resolving its outcome), so it carries its system fields like the others.
    func push(_ decision: SlotDecision) async {
        let record = existingOrNewRecord(type: "SlotDecision", id: decision.id, systemFields: decision.ckSystemFields)
        record["id"] = decision.id.uuidString
        record["userID"] = decision.userID
        record["slotFiresAt"] = decision.slotFiresAt
        record["decidedAt"] = decision.decidedAt
        record["slotHour"] = decision.slotHour
        record["actionRaw"] = decision.actionRaw
        record["propensity"] = decision.propensity
        record["policyVersion"] = decision.policyVersion
        record["featuresJSON"] = decision.featuresJSON
        record["notificationVariant"] = decision.notificationVariant
        record["notificationEventID"] = decision.notificationEventID
        record["suppressed"] = decision.suppressed.map { $0 ? 1 : 0 }
        record["intakeInWindow"] = decision.intakeInWindow.map { $0 ? 1 : 0 }
        record["resolvedAt"] = decision.resolvedAt

        do {
            let saved = try await container.publicCloudDatabase.save(record)
            decision.ckSystemFields = archivedSystemFields(saved)
            decision.syncStatus = .synced
        } catch {
            logger.error("Failed to push SlotDecision \(decision.id, privacy: .public): \(String(describing: error), privacy: .public)")
            decision.syncStatus = .failed
        }
    }

    // MARK: - Deletion

    /// Deletes one record from the public database — used when a tester removes an
    /// `IntakeLog` they logged by mistake. On failure the deletion is queued and
    /// retried by `flushPending`, since the local row is already gone by then and
    /// can't be rediscovered by scanning SwiftData the way a failed push can.
    func delete(recordType: String, id: UUID) async {
        do {
            _ = try await container.publicCloudDatabase.deleteRecord(withID: recordID(for: id))
        } catch let error as CKError where error.code == .unknownItem {
            // Never made it to CloudKit in the first place (e.g. deleted before its
            // first push finished) — nothing to retry.
        } catch {
            logger.error("Failed to delete \(recordType, privacy: .public) \(id, privacy: .public), queuing retry: \(String(describing: error), privacy: .public)")
            queuePendingDeletion(recordType: recordType, recordName: id.uuidString)
        }
    }

    private func queuePendingDeletion(recordType: String, recordName: String) {
        var pending = loadPendingDeletions()
        pending.append(PendingDeletion(recordType: recordType, recordName: recordName))
        savePendingDeletions(pending)
    }

    private func flushPendingDeletions() async {
        let pending = loadPendingDeletions()
        guard !pending.isEmpty else { return }

        var stillPending: [PendingDeletion] = []
        for deletion in pending {
            do {
                _ = try await container.publicCloudDatabase.deleteRecord(withID: CKRecord.ID(recordName: deletion.recordName))
            } catch let error as CKError where error.code == .unknownItem {
                continue // already gone (or never existed) — drop it
            } catch {
                stillPending.append(deletion)
            }
        }
        savePendingDeletions(stillPending)
    }

    private func loadPendingDeletions() -> [PendingDeletion] {
        guard let data = UserDefaults.standard.data(forKey: pendingDeletionsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingDeletion].self, from: data)) ?? []
    }

    private func savePendingDeletions(_ deletions: [PendingDeletion]) {
        guard let data = try? JSONEncoder().encode(deletions) else { return }
        UserDefaults.standard.set(data, forKey: pendingDeletionsKey)
    }

    /// Retries every local record still `.pending`/`.failed`, and any deletion that
    /// failed to reach CloudKit. Call on launch and whenever the scene becomes active
    /// — cheap no-op when everything is already synced.
    func flushPending(context: ModelContext) async {
        do {
            _ = try await currentUserID()
        } catch {
            logger.notice("flushPending skipped — currentUserID() failed: \(String(describing: error), privacy: .public)")
            return
        }

        await flushPendingDeletions()

        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            for profile in profiles where profile.syncStatus != .synced {
                await push(profile)
            }
        }
        if let logs = try? context.fetch(FetchDescriptor<IntakeLog>()) {
            for log in logs where log.syncStatus != .synced {
                await push(log)
            }
        }
        if let events = try? context.fetch(FetchDescriptor<NotificationEvent>()) {
            for event in events where event.syncStatus != .synced {
                await push(event)
            }
        }
        if let goals = try? context.fetch(FetchDescriptor<DailyGoal>()) {
            await push(goals.filter { $0.syncStatus != .synced })
        }
        if let interactionEvents = try? context.fetch(FetchDescriptor<UIInteractionEvent>()) {
            for event in interactionEvents where event.syncStatus != .synced {
                await push(event)
            }
        }
        if let decisions = try? context.fetch(FetchDescriptor<SlotDecision>()) {
            for decision in decisions where decision.syncStatus != .synced {
                await push(decision)
            }
        }
        try? context.save()
    }

    // MARK: - Restore (reinstall / another device)

    /// Last successful pull — absent on a fresh install, which makes the next
    /// `syncFromCloud` a full restore instead of an incremental one.
    private let lastPullKey = "cloudKitLastPull"
    private var pullTask: Task<Bool, Never>?

    /// Pulls this iCloud user's own records from the public database into SwiftData:
    /// on a fresh install (or a new device) the whole history — profile, every intake,
    /// the daily-goal snapshots — and afterwards just the recent intakes, so whatever
    /// another device with the same account logged shows up here too.
    ///
    /// Requires QUERYABLE indexes in the CloudKit Dashboard (both environments):
    /// `userID` on UserProfile, IntakeLog and DailyGoal, and `timestamp` on IntakeLog.
    ///
    /// Deletions aren't propagated between devices: a log deleted on device A stays on
    /// device B until B is reinstalled (the deleted record is gone from the server, so
    /// it won't be restored). Returns whether a `UserProfile` exists locally afterwards.
    @discardableResult
    func syncFromCloud(context: ModelContext) async -> Bool {
        if let pullTask { return await pullTask.value }
        let task = Task { @MainActor in
            await pull(context: context)
            return ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) > 0
        }
        pullTask = task
        defer { pullTask = nil }
        return await task.value
    }

    private func pull(context: ModelContext) async {
        guard (try? await container.accountStatus()) == .available,
              let userID = try? await currentUserID() else {
            logger.notice("syncFromCloud skipped — no iCloud account available")
            return
        }
        let startedAt = Date.now
        let lastPull = UserDefaults.standard.object(forKey: lastPullKey) as? Date
        var applied = 0
        do {
            let profiles = try await queryAll("UserProfile", NSPredicate(format: "userID == %@", userID))
            if let newest = profiles.max(by: { ($0["atualizadoEm"] as? Date ?? .distantPast) < ($1["atualizadoEm"] as? Date ?? .distantPast) }) {
                applied += applyProfile(newest, context: context) ? 1 : 0
            }

            let logPredicate: NSPredicate
            if let lastPull {
                // A day of overlap catches logs another device saved with a slightly
                // older timestamp (offline, slow push) since the last pull.
                logPredicate = NSPredicate(format: "userID == %@ AND timestamp >= %@", userID, lastPull.addingTimeInterval(-86_400) as NSDate)
            } else {
                logPredicate = NSPredicate(format: "userID == %@", userID)
            }
            for record in try await queryAll("IntakeLog", logPredicate) {
                applied += applyIntakeLog(record, context: context) ? 1 : 0
            }

            for record in try await queryAll("DailyGoal", NSPredicate(format: "userID == %@", userID)) {
                applied += applyDailyGoal(record, context: context) ? 1 : 0
            }
            try? context.save()
            UserDefaults.standard.set(startedAt, forKey: lastPullKey)
        } catch {
            try? context.save()
            logger.error("syncFromCloud failed: \(String(describing: error), privacy: .public)")
        }
        if applied > 0 {
            logger.notice("syncFromCloud applied \(applied) record(s)")
            WidgetSync.reloadWaterTank()
        }
    }

    private func queryAll(_ recordType: String, _ predicate: NSPredicate) async throws -> [CKRecord] {
        let database = container.publicCloudDatabase
        var records: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: CKQuery(recordType: recordType, predicate: predicate))
        while true {
            for (_, result) in results {
                if case .success(let record) = result { records.append(record) }
            }
            guard let next = cursor else { break }
            (results, cursor) = try await database.records(continuingMatchFrom: next)
        }
        return records
    }

    /// Upserts the profile, last writer (by `atualizadoEm`) wins.
    private func applyProfile(_ record: CKRecord, context: ModelContext) -> Bool {
        guard let userID = record["userID"] as? String,
              let remoteUpdated = record["atualizadoEm"] as? Date else { return false }
        let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first
        if let existing, existing.atualizadoEm >= remoteUpdated { return false }

        let profile = existing ?? UserProfile(
            userID: userID, idade: 0, genero: nil, pesoKg: 0, alturaCm: 0,
            fusoHorario: TimeZone.current.identifier, metaDiariaML: 0
        )
        if existing == nil {
            if let id = UUID(uuidString: record.recordID.recordName) { profile.id = id }
            profile.criadoEm = record["criadoEm"] as? Date ?? .now
            context.insert(profile)
        }
        if profile.id.uuidString == record.recordID.recordName {
            profile.ckSystemFields = archivedSystemFields(record)
            profile.syncStatus = .synced
        }
        profile.userID = userID
        // `idade` is only present on rows pushed by a build before pseudonymization
        // (see `push(_ profile:)`); newer rows carry a 5-year band, whose midpoint is
        // the best available approximation. Exact weight/height are no longer pushed at
        // all, so they keep whatever this device already had (0 on a fresh install —
        // the goal itself is restored below, so the app stays usable).
        if let exactAge = record["idade"] as? Int {
            profile.idade = exactAge
        } else if let band = record["faixaIdade"] as? String, let approximate = Self.ageFromBand(band) {
            profile.idade = approximate
        }
        profile.genero = record["genero"] as? String
        profile.pesoKg = record["pesoKg"] as? Double ?? profile.pesoKg
        profile.alturaCm = record["alturaCm"] as? Double ?? profile.alturaCm
        profile.fusoHorario = record["fusoHorario"] as? String ?? profile.fusoHorario
        profile.metaDiariaML = record["metaDiariaML"] as? Int ?? profile.metaDiariaML
        profile.customIntakeML = record["customIntakeML"] as? Int ?? profile.customIntakeML
        profile.atualizadoEm = remoteUpdated
        return true
    }

    /// Inserts an intake this device doesn't have yet (logs are immutable once created).
    private func applyIntakeLog(_ record: CKRecord, context: ModelContext) -> Bool {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let userID = record["userID"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let volumeML = record["volumeML"] as? Int else { return false }
        if ((try? context.fetchCount(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0 { return false }
        let healthKitUUID = record["healthKitUUID"] as? String
        if let healthKitUUID,
           ((try? context.fetchCount(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.healthKitUUID == healthKitUUID }))) ?? 0) > 0 {
            return false // already imported from Health on this device
        }

        let log = IntakeLog(
            userID: userID,
            timestamp: timestamp,
            volumeML: volumeML,
            tipoEntrada: record["tipoEntrada"] as? String ?? "",
            origem: OrigemRegistro(rawValue: record["origem"] as? String ?? "") ?? .manual,
            source: record["source"] as? String ?? "app",
            healthKitUUID: healthKitUUID ?? ""
        )
        log.id = id
        log.healthKitUUID = healthKitUUID
        log.notificationEventID = record["notificationEventID"] as? String
        log.temperaturaC = record["temperaturaC"] as? Double
        log.umidadeRelativa = record["umidadeRelativa"] as? Double
        log.sensacaoTermicaC = record["sensacaoTermicaC"] as? Double
        log.syncStatus = .synced
        context.insert(log)
        return true
    }

    /// Upserts one day's goal snapshot, last writer (by `atualizadoEm`) wins.
    private func applyDailyGoal(_ record: CKRecord, context: ModelContext) -> Bool {
        guard let userID = record["userID"] as? String,
              let dayKey = record["dayKey"] as? String,
              let baseGoalML = record["baseGoalML"] as? Int,
              let remoteUpdated = record["atualizadoEm"] as? Date else { return false }
        let adjustmentML = record["adjustmentML"] as? Int ?? 0
        // Rows pushed by a build before `adjustmentLocked` was synced have no field at
        // all; those come back unlocked, which just re-locks on their next write.
        let remoteLocked = (record["adjustmentLocked"] as? Int).map { $0 != 0 } ?? false
        let existing = try? context.fetch(FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userID == userID && $0.dayKey == dayKey })).first
        if let existing {
            guard existing.atualizadoEm < remoteUpdated else { return false }
            existing.baseGoalML = baseGoalML
            existing.adjustmentML = adjustmentML
            // Never un-lock: a settled adjustment stays settled whichever side saw it first.
            existing.adjustmentLocked = existing.adjustmentLocked || remoteLocked
            existing.atualizadoEm = remoteUpdated
            existing.syncStatus = .synced
        } else {
            let goal = DailyGoal(userID: userID, dayKey: dayKey, baseGoalML: baseGoalML, adjustmentML: adjustmentML, adjustmentLocked: remoteLocked)
            goal.atualizadoEm = remoteUpdated
            goal.syncStatus = .synced
            context.insert(goal)
        }
        return true
    }

    // MARK: - Helpers

    /// Saves `record`; if the server already holds a newer copy, re-applies this push's
    /// fields onto that copy and saves once more. Without this, a row whose earlier save
    /// landed but whose response was lost (or that raced another push of the same row,
    /// e.g. `captureContext` and `resolveInteraction` for one `NotificationEvent`) would
    /// stay `.failed` for good: every `flushPending` retry rebuilds the record from the
    /// same stale `ckSystemFields` and hits `.serverRecordChanged` again.
    private func saveResolvingConflict(_ record: CKRecord) async throws -> CKRecord {
        do {
            return try await container.publicCloudDatabase.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let serverRecord = error.serverRecord else { throw error }
            for key in record.changedKeys() {
                serverRecord[key] = record[key]
            }
            return try await container.publicCloudDatabase.save(serverRecord)
        }
    }

    private func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    /// Decodes a previously-saved record's system fields (preserving its change tag)
    /// so an update doesn't collide with the server copy, or creates a fresh record
    /// the first time this local row is pushed.
    private func existingOrNewRecord(type: String, id: UUID, systemFields: Data?) -> CKRecord {
        if let systemFields,
           let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            unarchiver.requiresSecureCoding = true
            if let record = CKRecord(coder: unarchiver) {
                return record
            }
        }
        return CKRecord(recordType: type, recordID: recordID(for: id))
    }

    private func archivedSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }
}
