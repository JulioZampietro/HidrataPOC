import Foundation

enum Constants {
    /// Governs both how long we wait before inferring `statusInteracao = "ignorada"`
    /// and the response window used to associate a manual `IntakeLog` with a
    /// `NotificationEvent` as `resultouEmConsumo`. Same constant, two call sites —
    /// see NotificationScheduler and IntakeLogService.
    static let notificationResponseWindowMinutes = 10

    static let cloudKitContainerID = "iCloud.com.hidratapoc"

    /// Shared container so the HydrationWidget extension (Live Activity + Lock Screen
    /// quick-log buttons) reads/writes the same local SwiftData store as the app —
    /// there's no CloudKit pull-sync, so this is the only way a lock-screen tap shows
    /// up on the Home screen without relaunching the app.
    static let appGroupID = "group.com.hidratapoc"

    /// Fixed per Constitution C-... of the Live Activity spec: not user-configurable in v1.
    static let hydrationReminderThresholdSeconds: TimeInterval = 3600

    /// How long a cached `WeatherContext` reading stays valid for reuse — e.g. when
    /// tagging an `IntakeLog` at the instant a tester taps a quick-log button, where
    /// waiting on a fresh WeatherKit/location fetch would add noticeable latency.
    /// Weather doesn't change fast enough for this to meaningfully hurt data quality.
    static let weatherCacheMaxAgeMinutes = 20

    /// How many hydration reminders are scheduled per day, spread across
    /// `dailyWindowStartHour`..<`dailyWindowEndHour` with semi-random timing.
    static let notificationsPerDay = 5
    static let dailyWindowStartHour = 8
    static let dailyWindowEndHour = 22

    enum NotificationCategory {
        static let hydrationReminder = "HYDRATION_REMINDER"
    }

    enum NotificationAction {
        static let glass = "INTAKE_GLASS"
        static let bottle = "INTAKE_BOTTLE"
        static let gallon = "INTAKE_GALLON"
        static let snooze = "SNOOZE"
    }

    enum IntakePreset {
        case glass, bottle, gallon
        case custom(volumeML: Int)

        var volumeML: Int {
            switch self {
            case .glass: return 250
            case .bottle: return 500
            case .gallon: return 1000
            case .custom(let volumeML): return volumeML
            }
        }

        var tipoEntrada: String {
            switch self {
            case .glass: return "copo"
            case .bottle: return "garrafa"
            case .gallon: return "galao"
            case .custom: return "personalizado"
            }
        }

        var label: String {
            switch self {
            case .glass: return "Copo"
            case .bottle: return "Garrafa"
            case .gallon: return "Galão"
            case .custom: return "Personalizado"
            }
        }

        /// Maps a raw volume back to the preset it represents — used by the Live
        /// Activity's `LogIntakeIntent`, which only carries an `Int` across the
        /// process boundary (see HYDRATE-LA-01 Decision D-2).
        static func matching(volumeML: Int) -> IntakePreset {
            switch volumeML {
            case Constants.IntakePreset.glass.volumeML: return .glass
            case Constants.IntakePreset.bottle.volumeML: return .bottle
            default: return .custom(volumeML: volumeML)
            }
        }
    }
}
