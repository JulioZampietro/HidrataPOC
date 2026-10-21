import CoreHaptics
import SwiftUI
import UIKit

/// Única porta de entrada para haptics, no mesmo espírito do `AppFont`: as telas dizem
/// *o que* aconteceu (um toque, uma seleção, um registro de água) e o tipo de vibração
/// de cada coisa fica definido só aqui.
///
/// Cada tipo tem uma "sensação" própria, para o toque dizer sem olhar o que aconteceu:
/// leve para navegar, seco para escolher, firme para confirmar, cheio para registrar água.
@MainActor
enum Haptic {
    /// Toque comum: botões de ação secundária, abrir uma tela, abrir/fechar um painel.
    case tap
    /// Botão principal da tela (Continuar, Salvar, Começar): um pouco mais firme que `tap`.
    case primary
    /// "Clique" de seleção: trocar de página, escolher uma opção, um passo do controle deslizante.
    case selection
    /// Voltar, fechar, cancelar: mais suave que `tap`, é uma saída e não uma ação.
    case dismiss
    /// Algo foi salvo, conectado ou concluído.
    case success
    /// Algo não deu certo ou precisa de atenção (permissão negada, valor inválido).
    case warning
    /// Ação que não tem volta (excluir): pancada seca seguida de um aviso.
    case destructive
    /// Água registrada: pancada cheia e, logo depois, a "marola" da gota na água.
    case drink
    /// Meta do dia batida: comemoração em crescendo.
    case celebrate
    /// Cutucar o mascote: toque macio e elástico.
    case poke
    /// Mascote arrastado ou água se mexendo: tique muito leve, para não cansar.
    case ripple
    /// Bolhas subindo na troca de estágio do mascote: um ronco que vai enchendo até `cover`
    /// (segundos, quando a cortina de bolhas tampa tudo e o mascote troca), estoura nesse
    /// instante e vai se apagando até `total` (segundos, quando a última bolha some).
    case bubbles(cover: Double, total: Double)

    func play() {
        HapticPlayer.shared.play(self)
    }

    /// Deixa os motores prontos para o primeiro toque sair sem atraso. Chamado quando o app abre.
    static func prepare() {
        HapticPlayer.shared.prepare()
    }
}

/// Executa os `Haptic`; só este arquivo o conhece. Os geradores ficam guardados e
/// "preparados" para o toque sair sem atraso — criar um gerador a cada toque faz a
/// primeira vibração chegar atrasada.
@MainActor
private final class HapticPlayer {
    static let shared = HapticPlayer()

    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    /// Sequência em andamento (marola, comemoração). Uma nova ação interrompe a anterior
    /// para os toques não se acumularem quando o usuário registra água várias vezes seguidas.
    private var sequence: Task<Void, Never>?

    private init() {}

    /// Os geradores se desligam sozinhos depois de alguns segundos parados; cada toque
    /// abaixo já deixa o gerador preparado para o próximo.
    func prepare() {
        [soft, light, medium, heavy, rigid].forEach { $0.prepare() }
        selection.prepare()
        notification.prepare()
    }

    func play(_ haptic: Haptic) {
        switch haptic {
        case .tap: impact(light, 0.8)
        case .primary: impact(medium)
        case .selection:
            selection.selectionChanged()
            selection.prepare()
        case .dismiss: impact(soft, 0.7)
        case .success: notify(.success)
        case .warning: notify(.warning)
        case .destructive:
            impact(rigid)
            notify(.warning)
        case .drink:
            run([
                .impact(heavy, 1.0, after: 0),
                .impact(soft, 0.7, after: 0.09),
                .impact(soft, 0.4, after: 0.09)
            ])
        case .celebrate:
            run([
                .impact(heavy, 1.0, after: 0),
                .impact(medium, 0.8, after: 0.1),
                .impact(light, 0.6, after: 0.1),
                .impact(rigid, 0.9, after: 0.12),
                .notification(.success, after: 0.12)
            ])
        case .poke: impact(soft)
        case .ripple: impact(soft, 0.35)
        case let .bubbles(cover, total): playBubbles(cover: cover, total: total)
        }
    }

    private func impact(_ generator: UIImpactFeedbackGenerator, _ intensity: CGFloat = 1) {
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }

    // MARK: - Bolhas (Core Haptics)

