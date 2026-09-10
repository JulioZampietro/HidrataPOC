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

    func push(_ profile: UserProfile) async {
        let record = existingOrNewRecord(type: "UserProfile", id: profile.id, systemFields: profile.ckSystemFields)
        record["userID"] = profile.userID
        record["idade"] = profile.idade
        record["genero"] = profile.genero
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

    func push(_ checkin: DailyCheckin) async {
        guard checkin.syncStatus != .synced else { return }
        let record = CKRecord(recordType: "DailyCheckin", recordID: recordID(for: checkin.id))
        record["userID"] = checkin.userID
        record["dataReferencia"] = checkin.dataReferencia
        record["horasSono"] = checkin.horasSono
        record["horarioAcordou"] = checkin.horarioAcordou
        record["treinou"] = checkin.treinou
        record["intensidadeExercicio"] = checkin.intensidadeExercicio

        do {
            _ = try await container.publicCloudDatabase.save(record)
            checkin.syncStatus = .synced
        } catch {
            logger.error("Failed to push DailyCheckin \(checkin.id, privacy: .public): \(String(describing: error), privacy: .public)")
            checkin.syncStatus = .failed
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

        do {
            _ = try await container.publicCloudDatabase.save(record)
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

        do {
            let saved = try await container.publicCloudDatabase.save(record)
            event.ckSystemFields = archivedSystemFields(saved)
            event.syncStatus = .synced
        } catch {
            logger.error("Failed to push NotificationEvent \(event.id, privacy: .public): \(String(describing: error), privacy: .public)")
            event.syncStatus = .failed
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
        if let checkins = try? context.fetch(FetchDescriptor<DailyCheckin>()) {
            for checkin in checkins where checkin.syncStatus != .synced {
                await push(checkin)
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
        try? context.save()
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
