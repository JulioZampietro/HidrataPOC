import Foundation

/// Apaga todo o estado local que não vive no SwiftData — o `UserDefaults` padrão e o
/// do App Group. Usado pelo "apagar meus dados" (`MyDataView`): sem isso, apagar o
/// banco deixaria para trás o agendamento de lembretes, o posterior da política
/// aprendido com o comportamento do usuário e os recordes dos minijogos, todos
/// derivados dos dados que o usuário acabou de pedir para remover.
///
/// Mantido como uma lista explícita, não um `removePersistentDomain`: o domínio
/// inteiro inclui estado que a Apple grava no mesmo lugar, e varrer tudo já causou
/// efeitos colaterais inesperados em outros apps. **Ao adicionar uma chave nova de
/// `UserDefaults` no app, acrescente-a aqui.**
enum AppStateReset {
    /// Chaves no `UserDefaults.standard`.
    private static let standardKeys = [
        // Onboarding e consentimento (RootView)
        "hasAcceptedConsent",
        "hasSeenFeatureOnboarding",
        // Agendamento de notificações (NotificationScheduler)
        "pendingNotificationSlots",
        "notificationSlotsScheduledForDay",
        "notificationSchedulingSchemaVersion",
        "pendingNotificationDismissals",
        "pendingNotificationsRenderedMascot",
        "lastNotificationMascotImageName",
        "lastNotificationMascotDay",
        // Sync (CloudKitSyncService, HealthKitService)
        "pendingCloudKitDeletions",
        "cloudKitLastPull",
        "localFallbackUserID",
        "healthkit.lastSyncDate",
        // Minijogos (MiniGame)
        "minigame.selected",
        "minigame.announced",
        "minigame.jump.best",
        "minigame.bubbles.best",
        "minigame.flappy.best",
        // Sons e vibração (FeedbackSettings)
        "settings.hapticsEnabled",
        "settings.soundEffectsEnabled",
    ]

    /// Chaves no App Group (compartilhadas com a extensão do widget).
    private static let appGroupKeys = [
        // Política de horários — aprendida a partir do comportamento do usuário.
        "policy.params.json",
        "policy.posterior.json",
        "policy.params.lastRefresh",
        // Widget
        "widget.effectiveGoalML",
        "widget.effectiveGoalDay",
        "systemInterfaceStyleIsDark",
    ]

    static func eraseLocalState() {
        let standard = UserDefaults.standard
        for key in standardKeys { standard.removeObject(forKey: key) }

        if let group = UserDefaults(suiteName: Constants.appGroupID) {
            for key in appGroupKeys { group.removeObject(forKey: key) }
        }
    }
}
