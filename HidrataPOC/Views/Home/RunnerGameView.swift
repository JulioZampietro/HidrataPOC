import SwiftUI

/// Desenha a Gota Surfista (`RunnerGameSimulation`) dentro do recipiente de água, no mesmo lugar
/// dos outros minijogos — então passa pela refração do shader. Recebe toque: deslizar no aquário
/// troca de pista, pula ou abaixa (é o único controle; a Home só mostra a dica). Cada tipo de
/// obstáculo tem uma cor, pra reconhecer de longe o que fazer: amarela = pula, roxa = abaixa,
/// vermelha = desvia.
struct RunnerGameView: View {
    let simulation: RunnerGameSimulation
    let water: WaterMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Este arrasto já mandou o comando dele: um deslize vale um comando só, então não dá pra
    /// atravessar da pista da direita pra da esquerda sem tirar o dedo.
    @State private var didSwipe = false

    /// Arrasto (pt) que conta como deslize pra um lado.
    private static let swipeThreshold: CGFloat = 18

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                let track = colorScheme == .dark ? TrackStyle.dark : TrackStyle.light
                Canvas { ctx, size in
                    MiniGameBackdrop.draw(time: time, size: size, in: &ctx)
                    Self.draw(snapshot, track: track, time: time, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { simulation.begin() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard !didSwipe else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    guard max(abs(dx), abs(dy)) >= Self.swipeThreshold else { return }
                    let direction: MazeDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    simulation.swipe(direction)
                    didSwipe = true
                }
                .onEnded { _ in didSwipe = false }
        )
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static let splashColor = Color(red: 0.78, green: 0.93, blue: 1.0)

    /// Cores da pista. No claro, branco some no fundo claro do app (e na água rasa), então a
    /// pista é azul; no escuro, branca.
    private struct TrackStyle {
        let ink: Color
        let roadFar: Double
        let roadNear: Double
        let edge: Double
        let dash: Double

        static let light = TrackStyle(ink: Color(red: 0.05, green: 0.34, blue: 0.82), roadFar: 0.04, roadNear: 0.16, edge: 0.55, dash: 0.45)
        static let dark = TrackStyle(ink: .white, roadFar: 0.04, roadNear: 0.24, edge: 0.6, dash: 0.5)
    }

    /// Cor de cada tipo de obstáculo (as das Bolhas Coloridas, puxadas um pouco pro tom de pedra).
    private static func tint(_ kind: RunnerGameSnapshot.Kind) -> Color {
        let color = switch kind {
        case .rock: BubbleGameTuning.colors[1]   // amarela: pula
        case .arch: BubbleGameTuning.colors[3]   // roxa: abaixa
        case .pile: BubbleGameTuning.colors[0]   // vermelha: desvia
        }
        return color.mix(with: PebbleDrawing.stoneBrown, by: 0.12)
    }
    private static let boardColors = [Color(red: 1.0, green: 0.86, blue: 0.40), Color(red: 0.98, green: 0.62, blue: 0.24)]

    /// O que vai na pista, desenhado do mais longe pro mais perto.
    private enum Item {
        case obstacle(RunnerGameSnapshot.Obstacle)
        case drop(RunnerGameSnapshot.Drop)
        case player
    }

    private static func draw(_ snapshot: RunnerGameSnapshot, track: TrackStyle, time: Double, size: CGSize, in ctx: inout GraphicsContext) {
        drawTrack(snapshot, style: track, in: &ctx)

        var items: [(z: CGFloat, item: Item)] = [(0, .player)]
        items += snapshot.obstacles.map { ($0.z, .obstacle($0)) }
        items += snapshot.drops.map { ($0.z, .drop($0)) }
        for (z, item) in items.sorted(by: { $0.z > $1.z }) {
            var itemCtx = ctx
            // Some na neblina lá no fundo, em vez de surgir de repente.
            itemCtx.opacity = min(1, (RunnerProjection.farZ - z) / 14)
            switch item {
            case let .obstacle(obstacle): drawObstacle(obstacle, projection: snapshot.projection, in: &itemCtx)
            case let .drop(drop): drawDrop(drop, time: time, projection: snapshot.projection, in: &itemCtx)
            case .player: drawPlayer(snapshot, in: &itemCtx)
            }
        }

        for particle in snapshot.particles {
            var splashCtx = ctx
            splashCtx.opacity = particle.alpha
            let r = particle.radius
            splashCtx.fill(Path(ellipseIn: CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)),
                           with: .color(splashColor))
        }
        drawHUD(snapshot, size: size, in: &ctx)
    }

