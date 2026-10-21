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

    /// Autorização de **escrita**. É o que `authorizationStatus(for:)` reporta — a
    /// Apple não expõe o estado da permissão de leitura de propósito (saber que o
    /// usuário negou a leitura já é, por si, uma informação sobre ele).
    var isAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: waterType) == .sharingAuthorized
    }

    /// Gate das **leituras**. Usar `isAuthorized` aqui era errado: quem libera ler mas
    /// nega escrever nunca importava nada do Saúde, porque o status de escrita barrava
    /// a consulta. Como não há como consultar a permissão de leitura, o caminho certo é
    /// tentar a query e tratar o resultado — o que `syncFromHealthKit` já faz (resultado
    /// vazio e erro são indistinguíveis de fora, por design da Apple).
    var canAttemptRead: Bool { isAvailable }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [waterType], read: [waterType]) { _, error in
                if let error { logger.error("HealthKit auth error: \(error.localizedDescription, privacy: .public)") }
                let authorized = self.store.authorizationStatus(for: self.waterType) == .sharingAuthorized
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
            return
        }
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: milliliter, doubleValue: Double(volumeML)),
            start: timestamp,
            end: timestamp,
            metadata: [HKMetadataKeyExternalUUID: logID.uuidString]
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.save(sample) { success, error in
                if let error {
                    logger.error("HealthKit save failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.debug("HealthKit save callback success=\(success)")
                }
                continuation.resume()
            }
        }
    }

    /// Apaga do HealthKit **todas** as amostras de água escritas por este app — a
    /// parte "apagar meus dados" do consentimento (ver `MyDataView`). O predicado por
    /// `HKSource.default()` garante que nada registrado por outros apps (Saúde,
    /// MyFitnessPal…) seja tocado: aquilo nunca foi nosso para apagar.
    /// Retorna false se o HealthKit recusar, para o chamador não alegar sucesso.
    @discardableResult
    func deleteAllOurSamples() async -> Bool {
        guard isAuthorized else { return true } // nada foi escrito lá
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.deleteObjects(of: waterType, predicate: predicate) { success, _, error in
                if let error {
                    // `noDataAvailable`: não havia nada para apagar — sucesso na prática.
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: true)
                        return
                    }
                    logger.error("HealthKit bulk delete failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: success)
            }
        }
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
    /// Uma consulta por lote, não por registro: antes isso rodava uma `HKSampleQuery`
    /// para cada log, em série, sobre o histórico inteiro — e é chamado a cada vez que o
    /// app volta ao primeiro plano (`HidrataPOCApp.syncHealthKitIfAuthorized`), ou seja,
    /// milhares de IPCs para o `healthd` num trabalho que, depois da primeira passada,
    /// não tem nada a fazer.
    func backfill(logs: [IntakeLog]) async {
        guard isAuthorized else { return }
        let candidates = logs.filter { $0.source != "healthkit" }
        guard !candidates.isEmpty else { return }

        let alreadyThere = await existingExternalUUIDs(among: candidates.map(\.id))
        for log in candidates where !alreadyThere.contains(log.id.uuidString) {
            await save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
        }
    }

    /// Quais desses logs já têm amostra no HealthKit, consultando em lotes — um
    /// predicado com `allowedValues` de milhares de itens de uma vez é grande demais
    /// para valer a pena.
    private func existingExternalUUIDs(among ids: [UUID]) async -> Set<String> {
        var found: Set<String> = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = ids[start..<min(start + 500, ids.count)].map(\.uuidString)
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: chunk
            )
            let batch: Set<String> = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: waterType, predicate: predicate,
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                    if let error {
                        logger.error("HealthKit backfill lookup failed: \(error.localizedDescription, privacy: .public)")
                        // Com a consulta falhando, tratar tudo como "já existe" evita
                        // reescrever (e duplicar) amostras às cegas no Saúde.
                        continuation.resume(returning: Set(chunk))
                        return
                    }
                    let uuids = (results ?? []).compactMap {
                        $0.metadata?[HKMetadataKeyExternalUUID] as? String
                    }
                    continuation.resume(returning: Set(uuids))
                }
                store.execute(query)
            }
            found.formUnion(batch)
        }
        return found
    }

    func syncFromHealthKit(userID: String, context: ModelContext) async {
        guard canAttemptRead else { return }

        // Na primeira sincronização (sem lastSyncDate gravado) busca todo o histórico.
        // Nas sincronizações incrementais, olha 1 hora antes do lastSyncDate para capturar
        // registros adicionados retroativamente ou com atraso de propagação iCloud.
        let lastSync: Date
        if let saved = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSync = saved.addingTimeInterval(-60 * 60)
        } else {
            lastSync = Date.distantPast
        }
        logger.debug("syncFromHealthKit a partir de \(lastSync, privacy: .public)")

        // Fixed end bound, reused as the new `lastSyncKey`: using a later `.now` would
        // skip samples that landed while the query ran.
        let queryEnd = Date.now
        let predicate = HKQuery.predicateForSamples(withStart: lastSync, end: queryEnd)
        // nil = the query itself failed. Advancing `lastSyncKey` on a failure would skip
        // that window permanently, so a failed read has to leave the bookmark alone.
        let samples: [HKQuantitySample]? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    logger.error("HealthKit read failed, keeping lastSync: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
        guard let samples else { return }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        let external = samples.filter { $0.sourceRevision.source.bundleIdentifier != ourBundle }
        logger.debug("query devolveu \(samples.count, privacy: .public) amostras, \(external.count, privacy: .public) externas")

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

        logger.debug("importou \(inserted, privacy: .public) registros novos")
        if inserted > 0 { try? context.save() }
        UserDefaults.standard.set(queryEnd, forKey: lastSyncKey)
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }
}
