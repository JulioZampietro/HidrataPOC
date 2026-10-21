import SwiftUI

/// Desenha a Cobrinha de Pedra (`SnakeGameSimulation`) dentro do recipiente de água, no mesmo lugar
/// dos outros minijogos — então passa pela refração do shader. Recebe toque: deslizar no aquário
/// vira a cobrinha pra direção do deslize (é o único controle; a Home só mostra a dica).
struct SnakeGameView: View {
    let simulation: SnakeGameSimulation
    let water: WaterMotion
    /// Onde o dedo estava na última virada: dá pra virar várias vezes no mesmo arrasto.
    @State private var swipeAnchor: CGPoint?

    /// Arrasto (pt) que conta como deslize pra um lado.
    private static let swipeThreshold: CGFloat = 16

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    Self.draw(snapshot, time: time, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let anchor = swipeAnchor ?? value.startLocation
                    let dx = value.location.x - anchor.x, dy = value.location.y - anchor.y
                    guard max(abs(dx), abs(dy)) >= Self.swipeThreshold else { return }
                    let direction: MazeDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    simulation.setDirection(direction)
                    swipeAnchor = value.location
                }
                .onEnded { _ in swipeAnchor = nil }
        )
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    /// Pó de pedra que voa quando ela come ou desmancha.
    private static let dustColor = Color(red: 0.70, green: 0.60, blue: 0.48)

    private static func draw(_ snapshot: SnakeGameSnapshot, time: Double, size: CGSize, in ctx: inout GraphicsContext) {
        drawBoard(snapshot, in: &ctx)
        let pulse = 1 + 0.1 * CGFloat(sin(time * 6))
        drawFood(at: snapshot.food, stone: snapshot.foodStone, radius: snapshot.tile * 0.4 * pulse, in: &ctx)
        if snapshot.phase == .dying {
            var fading = ctx
            fading.opacity = max(0, 1 - snapshot.phaseProgress * 2.5)
            drawSnake(snapshot, in: &fading)
        } else {
            drawSnake(snapshot, in: &ctx)
        }
        for particle in snapshot.particles {
            var dustCtx = ctx
            dustCtx.opacity = particle.alpha
            let r = particle.radius
            let rect = CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)
            dustCtx.fill(Path(ellipseIn: rect), with: .color(dustColor))
            dustCtx.stroke(Path(ellipseIn: rect), with: .color(dustColor.mix(with: .black, by: 0.4)), lineWidth: 0.6)
        }
        drawHUD(snapshot, size: size, in: &ctx)
    }

    /// Campo: fundo levemente claro com quadriculado suave e borda, pra ver até onde dá pra ir.
    private static func drawBoard(_ snapshot: SnakeGameSnapshot, in ctx: inout GraphicsContext) {
        let board = snapshot.board
        let shape = Path(roundedRect: board, cornerRadius: snapshot.tile * 0.4)
        ctx.fill(shape, with: .color(.white.opacity(0.14)))
        var checker = Path()
        let columns = Int((board.width / snapshot.tile).rounded())
        let rows = Int((board.height / snapshot.tile).rounded())
        for y in 0..<rows {
            for x in 0..<columns where (x + y).isMultiple(of: 2) {
                checker.addRect(CGRect(x: board.minX + CGFloat(x) * snapshot.tile, y: board.minY + CGFloat(y) * snapshot.tile,
                                       width: snapshot.tile, height: snapshot.tile))
            }
        }
        var clipped = ctx
        clipped.clip(to: shape)
        clipped.fill(checker, with: .color(.white.opacity(0.08)))
        ctx.stroke(shape, with: .color(.white.opacity(0.55)), lineWidth: 2)
    }

    /// Cor viva da pedrinha (as mesmas das Bolhas Coloridas), puxada um pouco pro tom de pedra.
    private static func tint(_ stone: SnakeGameSnapshot.Stone) -> Color {
        BubbleGameTuning.colors[stone.colorIndex % BubbleGameTuning.colors.count].mix(with: PebbleDrawing.stoneBrown, by: 0.12)
    }

    /// Pedrinha colorida pra comer, pulsando; depois de comida ela entra no corpo com essa cara.
    private static func drawFood(at point: CGPoint, stone: SnakeGameSnapshot.Stone, radius: CGFloat, in ctx: inout GraphicsContext) {
        PebbleDrawing.draw(center: point, radiusX: radius, radiusY: radius, tint: tint(stone),
                           seed: stone.seed, castsShadow: true, in: &ctx)
    }

    /// Corpo de pedrinhas coloridas (as que ela comeu, `segmentStones`), menores pro rabo, cada
    /// uma com sua cor e formato; a cabeça é a pedra marrom maior, com olhos bravos olhando pra
    /// onde ela vai. Desenha do rabo pra cabeça, pra cada pedra ficar por cima da de trás.
    private static func drawSnake(_ snapshot: SnakeGameSnapshot, in ctx: inout GraphicsContext) {
        let segments = snapshot.segments
        guard let head = segments.first else { return }
        let tile = snapshot.tile

        for (index, point) in segments.enumerated().reversed() where index > 0 {
            let shrink = CGFloat(index) / CGFloat(max(segments.count, 1))
            let r = tile * (0.5 - 0.14 * shrink)
            let stone = index < snapshot.segmentStones.count ? snapshot.segmentStones[index] : SnakeGameSnapshot.Stone(colorIndex: index, seed: index &* 7919)
            PebbleDrawing.draw(center: point, radiusX: r, radiusY: r, tint: tint(stone),
                               seed: stone.seed, castsShadow: true, in: &ctx)
        }

        let r = tile * 0.58
        PebbleDrawing.draw(center: head, radiusX: r, radiusY: r, tint: Color(red: 0.52, green: 0.44, blue: 0.36),
                           seed: 424_242, castsShadow: true, in: &ctx)
        drawEyes(at: head, radius: r, heading: snapshot.heading, in: &ctx)
    }

    /// Olhos da cabeça: brancos com pupila deslocada pra frente e sobrancelha brava, como o mascote.
    private static func drawEyes(at center: CGPoint, radius r: CGFloat, heading: MazeDirection, in ctx: inout GraphicsContext) {
        let forward = CGVector(dx: CGFloat(heading.delta.x), dy: CGFloat(heading.delta.y))
        let side = CGVector(dx: -forward.dy, dy: forward.dx)
        let ink = Color(red: 0.18, green: 0.13, blue: 0.10)
        for s: CGFloat in [-1, 1] {
            let eye = CGPoint(x: center.x + forward.dx * r * 0.3 + side.dx * s * r * 0.36,
                              y: center.y + forward.dy * r * 0.3 + side.dy * s * r * 0.36)
            let er = r * 0.24
            ctx.fill(Path(ellipseIn: CGRect(x: eye.x - er, y: eye.y - er, width: er * 2, height: er * 2)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: eye.x - er, y: eye.y - er, width: er * 2, height: er * 2)), with: .color(ink), lineWidth: 1)
            let pr = er * 0.5
            let pupil = CGPoint(x: eye.x + forward.dx * er * 0.4, y: eye.y + forward.dy * er * 0.4)
            ctx.fill(Path(ellipseIn: CGRect(x: pupil.x - pr, y: pupil.y - pr, width: pr * 2, height: pr * 2)), with: .color(ink))
            // Sobrancelha: atrás do olho, inclinada pro meio da cabeça.
            var brow = Path()
            let back = CGPoint(x: eye.x - forward.dx * er * 1.3, y: eye.y - forward.dy * er * 1.3)
            brow.move(to: CGPoint(x: back.x + side.dx * s * er * 1.1, y: back.y + side.dy * s * er * 1.1))
            brow.addLine(to: CGPoint(x: back.x - side.dx * s * er * 0.9 + forward.dx * er * 0.6,
                                     y: back.y - side.dy * s * er * 0.9 + forward.dy * er * 0.6))
            ctx.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Pontos no meio do cabeçalho (entre a seta de voltar e o botão de minijogos) e os avisos.
    private static func drawHUD(_ snapshot: SnakeGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 26).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 26)
        )
        let message: String? = switch snapshot.phase {
        case .ready: "Deslize pra começar"
        case .dying: "Splash!"
        case .playing: nil
        }
        if let message {
            textCtx.draw(
                Text(message)
                    .font(.custom("Nunito", size: 22).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: snapshot.board.midY - snapshot.tile * 2)
            )
        }
    }
}
