import Foundation

/// One of the persona-flavored copy variants for hydration reminders — see
/// HYDRATE-NP-01. Selected per-send in `NotificationScheduler.selectVariant(...)`,
/// recorded on `NotificationEvent.notificationVariant` so effectiveness can be
/// compared per variant (and per user) later.
///
/// The persona is the mascot: a kidney stone that taunts the user and pretends to want
/// them *not* to drink. Each variant has several `Copy` options; which one a given
/// reminder uses is fixed by its slot (see `copy(for:)`), so the title, the body and
/// the mascot avatar always agree.
enum NotificationVariant: String, CaseIterable {
    case hotDay = "hot_day"
    case coldDay = "cold_day"
    case mildMorning = "mild_morning"
    case middayNeutral = "midday_neutral"
    case symptomHeadacheMidday = "symptom_headache_midday"
    case symptomConcentrationMidday = "symptom_concentration_midday"
    case streakRiskEvening = "streak_risk_evening"
    case symptomIrritabilityEvening = "symptom_irritability_evening"
    /// The mascot is already in its late stages (`AppTheme.mascotStage` 2 and 1).
    case nearGoal = "near_goal"
    /// The mascot is in the middle stage (`AppTheme.mascotStage` 3): already drank a lot.
    case wellHydrated = "well_hydrated"
    case fallbackGeneric = "fallback_generic"

    struct Copy: Equatable {
        let title: String
        let body: String

        fileprivate init(_ title: String, _ body: String) {
            self.title = title
            self.body = body
        }
    }

    /// The copy a reminder uses: always the same one for the same `slotID`, however many
    /// times it is asked for (the notification is re-armed when its context is refreshed),
    /// and spread across the options between different reminders.
    func copy(for slotID: UUID) -> Copy {
        let options = copies
        let bytes = slotID.uuid
        let seed = Int(bytes.0) << 16 | Int(bytes.1) << 8 | Int(bytes.2)
        return options[seed % options.count]
    }

    /// Every option of the variant — never empty.
    var copies: [Copy] {
        switch self {
        case .hotDay:
            return [
                Copy("35 graus e você de boca seca?", "Meu sonho virou realidade."),
                Copy("Calorão de 40°?", "Perfeito. Meu clima favorito."),
                Copy("Tá derretendo aí?", "Eu tô ótimo."),
                Copy("Protetor solar você passou. E água?", "Ah, nem isso. Ótimo.")
            ]
        case .coldDay:
            return [
                Copy("Cobertor, sofá e zero água?", "Combinação perfeita."),
                Copy("Aquele chocolate quente não é água", "Mas pode continuar achando que é.")
            ]
        case .mildMorning:
            return [
                Copy("Bom dia! Já bebeu água?", "Claro que não. Que orgulho."),
                Copy("Café primeiro, água nunca", "Boa ordem de prioridades."),
                Copy("Acordou e nem olhou pra água", "Continue assim.")
            ]
        case .middayNeutral:
            return [
                Copy("Já passou da hora do almoço", "E o copo continua do mesmo jeito. Que lindo."),
                Copy("Meio-dia e o copo seco", "Hoje tá sendo um bom dia pra mim."),
                Copy("Metade do dia já foi", "E você nem molhou os lábios. Que orgulho."),
                Copy("Quantos copos até agora?", "Zero, pelas minhas contas. Gosto desse número.")
            ]
        case .symptomHeadacheMidday:
            return [
                Copy("Remédio não resolve, né?", "Eu sei o que resolve. Mas não vou contar."),
                Copy("Dorzinha de cabeça? Pois é.", "Trabalho de equipe: eu e a sua falta de água."),
                Copy("Dor de cabeça de novo?", "Já é minha marca registrada.")
            ]
        case .symptomConcentrationMidday:
            return [
                Copy("Esqueceu o que ia fazer?", "Ótimo sinal. Estou fazendo meu trabalho direitinho."),
                Copy("Leu o mesmo parágrafo 3 vezes?", "Isso é obra minha. De nada.")
            ]
        case .streakRiskEvening:
            return [
                Copy("Sua sequência tá por um fio", "Falta pouquinho pra eu comemorar."),
                Copy("A noite chegou e a meta não", "Mais um dia de vitória!"),
                Copy("Já pode ir se despedindo da sequência", "Eu sou inabalável mesmo."),
                Copy("Vitória pra mim!", "Ufa, por um momento achei que iria me derrotar hoje."),
                Copy("Falta tão pouco pra você perder", "Já estou até separando o champanhe.")
            ]
        case .symptomIrritabilityEvening:
            return [
                Copy("Já brigou com alguém hoje?", "Eu só deixei você sem água. O resto foi você.")
            ]
        case .nearGoal:
            return [
                Copy("Faltam só alguns goles", "Hora de parar de beber, não acha?"),
                Copy("Quase lá, hein", "Mas ainda dá tempo de desistir."),
                Copy("Chega, né?", "Já bebeu mais do que o suficiente.")
            ]
        case .wellHydrated:
            return [
                Copy("Já bebeu bastante, hein", "Pode parar. Descansa."),
                Copy("Que sede é essa?", "Aposto que tá com remorso de beber tanto."),
                Copy("Tá bebendo demais", "Ouvi dizer que isso faz mal.")
            ]
        case .fallbackGeneric:
            return [
                Copy("Dica do dia", "Não beba água.")
            ]
        }
    }
}
