import SwiftUI

/// Desenha o jogo das Pedras Coloridas (`PebbleGameSimulation`) dentro do recipiente de água,
/// no mesmo lugar dos outros minijogos (`JumpGameView`) — então passa pela refração do shader.
/// Diferente dos outros jogos, recebe toque: arrastar no aquário mira e soltar atira.
struct PebbleGameView: View {
    let simulation: PebbleGameSimulation
    let water: WaterMotion
    @AppStorage(MiniGame.pebblesBestStorageKey) private var best = 0

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    MiniGameBackdrop.draw(time: time, size: size, in: &ctx)
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

    private static func draw(_ snapshot: PebbleGameSnapshot, best: Int, size: CGSize, in ctx: inout GraphicsContext) {
        drawDangerLine(snapshot, size: size, in: &ctx)
        for (index, point) in snapshot.aimGuide.enumerated() {
            let fade = 1 - CGFloat(index) / CGFloat(max(snapshot.aimGuide.count, 1))
            let r: CGFloat = 2.6
            let dot = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            let strength: CGFloat = snapshot.isTouchAiming ? 0.9 : 0.7
            ctx.fill(dot, with: .color(ink.opacity(strength * fade)))
            ctx.stroke(dot, with: .color(.white.opacity(0.8 * fade)), lineWidth: 1)
        }
        for pebble in snapshot.pebbles { drawStone(pebble, radius: snapshot.radius, in: &ctx) }
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
        GameConfetti.draw(snapshot.confetti, colors: PebbleGameTuning.colors, in: &ctx)
        if snapshot.isReady && !snapshot.isGameOver { drawReadyText(snapshot, size: size, in: &ctx) }
        if snapshot.isGameOver {
            textCtx.draw(
                Text("Splash!")
                    .font(.custom("Nunito", size: 28).weight(.black))
                    .foregroundStyle(ink),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        }
    }

    /// Aviso de início: "Fase N" antes de cada fase e "Parabéns!" depois de limpar a última.
    private static func drawReadyText(_ snapshot: PebbleGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        if snapshot.isCelebrating {
            GameStartPrompt.draw(title: "Parabéns!", action: "Toque pra recomeçar", hint: "Você limpou as 3 fases!",
                                 centerY: size.height * 0.62, size: size, in: &ctx)
        } else {
            GameStartPrompt.draw(title: "Fase \(snapshot.level)",
                                 hint: "Junte \(snapshot.minMatch) ou mais da mesma cor",
                                 centerY: size.height * 0.62, size: size, in: &ctx)
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
    private static func drawDangerLine(_ snapshot: PebbleGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var line = Path()
        let y = snapshot.dangerY + snapshot.radius
        line.move(to: CGPoint(x: 16, y: y))
        line.addLine(to: CGPoint(x: size.width - 16, y: y))
        let color = Color.white.mix(with: Color(red: 0.95, green: 0.25, blue: 0.3), by: snapshot.dangerLevel)
        ctx.stroke(line, with: .color(color.opacity(0.3 + 0.4 * snapshot.dangerLevel)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
    }

    private static func color(_ index: Int) -> Color {
        PebbleGameTuning.colors[index % PebbleGameTuning.colors.count]
    }

    /// Pedrinha colorida no estilo das pedrinhas do rim (ver `PebbleDrawing`).
    private static func drawStone(_ stone: PebbleGameSnapshot.Pebble, radius: CGFloat, in context: inout GraphicsContext) {
        var ctx = context
        ctx.opacity = stone.alpha
        let r = radius * stone.scale * 0.98
        PebbleDrawing.draw(center: stone.position, radiusX: r, radiusY: r,
                           tint: color(stone.colorIndex).mix(with: PebbleDrawing.stoneBrown, by: 0.12),
                           seed: stone.seed, in: &ctx)
    }

    /// Canhão: um bocal que gira com a mira, a pedrinha carregada no meio e a próxima ao lado,
    /// com bolinhas embaixo contando os tiros que faltam até descer uma linha nova.
    private static func drawCannon(_ snapshot: PebbleGameSnapshot, in context: inout GraphicsContext) {
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

        let count = PebbleGameTuning.missesBeforeNewRow
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