    /// Pista: faixa translúcida que afina até o horizonte, com bordas e as faixas tracejadas entre
    /// as pistas andando na velocidade da gota.
    private static func drawTrack(_ snapshot: RunnerGameSnapshot, style: TrackStyle, in ctx: inout GraphicsContext) {
        let projection = snapshot.projection
        let near: CGFloat = -3, far = RunnerProjection.farZ
        var road = Path()
        road.addLines([
            projection.point(lane: -1.55, z: near), projection.point(lane: 1.55, z: near),
            projection.point(lane: 1.55, z: far), projection.point(lane: -1.55, z: far),
        ])
        road.closeSubpath()
        ctx.fill(road, with: .linearGradient(
            Gradient(colors: [style.ink.opacity(style.roadFar), style.ink.opacity(style.roadNear)]),
            startPoint: CGPoint(x: 0, y: projection.horizonY), endPoint: CGPoint(x: 0, y: projection.groundY)
        ))
        var edges = Path()
        for lane: CGFloat in [-1.55, 1.55] {
            edges.move(to: projection.point(lane: lane, z: near))
            edges.addLine(to: projection.point(lane: lane, z: far))
        }
        ctx.stroke(edges, with: .color(style.ink.opacity(style.edge)), lineWidth: 2)

        let period: CGFloat = 6, dash: CGFloat = 3, halfWidth: CGFloat = 0.03
        let offset = snapshot.travelled.truncatingRemainder(dividingBy: period)
        var dashes = Path()
        for lane: CGFloat in [-0.5, 0.5] {
            for k in 0...Int(far / period) + 1 {
                let z0 = max(near, CGFloat(k) * period - offset), z1 = min(far, z0 + dash)
                guard z1 > z0 else { continue }
                dashes.addLines([
                    projection.point(lane: lane - halfWidth, z: z0), projection.point(lane: lane + halfWidth, z: z0),
                    projection.point(lane: lane + halfWidth, z: z1), projection.point(lane: lane - halfWidth, z: z1),
                ])
                dashes.closeSubpath()
            }
        }
        ctx.fill(dashes, with: .color(style.ink.opacity(style.dash)))
    }

    private static func drawObstacle(_ obstacle: RunnerGameSnapshot.Obstacle, projection: RunnerProjection, in ctx: inout GraphicsContext) {
        let m = projection.meter * projection.scale(at: obstacle.z)
        let tint = tint(obstacle.kind)
        switch obstacle.kind {
        case .rock:
            PebbleDrawing.draw(center: projection.point(lane: obstacle.lane, height: 0.32, z: obstacle.z),
                               radiusX: 0.55 * m, radiusY: 0.36 * m, tint: tint, seed: obstacle.seed, castsShadow: true, in: &ctx)
        case .pile:
            let stones: [(height: CGFloat, radius: CGFloat)] = [(0.4, 0.58), (1.12, 0.5), (1.78, 0.42)]
            for (i, (height, radius)) in stones.enumerated() {
                PebbleDrawing.draw(center: projection.point(lane: obstacle.lane, height: height, z: obstacle.z),
                                   radiusX: radius * m, radiusY: radius * 0.78 * m,
                                   tint: tint.mix(with: i.isMultiple(of: 2) ? .black : .white, by: 0.1),
                                   seed: obstacle.seed &+ i, castsShadow: i == 0, in: &ctx)
            }
        case .arch:
            // Duas colunas baixas de pedrinhas e a laje por cima, com vão embaixo.
            let columnHeights: [CGFloat] = [0.22, 0.62]
            for side: CGFloat in [-0.36, 0.36] {
                for (i, height) in columnHeights.enumerated() {
                    PebbleDrawing.draw(center: projection.point(lane: obstacle.lane + side, height: height, z: obstacle.z),
                                       radiusX: 0.2 * m, radiusY: 0.2 * m, tint: tint,
                                       seed: obstacle.seed &+ i &+ (side > 0 ? 7 : 0), castsShadow: i == 0, in: &ctx)
                }
            }
            PebbleDrawing.draw(center: projection.point(lane: obstacle.lane, height: 1.08, z: obstacle.z),
                               radiusX: 0.86 * m, radiusY: 0.22 * m, tint: tint.mix(with: .white, by: 0.08),
                               seed: obstacle.seed &+ 3, sides: 6...7, castsShadow: true, in: &ctx)
        }
    }