    private var engine: CHHapticEngine?
    private var bubblesPlayer: CHHapticPatternPlayer?

    /// O ronco contínuo só existe no Core Haptics; sem ele (iPad, simulador) cai numa
    /// sequência de toques leves com o mesmo desenho: sobe, estoura e some.
    private func playBubbles(cover: Double, total: Double) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = makeEngine() else {
            playBubblesFallback(cover: cover, total: total)
            return
        }
        do {
            try? bubblesPlayer?.stop(atTime: CHHapticTimeImmediate)
            try engine.start()
            let player = try engine.makePlayer(with: try Self.bubblesPattern(cover: cover, total: total))
            try player.start(atTime: CHHapticTimeImmediate)
            bubblesPlayer = player
        } catch {
            playBubblesFallback(cover: cover, total: total)
        }
    }

    private func makeEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard let created = try? CHHapticEngine() else { return nil }
        // O sistema para o motor quando o app vai para segundo plano; o próximo `start()` religa.
        created.isAutoShutdownEnabled = true
        created.resetHandler = { [weak created] in try? created?.start() }
        engine = created
        return created
    }

    private static func bubblesPattern(cover: Double, total: Double) throws -> CHHapticPattern {
        // Ronco: contínuo e grave (nitidez baixa), a força sobe até a cortina tampar tudo
        // e cai depois — o mesmo caminho das bolhas.
        var events = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                ],
                relativeTime: 0,
                duration: total
            )
        ]
        let envelope = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.12),
                .init(relativeTime: cover, value: 0.55),
                .init(relativeTime: total, value: 0.0)
            ],
            relativeTime: 0
        )

        // Estouros: bolhinhas pipocando, mais juntas e mais fortes perto do auge.
        var time = 0.04
        while time < total {
            let nearPeak = Self.proximity(of: time, to: cover, total: total)
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.25 + 0.45 * nearPeak * Double.random(in: 0.6...1))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float.random(in: 0.5...0.9))
                ],
                relativeTime: time
            ))
            time += Double.random(in: 0.05...0.14) + (1 - nearPeak) * 0.08
        }

        // O auge: a cortina tampa o mascote e ele troca.
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: cover
        ))
        return try CHHapticPattern(events: events, parameterCurves: [envelope])
    }

    /// 1 no auge das bolhas (`cover`) e 0 nas pontas: define quão forte e quão junto vem cada estouro.
    private static func proximity(of time: Double, to cover: Double, total: Double) -> Double {
        max(0, 1 - abs(time - cover) / max(cover, total - cover))
    }

    private func playBubblesFallback(cover: Double, total: Double) {
        var beats: [Beat] = []
        var time = 0.0
        var last = 0.0
        var popped = false
        while time < total {
            if !popped, time >= cover {
                beats.append(.impact(heavy, 1, after: cover - last))
                last = cover
                popped = true
            }
            let nearPeak = Self.proximity(of: time, to: cover, total: total)
            beats.append(.impact(time < cover ? light : soft, CGFloat(0.3 + 0.5 * nearPeak), after: max(0, time - last)))
            last = max(last, time)
            time += 0.09 + (1 - nearPeak) * 0.08
        }
        run(beats)
    }

    // MARK: - Sequências

    private enum Beat {
        case impact(UIImpactFeedbackGenerator, CGFloat, after: Double)
        case notification(UINotificationFeedbackGenerator.FeedbackType, after: Double)

        var delay: Double {
            switch self {
            case let .impact(_, _, after), let .notification(_, after): return after
            }
        }
    }

    private func run(_ beats: [Beat]) {
        sequence?.cancel()
        sequence = Task { [notification] in
            for beat in beats {
                if beat.delay > 0 {
                    try? await Task.sleep(for: .seconds(beat.delay))
                }
                guard !Task.isCancelled else { return }
                switch beat {
                case let .impact(generator, intensity, _): generator.impactOccurred(intensity: intensity)
                case let .notification(type, _): notification.notificationOccurred(type)
                }
            }
        }
    }
}

// MARK: - SwiftUI

extension View {
    /// Toca `haptic` quando `value` muda — para trocas que não passam por um botão
    /// (página que desliza, opção de um seletor). O primeiro valor não vibra.
    func haptic<V: Equatable>(_ haptic: Haptic, on value: V) -> some View {
        onChange(of: value) { _, _ in haptic.play() }
    }
}
