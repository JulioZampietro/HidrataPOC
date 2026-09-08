import Foundation

enum Constants {
    /// Governs both how long we wait before inferring `statusInteracao = "ignorada"`
    /// and the response window used to associate a manual `IntakeLog` with a
    /// `NotificationEvent` as `resultouEmConsumo`. Same constant, two call sites —
    /// see NotificationScheduler and IntakeLogService.
    static let notificationResponseWindowMinutes = 10

    static let cloudKitContainerID = "iCloud.com.hidratapoc"

    /// How long a cached `WeatherContext` reading stays valid for reuse — e.g. when
    /// tagging an `IntakeLog` at the instant a tester taps a quick-log button, where
    /// waiting on a fresh WeatherKit/location fetch would add noticeable latency.
    /// Weather doesn't change fast enough for this to meaningfully hurt data quality.
    static let weatherCacheMaxAgeMinutes = 20

    /// Extra hydration (mL) added per degree Celsius that today's forecast high
    /// exceeds `baselineMaxTempC`.
    static let tempAdjustmentMLPerDegree = 50

    /// Reference "comfortable" maximum temperature (°C). Days hotter than this
    /// trigger the +50 mL/°C adjustment. Adjust to match your region's typical climate.
    static let baselineMaxTempC: Double = 26

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
    }
}
