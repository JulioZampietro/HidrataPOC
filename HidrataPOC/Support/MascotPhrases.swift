import Foundation

/// Situação em que o mascote vai falar: decide quais falas estão liberadas agora.
struct MascotPhraseContext {
    /// 5 (mascote forte) a 1 (quase derrotado); nil com a meta batida (o mascote some).
    var stage: Int?
    /// Hora do dia, de 0 a 23.
    var hour: Int
    /// O último registro de hoje foi um gole.
    var lastIntakeWasGole: Bool
    /// O último registro de hoje não fez o mascote mudar de tamanho (de estágio).
    var lastIntakeKeptStage: Bool
    /// O dia está seco (umidade abaixo de `Constants.mascotDryHumidityPct`).
    var isDryDay: Bool

    enum Period {
        case morning, afternoon, night
    }

    var period: Period {
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        default: return .night
        }
    }
}

/// Todas as falas do balão do mascote da tela inicial, em um lugar só (no mesmo espírito
/// do `AppFont` e do `Haptic`). O mascote é uma pedra no rim: vilã, quer que o usuário
/// *não* beba, e quanto mais ele bebe mais ela encolhe e se desespera.
enum MascotPhrases {
    /// Falas que o mascote solta sozinho, trocando de tempos em tempos: as do estágio atual
    /// somadas às da hora do dia, só as que valem para a situação de agora.
    static func idle(in context: MascotPhraseContext) -> [String] {
        let stage = context.stage.map(stagePhrases) ?? []
        return (stage + timeOfDayPhrases(context.period))
            .filter { $0.isAllowed(in: context) }
            .map(\.text)
    }

    /// Cutucões (1º e 2º toques).
    static let pokes = [
        "Tá procurando briga?",
        "Ei! quem foi?",
        "Sai daí",
        "Não encosta",
        "Ei!",
        "Opa",
        "Que foi?",
        "Isso faz cócegas"
    ]

    /// Reclamação do 3º cutucão seguido.
    static let pokeComplaints = [
        "Eu tenho sentimentos, sabia?",
        "Quer brigar? Vem!",
        "Para de me cutucar, zé mané"
    ]

    /// Logo depois de registrar água.
    static let drinkReactions = [
        "Cospe isso agora!",
        "Tá me afogando de propósito?",
        "Ai",
        "Isso doeu",
        "Traidor"
    ]

    // MARK: - Falas com condição

    /// Quando uma fala só pode aparecer em certas situações.
    private enum Condition {
        /// O último registro foi um gole.
        case gole
        /// O último registro não mudou o tamanho do mascote.
        case keptSize
        /// Dia seco.
        case dryDay
        /// Bebeu pouco até agora (estágios 5 e 4): a fala debocha de quem mal bebeu.
        case drankLittle

        func isMet(in context: MascotPhraseContext) -> Bool {
            switch self {
            case .gole: return context.lastIntakeWasGole
            case .keptSize: return context.lastIntakeKeptStage
            case .dryDay: return context.isDryDay
            case .drankLittle: return (context.stage ?? 0) >= 4
            }
        }
    }

    private struct Phrase {
        let text: String
        let condition: Condition?

        init(_ text: String, when condition: Condition? = nil) {
            self.text = text
            self.condition = condition
        }

        func isAllowed(in context: MascotPhraseContext) -> Bool {
            condition?.isMet(in: context) ?? true
        }
    }

    // MARK: - Por estágio

    private static func stagePhrases(_ stage: Int) -> [Phrase] {
        switch stage {
        case 5: // abaixo de 20%: confiante, no controle
            return [
                Phrase("Pode esquecer a garrafa. Eu cuido de tudo"),
                Phrase("Ótimo. Mais um dia sem água"),
                Phrase("Hoje o dia é meu"),
                Phrase("Nem começou a beber, né? Continue assim")
            ]
        case 4: // 20–40%: ainda tranquilo, debochado
            return [
                Phrase("Uma gotinha dessa não me assusta", when: .gole),
                Phrase("Foi só isso? Nem senti", when: .gole),
                Phrase("Boa tentativa. Continuo do mesmo tamanho", when: .keptSize),
                Phrase("Já tá cansado de beber? Descansa aí"),
                Phrase("Isso não é nada pra mim"),
                Phrase("Um golinho? Acha que só isso vai me atingir?", when: .gole)
            ]
        case 3: // 40–60%: começa a ficar incomodado
            return [
                Phrase("Ainda falta muito pra me derrubar"),
                Phrase("Tá bom, tá bom, já chega de água"),
                Phrase("Você tá bebendo demais, não acha?"),
                Phrase("Eu aguento. Eu aguento. Eu... aguento"),
                Phrase("Calma aí, ninguém precisa de tanta água"),
                Phrase("Metade do caminho. E daí?"),
                Phrase("Nem vem que eu ainda sou grande")
            ]
        case 2: // 60–80%: preocupado
            return [
                Phrase("Quem te ensinou a beber tanta água?!"),
                Phrase("Para um pouco e a gente negocia"),
                Phrase("Eu tô encolhendo?!"),
                Phrase("Isso não é justo")
            ]
        case 1: // 80–99%: quase derrotado, implorando
            return [
                Phrase("Eu faço o que você quiser. Só para de beber"),
                Phrase("Por favor, guarda essa garrafa"),
                Phrase("Eu tenho família, sabia?"),
                Phrase("Você não teria coragem... teria?"),
                Phrase("Não, não, não, o último copo não")
            ]
        default:
            return []
        }
    }

    // MARK: - Por hora do dia

    private static func timeOfDayPhrases(_ period: MascotPhraseContext.Period) -> [Phrase] {
        switch period {
        case .morning:
            return [
                Phrase("Que lindo dia pra ficar desidratado, não acha?"),
                Phrase("Café sim, água não. Boa escolha"),
                Phrase("Oi, tenha um péssimo dia")
            ]
        case .afternoon:
            return [
                Phrase("Tá calor, né? Que pena que a garrafa tá longe"),
                Phrase("Aproveita o ar seco da tarde", when: .dryDay),
                Phrase("Já tá tarde, não adianta beber agora")
            ]
        case .night:
            return [
                Phrase("Se beber agora, vai levantar de madrugada"),
                Phrase("Quem bebe água mija na cama"),
                Phrase("Boa noite. A água só atrapalha o sono"),
                Phrase("O dia tá quase no fim. Segura mais um pouco"),
                Phrase("Hoje você quase não precisou de água, bom trabalho", when: .drankLittle)
            ]
        }
    }
}
