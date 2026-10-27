import SwiftUI

/// Desenha o jogo da Gota Saltitante (`JumpGameSimulation`) dentro do recipiente de água,
/// no mesmo lugar do jogo das argolas (`RingGameView`) — então passa pela refração do shader.
struct JumpGameView: View {
    let simulation: JumpGameSimulation
    let water: WaterMotion

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `RingGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, down: water.down, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    MiniGameBackdrop.draw(time: time, size: size, in: &ctx)
                    Self.draw(snapshot, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { simulation.begin() }
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static func draw(_ snapshot: JumpGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        for leaf in snapshot.leaves { drawLeaf(leaf, in: &ctx) }
        for bubble in snapshot.bubbles {
            let rect = CGRect(x: bubble.position.x - bubble.radius, y: bubble.position.y - bubble.radius,
                              width: bubble.radius * 2, height: bubble.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(bubble.alpha)))
        }
        if !snapshot.isGameOver { drawDrop(snapshot, in: &ctx) }

        // Pontos da partida, logo abaixo do cabeçalho (streak e botões). Sombra azul pra ler
        // o branco em cima da água clara.
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 34).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 84)
        )
        if snapshot.isGameOver {
            textCtx.draw(
                Text("Splash!")
                    .font(.custom("Nunito", size: 28).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            if snapshot.canRetry {
                textCtx.draw(
                    Text("Tentar novamente")
                        .font(.custom("Nunito", size: 20).weight(.black))
                        .foregroundStyle(.white),
                    at: CGPoint(x: size.width / 2, y: size.height / 2 + 36)
                )
            }
        }
        if snapshot.isReady {
            GameStartPrompt.draw(hint: "Use o joystick pra guiar a gota", centerY: size.height * 0.4, size: size, in: &ctx)
        }
    }

    /// Cores das plataformas de pedra, no tom das pedrinhas do rim: marrom (firme), cinza-azulada
    /// (anda de lado) e arenito claro, trincado (quebra ao pisar).
    private static let stoneFirm = Color(red: 0.62, green: 0.50, blue: 0.38)
    private static let stoneMoving = Color(red: 0.52, green: 0.57, blue: 0.64)
    private static let stoneFragile = Color(red: 0.82, green: 0.69, blue: 0.48)

    /// Plataforma: uma laje de pedra facetada (`PebbleDrawing`) com o topo rente ao topo do
    /// `rect`, onde a gota quica; o corpo da pedra desce um pouco abaixo dele.
    private static func drawLeaf(_ leaf: JumpGameSnapshot.Leaf, in context: inout GraphicsContext) {
        var ctx = context
        let color: Color = switch leaf.kind {
        case .normal: stoneFirm
        case .moving: stoneMoving
        case .fragile: stoneFragile
        }
        let rx = leaf.rect.width / 2 + 2
        let ry: CGFloat = 10
        let centerY = leaf.rect.minY + ry * 0.75

        if leaf.isTorn {
            // Quebrada: duas metades se abrindo e sumindo enquanto caem.
            ctx.opacity = 0.6
            for (side, seedOffset) in [(-1.0, 1), (1.0, 2)] {
                let center = CGPoint(x: leaf.rect.midX + CGFloat(side) * (rx / 2 + 4), y: centerY)
                PebbleDrawing.draw(center: center, radiusX: rx / 2, radiusY: ry * 0.9, tint: color,
                                   seed: leaf.seed + seedOffset, sides: 6...7, in: &ctx)
            }
            return
        }

        PebbleDrawing.draw(center: CGPoint(x: leaf.rect.midX, y: centerY), radiusX: rx, radiusY: ry, tint: color,
                           seed: leaf.seed, sides: 9...11, castsShadow: true, cracked: leaf.kind == .fragile, in: &ctx)

        if leaf.hasSpring {
            // Bolha-mola: pisar no meio dela lança a gota bem mais alto.
            let r: CGFloat = 8
            let rect = CGRect(x: leaf.rect.midX - r, y: leaf.rect.minY - r * 2 + 2, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + 4, y: rect.minY + 3, width: 4, height: 4)), with: .color(.white))
        }
    }

    private static func drawDrop(_ snapshot: JumpGameSnapshot, in context: inout GraphicsContext) {
        var ctx = context
        let r = snapshot.dropRadius
        // Achata ao quicar, com o "pé" fixo no chão.
        ctx.translateBy(x: snapshot.drop.x, y: snapshot.drop.y + r)
        ctx.scaleBy(x: 1 + 0.3 * snapshot.squash, y: 1 - 0.3 * snapshot.squash)
        ctx.translateBy(x: 0, y: -r)
        DropDrawing.draw(radius: r, facing: snapshot.facing, in: &ctx)
    }
}

/// A gota com olhinhos, personagem da Gota Saltitante e da Gota Voadora. Desenhada com o centro
/// do círculo de baixo na origem do `context` e a ponta pra cima (a 2,1 × `radius`), então quem
/// chama posiciona, gira e achata com as transformações do `context`.
enum DropDrawing {
    /// `facing`: −1 olhando pra esquerda, 1 pra direita. Sem `eyes`, é só a gota (as gotinhas
    /// que o rim come no Rim Comilão). `tint`: cores de cima e de baixo do degradê (azul por padrão).
    static func draw(radius r: CGFloat, facing: CGFloat, eyes: Bool = true,
                     tint: (top: Color, bottom: Color) = (Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.16, green: 0.52, blue: 0.95)),
                     in ctx: inout GraphicsContext) {
        // Gota: círculo embaixo, ponta em cima.
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -r * 2.1))
        drop.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.35, y: -r * 1.5), control2: CGPoint(x: r, y: -r * 0.8))
        drop.addArc(center: .zero, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        drop.addCurve(to: CGPoint(x: 0, y: -r * 2.1), control1: CGPoint(x: -r, y: -r * 0.8), control2: CGPoint(x: -r * 0.35, y: -r * 1.5))
        drop.closeSubpath()

        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [tint.top, tint.bottom]),
            startPoint: CGPoint(x: 0, y: -r * 2), endPoint: CGPoint(x: 0, y: r)
        ))
        ctx.stroke(drop, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        // Brilho.
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.9, width: r * 0.45, height: r * 0.6)), with: .color(.white.opacity(0.7)))
        guard eyes else { return }
        // Olhinhos, olhando pra onde está indo.
        let look = facing * r * 0.18
        for side: CGFloat in [-1, 1] {
            let eye = CGRect(x: side * r * 0.35 + look - 2, y: -r * 0.15, width: 4, height: 5.5)
            ctx.fill(Path(ellipseIn: eye), with: .color(Color(red: 0.08, green: 0.16, blue: 0.32)))
        }
    }
}

/// Cartão do recorde da Gota Saltitante, no lugar de um cartão de ingestão enquanto o jogo roda.
struct JumpGameRecordCard: View {
    let best: Int
    let height: CGFloat

    var body: some View {
        IntakeCardContent(
            icon: .symbol("trophy.fill"),
            title: "\(best)",
            subtitle: "Recorde",
            height: height,
            textOnTop: true
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorde: \(best) pontos")
    }
}
