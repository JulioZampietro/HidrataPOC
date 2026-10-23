import Foundation

/// Preferências de som e vibração, escolhidas na sheet "Sons e vibração" do Perfil.
/// Ficam no `UserDefaults` (a sheet usa `@AppStorage` com as mesmas chaves) e valem
/// como ligadas enquanto o usuário nunca mexeu nelas.
enum FeedbackSettings {
    /// Chave do `@AppStorage` que liga/desliga todos os `Haptic`.
    static let hapticsEnabledKey = "settings.hapticsEnabled"
    /// Chave do `@AppStorage` que liga/desliga os efeitos sonoros (som da água na Home e
    /// sons dos minijogos). O som das notificações é do sistema e não passa por aqui.
    static let soundEffectsEnabledKey = "settings.soundEffectsEnabled"

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsEnabledKey) as? Bool ?? true
    }

    static var soundEffectsEnabled: Bool {
        UserDefaults.standard.object(forKey: soundEffectsEnabledKey) as? Bool ?? true
    }
}
