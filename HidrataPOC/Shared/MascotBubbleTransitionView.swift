import SwiftUI

/// Transição entre estágios do mascote (mascote5→mascote4 etc.), estilo a
/// transição de cena do Bob Esponja: uma cortina de bolhas sobe da base até o
/// topo cobrindo de ponta a ponta (ver `makeBubbles`) e, no auge da cobertura,
/// o mascote ANTIGO por baixo delas é escondido — revelando o mascote novo,
/// que já está sendo exibido normalmente por baixo de tudo. As bolhas
/// continuam subindo e estourando por cima dele até sumirem. Não depende de
/// água real nenhuma, então funciona igual com o recipiente cheio ou quase vazio.
struct MascotBubbleTransitionView: View {
    let imageName: String
    let width: CGFloat
    let height: CGFloat

    @State private var animate = false
    @State private var oldVisible = true
    @State private var bubbles: [RisingBubble]

    /// Quando o mascote antigo some. Não é um palpite: `makeBubbles` resolve,
    /// pra cada bolha, o atraso exato que a faz estar passando pela sua célula
    /// da grade precisamente neste instante — nesse momento (e só nesse), a
    /// grade inteira (toda coluna, toda linha) está ocupada ao mesmo tempo,
    /// tampando o mascote de ponta a ponta e de baixo a cima. Antes disso a
    /// cortina está "enchendo"; depois, continua subindo e "esvaziando" por
    /// cima do que estiver atrás dele (mascote novo ou não, dependendo de
    /// quando quem chama decidir mostrá-lo — ver `handleGoalTransition`).
    /// Recebido de fora (em vez de uma constante fixa aqui) pra poder ser
    /// ajustado independente do tempo de aparecer do mascote novo.
    let revealDelay: Double

    init(imageName: String, width: CGFloat, height: CGFloat, revealDelay: Double = 0.75) {
        self.imageName = imageName
        self.width = width
        self.height = height
        self.revealDelay = revealDelay
        _bubbles = State(initialValue: Self.makeBubbles(width: width, height: height, revealDelay: revealDelay))
    }

