import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.hidratapoc", category: "PersistenceController")

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
            IntakeLog.self,
            NotificationEvent.self,
            UIInteractionEvent.self,
            DailyGoal.self,
            SlotDecision.self,
        ])
        // Sem o App Group, o app e a extensão do widget não compartilham store. Antes
        // isto era `fatalError`: um crash no boot, sem telemetria e sem recuperação.
        // Agora cai para um store em memória, que mantém o app utilizável na sessão
        // (o onboarding roda, os registros funcionam) e deixa o motivo no log.
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupID)
        if groupURL == nil {
            logger.critical("App Group '\(Constants.appGroupID, privacy: .public)' não configurado — confira os entitlements dos targets HidrataPOC e HydrationWidget. Usando store em memória.")
        }
        // `cloudKitDatabase: .none` disables SwiftData's own automatic CloudKit
        // mirroring — this app pushes to the CloudKit **public** database manually
        // via CloudKitSyncService instead (SwiftData's built-in integration only
        // mirrors to the private database, and would otherwise also force every
        // attribute optional/defaulted and forbid the `.unique` constraints below).
        if let groupURL {
            let configuration = ModelConfiguration(schema: schema, url: groupURL.appending(path: "HidrataPOC.sqlite"), cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // Store corrompido ou incompatível. Um crash aqui deixaria o app sem
                // nenhuma saída; em memória ele abre, e o log diz o que aconteceu.
                logger.critical("Falha ao abrir o ModelContainer do App Group: \(String(describing: error), privacy: .public). Usando store em memória.")
            }
        }

        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [fallback])
        } catch {
            // Um container em memória que não abre significa que o próprio schema está
            // inválido — um erro de programação, não de ambiente.
            fatalError("Schema inválido: nem um store em memória pôde ser criado: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}
