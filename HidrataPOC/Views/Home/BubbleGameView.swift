import SwiftUI

/// Desenha o jogo das Bolhas Coloridas (`BubbleGameSimulation`) dentro do recipiente de água,
/// no mesmo lugar dos outros minijogos (`JumpGameView`) — então passa pela refração do shader.
/// Diferente dos outros jogos, recebe toque: arrastar no aquário mira e soltar atira.
struct BubbleGameView: View {
    let simulation: BubbleGameSimulation
    let water: WaterMotion
    @AppStorage(MiniGame.bubblesBestStorageKey) private var best = 0

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                Canvas { ctx, size in
                    Self.draw(snapshot, best: best, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { simulation.touchAim(at: $0.location) }
                .onEnded { simulation.touchRelease(at: $0.location) }
        )
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static func draw(_ snapshot: BubbleGameSnapshot, best: Int, size: CGSize, in ctx: inout GraphicsContext) {
        drawDangerLine(snapshot, size: size, in: &ctx)
        for (index, point) in snapshot.aimGuide.enumerated() {
            let fade = 1 - CGFloat(index) / CGFloat(max(snapshot.aimGuide.count, 1))
            let r: CGFloat = 2.6
            let dot = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            let strength: CGFloat = snapshot.isTouchAiming ? 0.9 : 0.7
            ctx.fill(dot, with: .color(ink.opacity(strength * fade)))
            ctx.stroke(dot, with: .color(.white.opacity(0.8 * fade)), lineWidth: 1)
        }
        for bubble in snapshot.bubbles { drawStone(bubble, radius: snapshot.radius, in: &ctx) }
        for spark in snapshot.sparks {
            let rect = CGRect(x: spark.position.x - spark.radius, y: spark.position.y - spark.radius,
                              width: spark.radius * 2, height: spark.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(spark.alpha)))
        }
        if let shot = snapshot.shot { drawStone(shot, radius: snapshot.radius, in: &ctx) }
        drawCannon(snapshot, in: &ctx)

        // Pontos e recorde à esquerda do canhão, na cor `ink` com um halo pra destacar da água.
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: halo, radius: 2))
        let scoreX = snapshot.shooter.x - snapshot.radius * 4.6
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 26).weight(.black))
                .foregroundStyle(ink),
            at: CGPoint(x: scoreX, y: snapshot.shooter.y - 6)
        )
        textCtx.draw(
            Text("Recorde \(max(best, snapshot.score))")
                .font(.custom("Nunito", size: 11).weight(.bold))
                .foregroundStyle(ink.opacity(0.8)),
            at: CGPoint(x: scoreX, y: snapshot.shooter.y + 15)
        )
        if snapshot.isGameOver {
            textCtx.draw(
                Text("Splash!")
                    .font(.custom("Nunito", size: 28).weight(.black))
                    .foregroundStyle(ink),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        }
    }

    /// Cor dos textos, da mira e do canhão: azul escuro sobre a água clara, azul claro sobre a
    /// água escura do modo escuro (o `Canvas` resolve a cor dinâmica pelo ambiente).
    private static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.72, green: 0.87, blue: 1.0, alpha: 1)
        : UIColor(red: 0.07, green: 0.30, blue: 0.72, alpha: 1) })
    private static let halo = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.5)
        : UIColor.white.withAlphaComponent(0.6) })

    /// Linha tracejada que as pedrinhas não podem passar; fica vermelha conforme elas chegam perto.
    private static func drawDangerLine(_ snapshot: BubbleGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var line = Path()
        let y = snapshot.dangerY + snapshot.radius
        line.move(to: CGPoint(x: 16, y: y))
        line.addLine(to: CGPoint(x: size.width - 16, y: y))
        let color = Color.white.mix(with: Color(red: 0.95, green: 0.25, blue: 0.3), by: snapshot.dangerLevel)
        ctx.stroke(line, with: .color(color.opacity(0.3 + 0.4 * snapshot.dangerLevel)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
    }

    private static func color(_ index: Int) -> Color {
        BubbleGameTuning.colors[index % BubbleGameTuning.colors.count]
    }

    /// Marrom das pedrinhas do rim: puxa um pouco as cores vivas pro tom de pedra.
    private static let stoneBrown = Color(red: 0.55, green: 0.44, blue: 0.33)
    /// Direção de onde vem a luz (cima-esquerda), a mesma das pedrinhas do aquário.
    private static let lightDirection = CGVector(dx: -0.55, dy: -0.83)

    /// Pedrinha colorida no estilo das pedrinhas do rim (e dos cacos do mascote): contorno
    /// irregular de 7 a 9 lados, uma face de cima clara puxada pra luz e faces laterais em volta,
    /// cada uma mais clara ou mais escura conforme está virada pra luz, com borda escura e um
    /// brilho pequeno. A semente (`seed`) fixa o formato.
    private static func drawStone(_ stone: BubbleGameSnapshot.Bubble, radius: CGFloat, in context: inout GraphicsContext) {
        var ctx = context
        ctx.opacity = stone.alpha
        let r = radius * stone.scale * 0.98
        let c = stone.position
        var random = SeededRandom(seed: UInt64(stone.seed))

        let sides = 7 + Int(random.next() * 3)
        let start = random.next() * 2 * .pi
        let vertices: [CGPoint] = (0..<sides).map { i in
            let angle = start + (CGFloat(i) + (random.next() - 0.5) * 0.5) / CGFloat(sides) * 2 * .pi
            let distance = r * (0.84 + 0.16 * random.next())
            return CGPoint(x: c.x + cos(angle) * distance, y: c.y + sin(angle) * distance)
        }
        // Face de cima: o mesmo contorno, menor e deslocado pra luz (cima-esquerda).
        let topCenter = CGPoint(x: c.x - r * (0.1 + 0.08 * random.next()), y: c.y - r * (0.14 + 0.08 * random.next()))
        let topScale = 0.5 + 0.1 * random.next()
        let top = vertices.map { CGPoint(x: topCenter.x + ($0.x - c.x) * topScale, y: topCenter.y + ($0.y - c.y) * topScale) }

        let tint = color(stone.colorIndex).mix(with: stoneBrown, by: 0.12)
        let edge = tint.mix(with: .black, by: 0.5)
        for i in vertices.indices {
            let j = (i + 1) % vertices.count
            var face = Path()
            face.addLines([vertices[i], vertices[j], top[j], top[i]])
            face.closeSubpath()
            let mid = CGPoint(x: (vertices[i].x + vertices[j].x) / 2 - c.x, y: (vertices[i].y + vertices[j].y) / 2 - c.y)
            let length = max(hypot(mid.x, mid.y), 0.001)
            let light = (mid.x * lightDirection.dx + mid.y * lightDirection.dy) / length
            let shade = light > 0 ? tint.mix(with: .white, by: 0.12 * light) : tint.mix(with: .black, by: 0.32 * -light)
            ctx.fill(face, with: .color(shade))
            ctx.stroke(face, with: .color(edge.opacity(0.3)), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        }
        var topFace = Path()
        topFace.addLines(top)
        topFace.closeSubpath()
        ctx.fill(topFace, with: .color(tint.mix(with: .white, by: 0.2)))

        var outline = Path()
        outline.addLines(vertices)
        outline.closeSubpath()
        ctx.stroke(outline, with: .color(edge), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        // Brilho: manchinha clara na face de cima, como nas pedrinhas do mascote.
        ctx.fill(Path(ellipseIn: CGRect(x: topCenter.x - r * 0.3, y: topCenter.y - r * 0.24, width: r * 0.3, height: r * 0.18)),
                 with: .color(.white.opacity(0.5)))
    }

    /// Canhão: um bocal que gira com a mira, a pedrinha carregada no meio e a próxima ao lado,
    /// com bolinhas embaixo contando os tiros que faltam até descer uma linha nova.
    private static func drawCannon(_ snapshot: BubbleGameSnapshot, in context: inout GraphicsContext) {
        let r = snapshot.radius
        let c = snapshot.shooter

        var barrelCtx = context
        barrelCtx.translateBy(x: c.x, y: c.y)
        barrelCtx.rotate(by: .radians(Double(snapshot.aimAngle)))
        let barrel = Path(roundedRect: CGRect(x: -r * 0.55, y: -r * 2, width: r * 1.1, height: r * 2), cornerRadius: r * 0.3)
        barrelCtx.fill(barrel, with: .linearGradient(
            Gradient(colors: [Color(red: 0.36, green: 0.68, blue: 1.0), ink]),
            startPoint: CGPoint(x: -r * 0.55, y: 0), endPoint: CGPoint(x: r * 0.55, y: 0)
        ))
        barrelCtx.stroke(barrel, with: .color(.white.opacity(0.8)), lineWidth: 1.5)

        if !snapshot.isGameOver {
            drawStone(snapshot.loaded, radius: r, in: &context)
            drawStone(snapshot.next, radius: r, in: &context)
        }

        let count = BubbleGameTuning.missesBeforeNewRow
        let dot: CGFloat = 3
        let spacing: CGFloat = 9
        for i in 0..<count {
            let x = c.x + (CGFloat(i) - CGFloat(count - 1) / 2) * spacing
            let rect = CGRect(x: x - dot, y: c.y + r + 8 - dot, width: dot * 2, height: dot * 2)
            let filled = i < snapshot.shotsUntilNewRow
            context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(filled ? 0.75 : 0.18)))
        }
    }
}

/// Gerador pseudoaleatório com semente (SplitMix64): a mesma semente dá sempre o mesmo
/// formato de pedrinha, frame após frame.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// Próximo número entre 0 e 1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