    var body: some View {
        ZStack {
            if oldVisible {
                // Mesma correção de tamanho do mascote ao vivo, mas aplicada só na
                // imagem (via `scaleEffect`, centrada) — a grade de bolhas abaixo
                // usa `width`/`height` sem correção, pra ter o mesmo tamanho de
                // canvas (e portanto o mesmo tempo/distância de cobertura) em
                // qualquer mascote, em vez de variar com o fator de cada um.
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .scaleEffect(AppTheme.mascotSizeCorrection(for: imageName), anchor: .center)
            }

            ForEach(bubbles) { bubble in
                RisingBubbleView(bubble: bubble, animate: animate, containerWidth: width)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        // Sem transição própria, mesmo motivo do `MascotShatterView`: a troca de
        // ramo do pai não deve ganhar um crossfade por cima disto.
        .transition(.identity)
        .onAppear {
            animate = true
            Task {
                try? await Task.sleep(for: .milliseconds(Int(revealDelay * 1000)))
                oldVisible = false
            }
        }
    }

    fileprivate struct RisingBubble: Identifiable {
        let id: Int
        let xFraction: CGFloat    // 0...1, posição horizontal fixa da bolha
        let diameter: CGFloat
        let baseY: CGFloat        // y inicial, abaixo da moldura (sempre a mesma)
        let travel: CGFloat       // distância vertical total até sair por cima
        let delay: Double         // s — resolvido pra sincronizar com `revealDelay`
        let riseDuration: Double  // s
        let wobbleAmplitude: CGFloat
        let wobbleCycles: Double
        let wobbleSeed: Double
    }

    /// Uma "cortina" de verdade precisa tampar de ponta a ponta — tanto na
    /// largura quanto na altura — bem no instante em que o mascote troca, não
    /// só cruzar por cima dele em algum momento qualquer. Em vez de bolhas
    /// soltas ao acaso, a área é dividida numa grade (`columns` × `rows`), e
    /// cada célula ganha uma bolha cujo atraso é calculado de trás pra frente:
    /// toda bolha sai do mesmo ponto abaixo da moldura (`baseY`) e sobe em
    /// linha reta até sair por cima; resolvendo o atraso a partir de "onde ela
    /// precisa estar em `revealDelay`" (sua célula), toda a grade — todas as
    /// colunas, todas as linhas — se encontra ocupada ao mesmo tempo bem nesse
    /// instante, garantindo a tampa completa. Antes disso vai "enchendo" de
    /// baixo pra cima (células de baixo, mais perto do ponto de partida,
    /// chegam quase na hora; células de cima vêm de mais longe e demoram mais
    /// pra chegar); depois, cada bolha continua reto e sai por cima, então a
    /// cortina "esvazia" de baixo pra cima também — primeiro aparece o novo
    /// mascote na base, por último no topo.
    private static func makeBubbles(width: CGFloat, height: CGFloat, revealDelay: Double) -> [RisingBubble] {
        guard width > 0, height > 0 else { return [] }
        let columns = max(6, Int((width / 32).rounded()))
        let rows = 4
        let columnPitch = width / CGFloat(columns)
        let rowPitch = height / CGFloat(rows)
        // Maior que o espaçamento da grade (não só do que a própria célula),
        // pra sobrepor as vizinhas (inclusive com a folga do balanço
        // horizontal) e não deixar nenhum buraco na tampa.
        let baseDiameter = max(columnPitch, rowPitch) * 1.55

        var bubbles: [RisingBubble] = []
        bubbles.reserveCapacity(columns * rows)
        var id = 0
        for col in 0..<columns {
            let centerX = (CGFloat(col) + 0.5) * columnPitch + CGFloat.random(in: -0.15...0.15) * columnPitch

            for row in 0..<rows {
                let diameter = baseDiameter * CGFloat.random(in: 0.9...1.1)
                let baseY = height + diameter
                let travel = baseY - (-diameter)
                // Linha 0 = célula mais perto da base (y grande); linha
                // `rows-1` = célula mais perto do topo (y pequeno).
                let restY = height - (CGFloat(row) + 0.5) * rowPitch + CGFloat.random(in: -0.2...0.2) * rowPitch
                let riseDuration = 1.0

                // Fração do trajeto total já percorrida quando a bolha cruza
                // `restY` — resolvendo o atraso a partir disso, ela está
                // exatamente ali (não antes, não depois) em `revealDelay`.
                let fraction = Double((baseY - restY) / travel)
                let delay = max(0, revealDelay - riseDuration * fraction)

                bubbles.append(RisingBubble(
                    id: id,
                    xFraction: max(0, min(1, centerX / width)),
                    diameter: diameter,
                    baseY: baseY,
                    travel: travel,
                    delay: delay,
                    riseDuration: riseDuration,
                    wobbleAmplitude: CGFloat.random(in: 3...7),
                    wobbleCycles: Double.random(in: 1...2),
                    wobbleSeed: Double.random(in: 0...(2 * .pi))
                ))
                id += 1
            }
        }
        return bubbles
    }
}

/// Uma bolha subindo: a posição segue `BubbleRiseEffect` (progresso real da
/// subida, pra oscilar de lado enquanto sobe), e opacidade/escala têm sua
/// própria curva `.easeIn` — fica praticamente opaca a maior parte do
/// percurso e só nos 20% finais "estoura" (cresce um pouco e some rápido),
/// em vez de desbotar linearmente do início ao fim.
private struct RisingBubbleView: View {
    let bubble: MascotBubbleTransitionView.RisingBubble
    let animate: Bool
    let containerWidth: CGFloat

    var body: some View {
        BubbleGlyph(diameter: bubble.diameter)
            .position(x: bubble.xFraction * containerWidth, y: bubble.baseY)
            .modifier(BubbleRiseEffect(
                progress: animate ? 1 : 0,
                travel: bubble.travel,
                wobbleAmplitude: bubble.wobbleAmplitude,
                wobbleCycles: bubble.wobbleCycles,
                wobbleSeed: bubble.wobbleSeed
            ))
            .animation(.linear(duration: bubble.riseDuration).delay(bubble.delay), value: animate)
            .scaleEffect(animate ? 1.15 : 1.0)
            .animation(.easeIn(duration: bubble.riseDuration * 0.2).delay(bubble.delay + bubble.riseDuration * 0.8), value: animate)
            .opacity(animate ? 0 : 1)
            .animation(.easeIn(duration: bubble.riseDuration * 0.2).delay(bubble.delay + bubble.riseDuration * 0.8), value: animate)
    }
}

/// Desloca a bolha pra cima (`travel` pontos) conforme `progress` vai de 0 a
/// 1, com uma leve oscilação horizontal (seno) acoplada ao MESMO progresso —
/// não um timer separado — pra ela balançar enquanto sobe, não só deslizar
/// reto. `animatableData` é o que faz o SwiftUI interpolar isso quadro a
/// quadro dentro da animação `.linear` aplicada em `RisingBubbleView`.
private struct BubbleRiseEffect: GeometryEffect {
    var progress: CGFloat
    let travel: CGFloat
    let wobbleAmplitude: CGFloat
    let wobbleCycles: Double
    let wobbleSeed: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dy = -travel * progress
        let dx = wobbleAmplitude * sin(progress * wobbleCycles * 2 * .pi + wobbleSeed)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: dy))
    }
}

/// A "cara" de bolha real: preenchimento de vidro quase transparente, aro com
/// gradiente angular (como a interferência iridescente de uma bolha de sabão
/// de verdade) e dois reflexos — um grande e suave no canto superior-esquerdo
/// (luz principal) e um pontinho menor no inferior-direito (reflexo
/// secundário), em vez de um círculo liso de cor sólida.
private struct BubbleGlyph: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color(red: 0.62, green: 0.85, blue: 1.0).opacity(0.55),
                            Color.white.opacity(0.6),
                        ],
                        center: UnitPoint(x: 0.4, y: 0.38),
                        startRadius: diameter * 0.02,
                        endRadius: diameter * 0.55
                    )
                )

            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.95), .cyan.opacity(0.55), .white.opacity(0.8),
                            .blue.opacity(0.35), .purple.opacity(0.28), .white.opacity(0.95),
                        ],
                        center: .center
                    ),
                    lineWidth: max(1, diameter * 0.04)
                )

            Ellipse()
                .fill(Color.white.opacity(0.82))
                .frame(width: diameter * 0.30, height: diameter * 0.18)
                .rotationEffect(.degrees(-28))
                .offset(x: -diameter * 0.16, y: -diameter * 0.20)
                .blur(radius: diameter * 0.02)

            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: diameter * 0.08, height: diameter * 0.08)
                .offset(x: diameter * 0.20, y: diameter * 0.18)
        }
        .frame(width: diameter, height: diameter)
    }
}
