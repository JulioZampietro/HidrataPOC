import Foundation

/// One of 9 persona-flavored copy variants for hydration reminders — see
/// HYDRATE-NP-01. Selected per-send in `NotificationScheduler.selectVariant(...)`,
/// recorded on `NotificationEvent.notificationVariant` so effectiveness can be
/// compared per variant (and per user) later.
enum NotificationVariant: String {
    case hotDay = "hot_day"
    case coldDay = "cold_day"
    case mildMorning = "mild_morning"
    case middayNeutral = "midday_neutral"
    case symptomHeadacheMidday = "symptom_headache_midday"
    case symptomConcentrationMidday = "symptom_concentration_midday"
    case streakRiskEvening = "streak_risk_evening"
    case symptomIrritabilityEvening = "symptom_irritability_evening"
    case fallbackGeneric = "fallback_generic"

    var title: String {
        switch self {
        case .hotDay: return "Vai desidratar nesse calor?"
        case .coldDay: return "Esqueceu de beber água de novo?"
        case .mildMorning: return "Não vai beber água?"
        case .middayNeutral: return "Continua sem beber água..."
        case .symptomHeadacheMidday: return "Essa dor de cabeça não é à toa"
        case .symptomConcentrationMidday: return "Não consegue focar?"
        case .streakRiskEvening: return "Vai perder sua sequência?"
        case .symptomIrritabilityEvening: return "Reparou como está irritado hoje?"
        case .fallbackGeneric: return "Hora de beber água 💧"
        }
    }

    var body: String {
        switch self {
        case .hotDay: return "Que calorão. Já estou de cadeira de praia esperando você desidratar."
        case .coldDay: return "Fazendo frio, né. Aposto que você nem vai lembrar de beber água hoje."
        case .mildMorning: return "Bom dia. Você já esqueceu de beber água e nem são 9h."
        case .middayNeutral: return "Faz tempo que você não bebe água. Eu percebi."
        case .symptomHeadacheMidday: return "Aquela dorzinha de cabeça do nada? Sou eu, de nada."
        case .symptomConcentrationMidday: return "Tá difícil de se concentrar aí? Isso é ponto pra mim."
        case .streakRiskEvening: return "Faltam poucas horas pra perder sua sequência pra uma pedra."
        case .symptomIrritabilityEvening: return "Aquela irritação com todo mundo hoje sem motivo? Talvez seja eu fazendo a festa."
        case .fallbackGeneric: return "Um gole agora ajuda a manter sua meta do dia."
        }
    }
}
