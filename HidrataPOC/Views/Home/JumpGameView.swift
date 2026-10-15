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
                Canvas { ctx, size in
                    Self.draw(snapshot, size: size, in: &ctx)
                }
            }
        }
        .allowsHitTesting(false)
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
        }
    }

    private static let leafGreen = Color(red: 0.30, green: 0.72, blue: 0.36)
    private static let leafTeal = Color(red: 0.22, green: 0.70, blue: 0.68)
    private static let leafDry = Color(red: 0.80, green: 0.62, blue: 0.30)

    private static func drawLeaf(_ leaf: JumpGameSnapshot.Leaf, in context: inout GraphicsContext) {
        var ctx = context
        let color: Color = switch leaf.kind {
        case .normal: leafGreen
        case .moving: leafTeal
        case .fragile: leafDry
        }
        if leaf.isTorn {
            // Rasgada: duas metades se abrindo e sumindo enquanto caem.
            ctx.opacity = 0.6
            let half = leaf.rect.width / 2
            let left = CGRect(x: leaf.rect.minX - 4, y: leaf.rect.minY, width: half, height: leaf.rect.height)
            let right = CGRect(x: leaf.rect.midX + 4, y: leaf.rect.minY, width: half, height: leaf.rect.height)
            ctx.fill(Path(roundedRect: left, cornerRadius: leaf.rect.height / 2), with: .color(color))
            ctx.fill(Path(roundedRect: right, cornerRadius: leaf.rect.height / 2), with: .color(color))
            return
        }

        let shape = Path(roundedRect: leaf.rect, cornerRadius: leaf.rect.height / 2)
        ctx.fill(shape.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.18)))
        ctx.fill(shape, with: .linearGradient(
            Gradient(colors: [color.opacity(1), color.mix(with: .black, by: 0.2)]),
            startPoint: CGPoint(x: leaf.rect.midX, y: leaf.rect.minY),
            endPoint: CGPoint(x: leaf.rect.midX, y: leaf.rect.maxY)
        ))
        // Nervura da folha.
        var vein = Path()
        vein.move(to: CGPoint(x: leaf.rect.minX + 8, y: leaf.rect.midY))
        vein.addLine(to: CGPoint(x: leaf.rect.maxX - 8, y: leaf.rect.midY))
        ctx.stroke(vein, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                                               dash: leaf.kind == .fragile ? [4, 4] : []))
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

        // Gota: círculo embaixo, ponta em cima.
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -r * 2.1))
        drop.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.35, y: -r * 1.5), control2: CGPoint(x: r, y: -r * 0.8))
        drop.addArc(center: .zero, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        drop.addCurve(to: CGPoint(x: 0, y: -r * 2.1), control1: CGPoint(x: -r, y: -r * 0.8), control2: CGPoint(x: -r * 0.35, y: -r * 1.5))
        drop.closeSubpath()

        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.16, green: 0.52, blue: 0.95)]),
            startPoint: CGPoint(x: 0, y: -r * 2), endPoint: CGPoint(x: 0, y: r)
        ))
        ctx.stroke(drop, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        // Brilho.
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.9, width: r * 0.45, height: r * 0.6)), with: .color(.white.opacity(0.7)))
        // Olhinhos, olhando pra onde está indo.
        let look = snapshot.facing * r * 0.18
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
            height: height
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorde: \(best) pontos")
    }
}
