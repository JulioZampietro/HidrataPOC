import Foundation
import HealthKit
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.hidratapoc", category: "HealthKitService")

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private init() {}

    private let store = HKHealthStore()
    private let waterType = HKQuantityType(.dietaryWater)
    private let milliliter = HKUnit.literUnit(with: .milli)
    private let lastSyncKey = "healthkit.lastSyncDate"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: waterType) == .sharingAuthorized
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [waterType], read: [waterType]) { _, error in
                if let error { logger.error("HealthKit auth error: \(error.localizedDescription, privacy: .public)") }
                let authorized = self.store.authorizationStatus(for: self.waterType) == .sharingAuthorized
                print("[HealthKit] requestAuthorization done – sharingAuthorized=\(authorized)")
                continuation.resume(returning: authorized)
            }
        }
    }

    // MARK: - Profile pre-fill

    struct ProfileData {
        var idade: Int?
        var genero: Genero?
        var pesoKg: Double?
        var alturaCm: Double?
    }

    /// Solicita permissão de leitura e retorna dados do perfil biológico do Health.
    func fetchProfileData() async -> ProfileData {
        guard isAvailable else { return ProfileData() }

        // Inclui água no mesmo dialog para cobrir tudo de uma vez.
        let readTypes: Set<HKObjectType> = [
            HKCharacteristicType(.biologicalSex),
            HKCharacteristicType(.dateOfBirth),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            waterType,
        ]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestAuthorization(toShare: [waterType], read: readTypes) { _, _ in
                continuation.resume()
            }
        }

        var result = ProfileData()

        if let sexObj = try? store.biologicalSex() {
            result.genero = generoFromBiologicalSex(sexObj.biologicalSex)
        }

        if let dob = try? store.dateOfBirthComponents(),
           let birthYear = dob.year, let birthMonth = dob.month, let birthDay = dob.day {
            let cal = Calendar.current
            let nowComps = cal.dateComponents([.year, .month, .day], from: .now)
            if let nowYear = nowComps.year, let nowMonth = nowComps.month, let nowDay = nowComps.day {
                var age = nowYear - birthYear
                if nowMonth < birthMonth || (nowMonth == birthMonth && nowDay < birthDay) { age -= 1 }
                result.idade = max(10, min(100, age))
            }
        }

        result.pesoKg = await latestQuantityValue(for: HKQuantityType(.bodyMass),
                                                  unit: .gramUnit(with: .kilo))

        if let heightM = await latestQuantityValue(for: HKQuantityType(.height), unit: .meter()) {
            result.alturaCm = heightM * 100
        }

        return result
    }

    private func generoFromBiologicalSex(_ sex: HKBiologicalSex) -> Genero? {
        switch sex {
        case .female: return .feminino
        case .male:   return .masculino
        case .other:  return .naoBinario
        default:      return nil
        }
    }

    private func latestQuantityValue(for type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: [sort]) { _, results, _ in
                let value = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Write

    /// Salva um registro de ingestão no HealthKit, marcando-o com o UUID do IntakeLog
    /// para permitir deleção precisa e deduplicação na importação futura.
    func save(volumeML: Int, timestamp: Date, logID: UUID) async {
        guard isAuthorized else {
            logger.warning("HealthKit: save skipped – not authorized (status=\(self.store.authorizationStatus(for: self.waterType).rawValue, privacy: .public))")
            print("[HealthKit] save skipped – isAuthorized=false for logID=\(logID)")
            return
        }
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: milliliter, doubleValue: Double(volumeML)),
            start: timestamp,
            end: timestamp,
            metadata: [HKMetadataKeyExternalUUID: logID.uuidString]
        )
        print("[HealthKit] saving \(volumeML)mL logID=\(logID)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.save(sample) { success, error in
                if let error {
                    logger.error("HealthKit save failed: \(error.localizedDescription, privacy: .public)")
                    print("[HealthKit] save FAILED: \(error.localizedDescription)")
                } else {
                    print("[HealthKit] save callback success=\(success)")
                }
                continuation.resume()
            }
        }
        // Verifica imediatamente se o sample foi persistido no store
        let verified = await existsInHealthKit(logID: logID)
        print("[HealthKit] post-save verification: exists=\(verified) logID=\(logID)")
    }

    /// Remove do HealthKit a amostra associada ao logID informado.
    func delete(logID: UUID) async {
        guard isAuthorized else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [logID.uuidString]
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.deleteObjects(of: waterType, predicate: predicate) { _, _, error in
                if let error { logger.error("HealthKit delete failed: \(error.localizedDescription, privacy: .public)") }
                continuation.resume()
            }
        }
    }

    // MARK: - Read (importar do Health)

    /// Busca amostras de água adicionadas por outros apps (Health, MyFitnessPal, etc.)
    /// desde a última sincronização e insere como IntakeLog no SwiftData.
    /// Escreve no HealthKit os logs do app que ainda não têm amostra correspondente lá.
    /// Seguro para chamar múltiplas vezes: verifica existência antes de salvar.
    func backfill(logs: [IntakeLog]) async {
        guard isAuthorized else { return }
        for log in logs where log.source != "healthkit" {
            guard await !existsInHealthKit(logID: log.id) else { continue }
            await save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
        }
    }

    private func existsInHealthKit(logID: UUID) async -> Bool {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [logID.uuidString]
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: waterType, predicate: predicate,
                                      limit: 1, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: !(results ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    func syncFromHealthKit(userID: String, context: ModelContext) async {
        guard isAuthorized else {
            print("[HealthKit] syncFromHealthKit skipped – not authorized")
            return
        }

        // Na primeira sincronização (sem lastSyncDate gravado) busca todo o histórico.
        // Nas sincronizações incrementais, olha 1 hora antes do lastSyncDate para capturar
        // registros adicionados retroativamente ou com atraso de propagação iCloud.
        let lastSync: Date
        if let saved = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSync = saved.addingTimeInterval(-60 * 60)
        } else {
            lastSync = Date.distantPast
        }
        print("[HealthKit] syncFromHealthKit start=\(lastSync) now=\(Date.now)")

        let predicate = HKQuery.predicateForSamples(withStart: lastSync, end: .now)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        let external = samples.filter { $0.sourceRevision.source.bundleIdentifier != ourBundle }
        print("[HealthKit] query returned \(samples.count) samples, \(external.count) external")

        var inserted = 0
        for sample in external {
            let hkUUID = sample.uuid.uuidString

            let alreadyImported = (try? context.fetch(
                FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.healthKitUUID == hkUUID })
            ))?.isEmpty == false
            guard !alreadyImported else { continue }

            let volumeML = Int(sample.quantity.doubleValue(for: milliliter).rounded())
            guard volumeML > 0 else { continue }

            let log = IntakeLog(
                userID: userID,
                timestamp: sample.startDate,
                volumeML: volumeML,
                tipoEntrada: "healthkit",
                origem: .manual,
                source: "healthkit",
                healthKitUUID: hkUUID
            )
            context.insert(log)
            inserted += 1
        }

        print("[HealthKit] inserted \(inserted) new records")
        if inserted > 0 { try? context.save() }
        UserDefaults.standard.set(Date.now, forKey: lastSyncKey)
    }

    /// Reseta a data de última sincronização para que a próxima chamada de
    /// `syncFromHealthKit` releia o histórico a partir do início do dia atual.
    func resetSyncDate() {
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }
}