    /// Gotinha pra pegar, boiando de leve.
    private static func drawDrop(_ drop: RunnerGameSnapshot.Drop, time: Double, projection: RunnerProjection, in ctx: inout GraphicsContext) {
        let m = projection.meter * projection.scale(at: drop.z)
        let bob = 0.08 * CGFloat(sin(time * 5 + Double(drop.z)))
        let center = projection.point(lane: drop.lane, height: drop.height + bob, z: drop.z)
        var dropCtx = ctx
        dropCtx.translateBy(x: center.x, y: center.y)
        DropDrawing.draw(radius: 0.17 * m, facing: 0, eyes: false, in: &dropCtx)
    }

    /// A gota em pé na prancha: sombra no chão (some conforme sobe), prancha inclinando pro lado
    /// em que vai, e a gota achatada quando abaixa. Batendo, pisca.
    private static func drawPlayer(_ snapshot: RunnerGameSnapshot, in ctx: inout GraphicsContext) {
        let projection = snapshot.projection
        let m = projection.meter
        let lane = snapshot.playerLane, height = snapshot.playerHeight
        if snapshot.phase == .dying, Int(snapshot.phaseProgress * 14).isMultiple(of: 2) { ctx.opacity *= 0.35 }

        let ground = projection.point(lane: lane, z: 0)
        var shadowCtx = ctx
        shadowCtx.opacity *= 0.22 * (1 - min(0.8, height / 2))
        shadowCtx.fill(Path(ellipseIn: CGRect(x: ground.x - 0.5 * m, y: ground.y - 0.1 * m, width: m, height: 0.2 * m)), with: .color(.black))

        let boardCenter = projection.point(lane: lane, height: height + 0.08, z: 0)
        var boardCtx = ctx
        boardCtx.translateBy(x: boardCenter.x, y: boardCenter.y)
        boardCtx.rotate(by: .radians(Double(snapshot.playerFacing) * 0.18))
        let board = Path(ellipseIn: CGRect(x: -0.5 * m, y: -0.12 * m, width: m, height: 0.24 * m))
        boardCtx.fill(board, with: .linearGradient(Gradient(colors: boardColors), startPoint: CGPoint(x: 0, y: -0.12 * m), endPoint: CGPoint(x: 0, y: 0.12 * m)))
        boardCtx.stroke(board, with: .color(.white.opacity(0.9)), lineWidth: 1.5)

        let r = 0.3 * m
        let foot = projection.point(lane: lane, height: height + 0.14, z: 0)
        var dropCtx = ctx
        // Achata com o "pé" fixo na prancha (mesma ideia do quique da Gota Saltitante).
        dropCtx.translateBy(x: foot.x, y: foot.y)
        dropCtx.scaleBy(x: 1 + 0.35 * snapshot.crouch, y: 1 - 0.45 * snapshot.crouch)
        dropCtx.translateBy(x: 0, y: -r)
        DropDrawing.draw(radius: r, facing: snapshot.playerFacing, in: &dropCtx)
    }

    /// Pontos no meio do cabeçalho (entre a seta de voltar e o botão de minijogos) e os avisos.
    private static func drawHUD(_ snapshot: RunnerGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 26).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 26)
        )
        let message: String? = switch snapshot.phase {
        case .dying: "Splash!"
        case .ready, .playing: nil
        }
        if let message {
            textCtx.draw(
                Text(message)
                    .font(.custom("Nunito", size: 22).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: size.height * 0.42)
            )
        }
        if snapshot.phase == .ready {
            GameStartPrompt.draw(hint: "Deslize pra desviar, pular ou abaixar", centerY: size.height * 0.42, size: size, in: &ctx)
        }
    }
}
