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
/// Separately, the records the user would want back after a reinstall or on another
/// device (`UserProfile`, `IntakeLog`, `DailyGoal`) are also mirrored to the user's
/// **private** database, in a custom zone — see "Private backup & restore" below.
/// That copy is readable only by the user's own iCloud account and is what
/// `syncPrivateDatabase` pulls back into SwiftData.
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
        /// nil on deletions queued before the private backup existed — those are public.
        var isPrivate: Bool? = nil
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

    func push(_ profile: UserProfile) async {
        profile.privateSyncStatus = .pending
        await pushPrivate(profile)

        let record = existingOrNewRecord(type: "UserProfile", id: profile.id, systemFields: profile.ckSystemFields)
        record["userID"] = profile.userID
        record["idade"] = profile.idade
        record["genero"] = profile.genero
        record["generoAutoDeclarado"] = profile.generoAutoDeclarado
        record["pesoKg"] = profile.pesoKg
        record["alturaCm"] = profile.alturaCm
        record["fusoHorario"] = profile.fusoHorario
        record["metaDiariaML"] = profile.metaDiariaML
        record["customIntakeML"] = profile.customIntakeML
        record["criadoEm"] = profile.criadoEm
        record["atualizadoEm"] = profile.atualizadoEm

        do {
            let saved = try await container.publicCloudDatabase.save(record)
            profile.ckSystemFields = archivedSystemFields(saved)
            profile.syncStatus = .synced
        } catch {
            logger.error("Failed to push UserProfile \(profile.id, privacy: .public): \(String(describing: error), privacy: .public)")
            profile.syncStatus = .failed
        }
    }

    func push(_ log: IntakeLog) async {
        if log.privateSyncStatus != .synced {
            await pushPrivate(log)
        }
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
            let saved = try await container.publicCloudDatabase.save(record)
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
            let saved = try await container.publicCloudDatabase.save(record)
            event.ckSystemFields = archivedSystemFields(saved)
            event.syncStatus = .synced
        } catch {
            logger.error("Failed to push UIInteractionEvent \(event.id, privacy: .public): \(String(describing: error), privacy: .public)")
            event.syncStatus = .failed
        }
    }

    // MARK: - Deletion

    /// Deletes one record from the public database — used when a tester removes an
    /// `IntakeLog` they logged by mistake. On failure the deletion is queued and
    /// retried by `flushPending`, since the local row is already gone by then and
    /// can't be rediscovered by scanning SwiftData the way a failed push can.
    func delete(recordType: String, id: UUID) async {
        await deletePrivate(recordName: id.uuidString)
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

    private func queuePendingDeletion(recordType: String, recordName: String, isPrivate: Bool = false) {
        var pending = loadPendingDeletions()
        pending.append(PendingDeletion(recordType: recordType, recordName: recordName, isPrivate: isPrivate))
        savePendingDeletions(pending)
    }

    private func flushPendingDeletions() async {
        let pending = loadPendingDeletions()
        guard !pending.isEmpty else { return }

        var stillPending: [PendingDeletion] = []
        for deletion in pending {
            do {
                if deletion.isPrivate == true {
                    try await ensurePrivateZone()
                    _ = try await container.privateCloudDatabase.deleteRecord(withID: privateRecordID(deletion.recordName))
                } else {
                    _ = try await container.publicCloudDatabase.deleteRecord(withID: CKRecord.ID(recordName: deletion.recordName))
                }
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
            // Também cobre o backfill único das linhas criadas antes do backup privado
            // existir (migraram com `privateSyncStatus == .pending`).
            await pushPrivate(logs.filter { $0.privateSyncStatus != .synced })
        }
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            for profile in profiles where profile.privateSyncStatus != .synced {
                await pushPrivate(profile)
            }
        }
        if let goals = try? context.fetch(FetchDescriptor<DailyGoal>()) {
            await pushPrivate(goals.filter { $0.privateSyncStatus != .synced })
        }
        if let events = try? context.fetch(FetchDescriptor<NotificationEvent>()) {
            for event in events where event.syncStatus != .synced {
                await push(event)
            }
        }
        if let interactionEvents = try? context.fetch(FetchDescriptor<UIInteractionEvent>()) {
            for event in interactionEvents where event.syncStatus != .synced {
                await push(event)
            }
        }
        try? context.save()
    }

    // MARK: - Private backup & restore

    /// Custom zone (not the default one) so `recordZoneChanges` can fetch everything
    /// — or just what changed since the last fetch — without any queryable indexes
    /// having to be deployed in the CloudKit Dashboard.
    private let privateZoneID = CKRecordZone.ID(zoneName: "UserData", ownerName: CKCurrentUserDefaultName)
    private let privateZoneReadyKey = "cloudKitPrivateZoneReady"
    private let privateChangeTokenKey = "cloudKitPrivateChangeToken"
    /// The profile is a singleton per iCloud account, so its record name is fixed —
    /// two devices that each created a profile still converge on one record.
    private let profileRecordName = "UserProfile"
    private var privateSyncTask: Task<Bool, Never>?

    private func privateRecordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: privateZoneID)
    }

    private func dailyGoalRecordName(_ goal: DailyGoal) -> String { "DailyGoal-\(goal.dayKey)" }

    private func ensurePrivateZone() async throws {
        guard !UserDefaults.standard.bool(forKey: privateZoneReadyKey) else { return }
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: privateZoneID)], deleting: [])
        UserDefaults.standard.set(true, forKey: privateZoneReadyKey)
    }

    private func privateRecord(for profile: UserProfile) -> CKRecord {
        let record = CKRecord(recordType: "UserProfile", recordID: privateRecordID(profileRecordName))
        record["localID"] = profile.id.uuidString
        record["userID"] = profile.userID
        record["idade"] = profile.idade
        record["genero"] = profile.genero
        record["generoAutoDeclarado"] = profile.generoAutoDeclarado
        record["pesoKg"] = profile.pesoKg
        record["alturaCm"] = profile.alturaCm
        record["fusoHorario"] = profile.fusoHorario
        record["metaDiariaML"] = profile.metaDiariaML
        record["customIntakeML"] = profile.customIntakeML
        record["criadoEm"] = profile.criadoEm
        record["atualizadoEm"] = profile.atualizadoEm
        return record
    }

    private func privateRecord(for log: IntakeLog) -> CKRecord {
        let record = CKRecord(recordType: "IntakeLog", recordID: privateRecordID(log.id.uuidString))
        record["userID"] = log.userID
        record["timestamp"] = log.timestamp
        record["volumeML"] = log.volumeML
        record["tipoEntrada"] = log.tipoEntrada
        record["origem"] = log.origem
        record["notificationEventID"] = log.notificationEventID
        record["source"] = log.source
        record["healthKitUUID"] = log.healthKitUUID
        record["temperaturaC"] = log.temperaturaC
        record["umidadeRelativa"] = log.umidadeRelativa
        record["sensacaoTermicaC"] = log.sensacaoTermicaC
        return record
    }

    private func privateRecord(for goal: DailyGoal) -> CKRecord {
        let record = CKRecord(recordType: "DailyGoal", recordID: privateRecordID(dailyGoalRecordName(goal)))
        record["localID"] = goal.id.uuidString
        record["userID"] = goal.userID
        record["dayKey"] = goal.dayKey
        record["baseGoalML"] = goal.baseGoalML
        record["adjustmentML"] = goal.adjustmentML
        record["atualizadoEm"] = goal.atualizadoEm
        return record
    }

    private func pushPrivate(_ profile: UserProfile) async {
        let ok = await savePrivate([privateRecord(for: profile)])
        profile.privateSyncStatus = ok.isEmpty ? .failed : .synced
    }

    private func pushPrivate(_ logs: [IntakeLog]) async {
        guard !logs.isEmpty else { return }
        let saved = await savePrivate(logs.map(privateRecord(for:)))
        for log in logs {
            log.privateSyncStatus = saved.contains(log.id.uuidString) ? .synced : .failed
        }
    }

    private func pushPrivate(_ log: IntakeLog) async {
        await pushPrivate([log])
    }

    private func pushPrivate(_ goals: [DailyGoal]) async {
        guard !goals.isEmpty else { return }
        let saved = await savePrivate(goals.map(privateRecord(for:)))
        for goal in goals {
            goal.privateSyncStatus = saved.contains(dailyGoalRecordName(goal)) ? .synced : .failed
        }
    }

    /// Saves in chunks (CloudKit caps a single modify at 400 records) with
    /// `.allKeys` — last writer wins, so no change-tag bookkeeping is needed for
    /// this per-user copy. Returns the record names that were saved.
    private func savePrivate(_ records: [CKRecord]) async -> Set<String> {
        var saved: Set<String> = []
        do {
            try await ensurePrivateZone()
            for start in stride(from: 0, to: records.count, by: 300) {
                let chunk = Array(records[start..<min(start + 300, records.count)])
                let (results, _) = try await container.privateCloudDatabase.modifyRecords(
                    saving: chunk, deleting: [], savePolicy: .allKeys, atomically: false
                )
                for (id, result) in results {
                    switch result {
                    case .success: saved.insert(id.recordName)
                    case .failure(let error):
                        if (error as? CKError)?.code == .zoneNotFound {
                            UserDefaults.standard.set(false, forKey: privateZoneReadyKey)
                        }
                        logger.error("Private save failed for \(id.recordName, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }
        } catch {
            if (error as? CKError)?.code == .zoneNotFound {
                UserDefaults.standard.set(false, forKey: privateZoneReadyKey)
            }
            logger.error("Private save failed: \(String(describing: error), privacy: .public)")
        }
        return saved
    }

    private func deletePrivate(recordName: String) async {
        do {
            try await ensurePrivateZone()
            _ = try await container.privateCloudDatabase.deleteRecord(withID: privateRecordID(recordName))
        } catch let error as CKError where error.code == .unknownItem {
            // Never backed up — nothing to do.
        } catch {
            logger.error("Failed to delete private \(recordName, privacy: .public), queuing retry: \(String(describing: error), privacy: .public)")
            queuePendingDeletion(recordType: "IntakeLog", recordName: recordName, isPrivate: true)
        }
    }

    /// Pulls every change in the user's private zone since the last fetch into
    /// SwiftData. On a fresh install there's no change token, so this is a full
    /// restore — profile, every intake and the daily-goal history. On later calls it's
    /// cheap and picks up what another device with the same iCloud account wrote.
    ///
    /// Returns whether a `UserProfile` exists locally afterwards. Concurrent callers
    /// share the same in-flight fetch.
    @discardableResult
    func syncPrivateDatabase(context: ModelContext) async -> Bool {
        if let privateSyncTask { return await privateSyncTask.value }
        let task = Task { @MainActor in
            await fetchPrivateChanges(context: context)
            return ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) > 0
        }
        privateSyncTask = task
        defer { privateSyncTask = nil }
        return await task.value
    }

    private func fetchPrivateChanges(context: ModelContext) async {
        guard (try? await container.accountStatus()) == .available else {
            logger.notice("Private sync skipped — no iCloud account available")
            return
        }
        var token = loadPrivateChangeToken()
        var applied = 0
        do {
            var moreComing = true
            while moreComing {
                let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                              deletions: [CKDatabase.RecordZoneChange.Deletion],
                              changeToken: CKServerChangeToken,
                              moreComing: Bool)
                do {
                    changes = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: privateZoneID, since: token)
                } catch let error as CKError where error.code == .changeTokenExpired {
                    token = nil
                    savePrivateChangeToken(nil)
                    continue
                }
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let modification) = result {
                        applied += apply(modification.record, context: context) ? 1 : 0
                    }
                }
                for deletion in changes.deletions where deletion.recordType == "IntakeLog" {
                    applied += applyIntakeLogDeletion(recordName: deletion.recordID.recordName, context: context) ? 1 : 0
                }
                try? context.save()
                token = changes.changeToken
                savePrivateChangeToken(token)
                moreComing = changes.moreComing
            }
            UserDefaults.standard.set(true, forKey: privateZoneReadyKey)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing was ever backed up for this account — a genuinely new user.
            UserDefaults.standard.set(false, forKey: privateZoneReadyKey)
        } catch {
            logger.error("Private fetch failed: \(String(describing: error), privacy: .public)")
        }
        if applied > 0 {
            logger.notice("Private sync applied \(applied) change(s) from iCloud")
            WidgetSync.reloadWaterTank()
        }
    }

    /// Upserts one fetched record. Returns whether anything local changed.
    private func apply(_ record: CKRecord, context: ModelContext) -> Bool {
        switch record.recordType {
        case "UserProfile": return applyProfile(record, context: context)
        case "IntakeLog": return applyIntakeLog(record, context: context)
        case "DailyGoal": return applyDailyGoal(record, context: context)
        default: return false
        }
    }

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
            if let localID = (record["localID"] as? String).flatMap(UUID.init(uuidString:)) { profile.id = localID }
            profile.criadoEm = record["criadoEm"] as? Date ?? .now
            // Already in the public dataset from the device that created it.
            profile.syncStatus = .synced
            context.insert(profile)
        }
        profile.userID = userID
        profile.idade = record["idade"] as? Int ?? profile.idade
        profile.genero = record["genero"] as? String
        profile.generoAutoDeclarado = record["generoAutoDeclarado"] as? String
        profile.pesoKg = record["pesoKg"] as? Double ?? profile.pesoKg
        profile.alturaCm = record["alturaCm"] as? Double ?? profile.alturaCm
        profile.fusoHorario = record["fusoHorario"] as? String ?? profile.fusoHorario
        profile.metaDiariaML = record["metaDiariaML"] as? Int ?? profile.metaDiariaML
        profile.customIntakeML = record["customIntakeML"] as? Int ?? profile.customIntakeML
        profile.atualizadoEm = remoteUpdated
        profile.privateSyncStatus = .synced
        return true
    }

    private func applyIntakeLog(_ record: CKRecord, context: ModelContext) -> Bool {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let userID = record["userID"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let volumeML = record["volumeML"] as? Int else { return false }
        // Intake logs are immutable once created — existing means nothing to do.
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
        log.privateSyncStatus = .synced
        context.insert(log)
        return true
    }

    private func applyIntakeLogDeletion(recordName: String, context: ModelContext) -> Bool {
        guard let id = UUID(uuidString: recordName),
              let log = try? context.fetch(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.id == id })).first
        else { return false }
        context.delete(log)
        return true
    }

    private func applyDailyGoal(_ record: CKRecord, context: ModelContext) -> Bool {
        guard let userID = record["userID"] as? String,
              let dayKey = record["dayKey"] as? String,
              let baseGoalML = record["baseGoalML"] as? Int,
              let remoteUpdated = record["atualizadoEm"] as? Date else { return false }
        let adjustmentML = record["adjustmentML"] as? Int ?? 0
        let existing = try? context.fetch(FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userID == userID && $0.dayKey == dayKey })).first
        if let existing {
            guard existing.atualizadoEm < remoteUpdated else { return false }
            existing.baseGoalML = baseGoalML
            existing.adjustmentML = adjustmentML
            existing.atualizadoEm = remoteUpdated
            existing.privateSyncStatus = .synced
        } else {
            let goal = DailyGoal(userID: userID, dayKey: dayKey, baseGoalML: baseGoalML, adjustmentML: adjustmentML)
            if let localID = (record["localID"] as? String).flatMap(UUID.init(uuidString:)) { goal.id = localID }
            goal.atualizadoEm = remoteUpdated
            goal.privateSyncStatus = .synced
            context.insert(goal)
        }
        return true
    }

    private func loadPrivateChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: privateChangeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func savePrivateChangeToken(_ token: CKServerChangeToken?) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            UserDefaults.standard.removeObject(forKey: privateChangeTokenKey)
            return
        }
        UserDefaults.standard.set(data, forKey: privateChangeTokenKey)
    }

    // MARK: - Helpers

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
