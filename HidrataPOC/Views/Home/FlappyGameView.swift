import SwiftUI

/// Desenha a Gota Voadora (`FlappyGameSimulation`) dentro do recipiente de água, no mesmo lugar
/// dos outros minijogos — então passa pela refração do shader. Recebe toque: tocar em qualquer
/// lugar do aquário faz a gota nadar pra cima (o botão do meio na Home faz o mesmo).
struct FlappyGameView: View {
    let simulation: FlappyGameSimulation
    let water: WaterMotion

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    MiniGameBackdrop.draw(time: time, size: size, in: &ctx)
                    Self.draw(snapshot, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { simulation.flap() }
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static func draw(_ snapshot: FlappyGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        for column in snapshot.columns { drawColumn(column, height: size.height, in: &ctx) }
        for bubble in snapshot.bubbles {
            let rect = CGRect(x: bubble.position.x - bubble.radius, y: bubble.position.y - bubble.radius,
                              width: bubble.radius * 2, height: bubble.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(bubble.alpha)))
        }
        for droplet in snapshot.droplets { drawDroplet(droplet, in: &ctx) }
        if snapshot.phase != .gameOver { drawDrop(snapshot, in: &ctx) }

        // Pontos logo abaixo do cabeçalho, como na Gota Saltitante. Sombra azul pra ler o branco
        // em cima da água clara.
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        if snapshot.phase != .ready {
            textCtx.draw(
                Text("\(snapshot.score)")
                    .font(.custom("Nunito", size: 34).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: 84)
            )
        }
        switch snapshot.phase {
        case .ready:
            GameStartPrompt.draw(hint: "Cada toque faz a gota nadar pra cima", centerY: size.height * 0.3, size: size, in: &ctx)
        case .gameOver:
            textCtx.draw(
                Text("Splash!")
                    .font(.custom("Nunito", size: 28).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        case .playing:
            break
        }
    }

    private static let stoneBrown = Color(red: 0.62, green: 0.50, blue: 0.38)
    private static let stoneGray = Color(red: 0.56, green: 0.58, blue: 0.62)

    /// Coluna de pedras empilhadas: uma pilha descendo do topo até o vão e outra subindo do fundo
    /// a partir dele. Cada pedra tem semente própria (a da coluna + o índice), então a pilha não
    /// muda de cara enquanto anda.
    private static func drawColumn(_ column: FlappyGameSnapshot.Column, height: CGFloat, in ctx: inout GraphicsContext) {
        let rx = column.width / 2 + 3
        let step = column.width * 0.62
        let ry = step * 0.62
        var index = 0

        func stone(atY y: CGFloat) {
            let jitter = CGFloat((column.seed &+ index &* 7919) % 7) - 3 // −3…3 pt pra pilha não ficar reta
            let mix = CGFloat((column.seed &+ index &* 104_729) % 100) / 100
            PebbleDrawing.draw(center: CGPoint(x: column.x + jitter, y: y), radiusX: rx, radiusY: ry,
                               tint: stoneBrown.mix(with: stoneGray, by: mix), seed: column.seed &+ index,
                               sides: 8...10, castsShadow: true, in: &ctx)
            index += 1
        }

        // De cima: a pedra mais baixa encosta no vão; as outras sobem até sair da tela.
        var y = column.gapTop - ry * 0.85
        var tops: [CGFloat] = []
        while y > -ry {
            tops.append(y)
            y -= step
        }
        for y in tops.reversed() { stone(atY: y) } // de cima pra baixo, pra sombra cair na de baixo
        // De baixo: a pedra mais alta encosta no vão; as outras descem até o fundo.
        y = column.gapBottom + ry * 0.85
        while y < height + ry {
            stone(atY: y)
            y += step
        }
    }

    /// A gota sempre de pé (ponta pra cima), olhando pra frente (direita), de onde vêm as pedras.
    private static func drawDrop(_ snapshot: FlappyGameSnapshot, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: snapshot.drop.x, y: snapshot.drop.y)
        DropDrawing.draw(radius: snapshot.dropRadius, facing: 1, in: &ctx)
    }

    /// Gotinha da explosão: no mesmo azul da gota, com borda branca e brilho.
    private static func drawDroplet(_ droplet: FlappyGameSnapshot.Bubble, in context: inout GraphicsContext) {
        var ctx = context
        ctx.opacity = droplet.alpha
        let r = droplet.radius
        let rect = CGRect(x: droplet.position.x - r, y: droplet.position.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.16, green: 0.52, blue: 0.95)]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + r * 0.45, y: rect.minY + r * 0.4, width: r * 0.55, height: r * 0.55)),
                 with: .color(.white.opacity(0.7)))
    }
}
