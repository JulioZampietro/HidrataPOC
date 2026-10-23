import SwiftUI

/// Desenha o jogo das argolas (`RingGameSimulation`) dentro do recipiente de água. Fica
/// no conteúdo do `.waterContainer`, então passa pela mesma refração do shader — as
/// argolas parecem mergulhadas; as pedrinhas do mascote continuam por cima, no fundo.
struct RingGameView: View {
    let simulation: RingGameSimulation
    let water: WaterMotion

    private static let ringColors: [Color] = [
        Color(red: 0.93, green: 0.26, blue: 0.28),
        Color(red: 1.00, green: 0.62, blue: 0.16),
        Color(red: 1.00, green: 0.86, blue: 0.22),
        Color(red: 0.25, green: 0.78, blue: 0.42),
        Color(red: 0.95, green: 0.42, blue: 0.72),
        Color(red: 0.62, green: 0.42, blue: 0.92)
    ]

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `WaterFillView`).
                let _ = simulation.advance(to: context.date, size: geo.size, down: water.down, water: water)
                let snapshot = simulation.snapshot()
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    MiniGameBackdrop.draw(time: time, size: size, in: &ctx)
                    Self.draw(snapshot, in: &ctx)
                    GameConfetti.draw(snapshot.confetti, colors: Self.ringColors, in: &ctx)
                    if snapshot.isReady {
                        if snapshot.isCelebrating {
                            GameStartPrompt.draw(title: "Parabéns!", action: "Toque pra recomeçar",
                                                 hint: "Você completou todas as argolas",
                                                 centerY: size.height * 0.4, size: size, in: &ctx)
                        } else {
                            GameStartPrompt.draw(hint: "Use os jatos pra encaixar as argolas nos pinos",
                                                 centerY: size.height * 0.4, size: size, in: &ctx)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { simulation.begin() }
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static func draw(_ snapshot: RingGameSnapshot, in ctx: inout GraphicsContext) {
        drawJets(snapshot, in: &ctx)
        for post in snapshot.posts { drawPost(post, in: &ctx) }

        // Livres primeiro (na frente dos pinos); depois, as enfiadas com o pino passando por
        // dentro do furo: todas as metades de trás, o pino por cima delas e só então as
        // metades da frente (senão o pino redesenhado cobre a frente das argolas de cima).
        for ring in snapshot.rings where !ring.isHooked { drawRing(ring, part: .whole, in: &ctx) }
        let hooked = snapshot.rings.filter(\.isHooked).sorted(by: { $0.slot > $1.slot })
        for ring in hooked { drawRing(ring, part: .back, in: &ctx) }
        var hookedPosts = Set<Int>()
        for ring in hooked {
            if let index = snapshot.posts.indices.min(by: { abs(snapshot.posts[$0].midX - ring.position.x) < abs(snapshot.posts[$1].midX - ring.position.x) }) {
                hookedPosts.insert(index)
            }
        }
        for index in hookedPosts.sorted() { drawPost(snapshot.posts[index], in: &ctx) }
        for ring in hooked { drawRing(ring, part: .front, in: &ctx) }

        for bubble in snapshot.bubbles {
            let rect = CGRect(x: bubble.position.x - bubble.radius, y: bubble.position.y - bubble.radius,
                              width: bubble.radius * 2, height: bubble.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(bubble.alpha)))
        }
    }

    private static func drawJets(_ snapshot: RingGameSnapshot, in ctx: inout GraphicsContext) {
        for (index, nozzle) in snapshot.nozzles.enumerated() {
            // Rajada central: um clarão redondo em volta do ponto de origem, sem bico.
            if RingGameSide(rawValue: index) == .center {
                if snapshot.jetsOpen[index] {
                    let radius = CGFloat(RingGameTuning.burstRadius)
                    let center = snapshot.burstOrigin
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(0.3), .white.opacity(0)]),
                                              center: center, startRadius: 0, endRadius: radius)
                    )
                }
                continue
            }
            if snapshot.jetsOpen[index] {
                let inward: CGFloat = index == 0 ? 1 : (index == 1 ? -1 : 0)
                var column = Path()
                column.move(to: CGPoint(x: nozzle.x - 9, y: nozzle.y))
                column.addLine(to: CGPoint(x: nozzle.x + inward * snapshot.jetHeight * CGFloat(RingGameTuning.jetInwardTilt) - 22, y: nozzle.y - snapshot.jetHeight))
                column.addLine(to: CGPoint(x: nozzle.x + inward * snapshot.jetHeight * CGFloat(RingGameTuning.jetInwardTilt) + 22, y: nozzle.y - snapshot.jetHeight))
                column.addLine(to: CGPoint(x: nozzle.x + 9, y: nozzle.y))
                column.closeSubpath()
                ctx.fill(column, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.28), .white.opacity(0)]),
                    startPoint: nozzle, endPoint: CGPoint(x: nozzle.x, y: nozzle.y - snapshot.jetHeight)
                ))
            }
            let bico = CGRect(x: nozzle.x - 10, y: nozzle.y - 2, width: 20, height: 8)
            ctx.fill(Path(roundedRect: bico, cornerRadius: 3), with: .color(Color(red: 0.55, green: 0.60, blue: 0.68)))
        }
    }

    private static func drawPost(_ post: CGRect, in ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: post, cornerRadius: post.width / 2), with: .linearGradient(
            Gradient(colors: [Color(white: 0.98), Color(white: 0.72)]),
            startPoint: CGPoint(x: post.minX, y: post.midY), endPoint: CGPoint(x: post.maxX, y: post.midY)
        ))
        let cap = CGRect(x: post.minX - 1.5, y: post.minY - 1, width: post.width + 3, height: post.width + 3)
        ctx.fill(Path(ellipseIn: cap), with: .color(Color(white: 0.95)))

        // Esfera na base: é onde as argolas param.
        let radius = CGFloat(RingGameTuning.stopperRadius)
        let center = CGPoint(x: post.midX, y: post.maxY + 5)
        let ball = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: ball), with: .radialGradient(
            Gradient(colors: [Color(white: 0.98), Color(white: 0.66)]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35), startRadius: 0, endRadius: radius * 1.4
        ))
    }

    private enum RingPart { case whole, back, front }

    private static func drawRing(_ ring: RingGameSnapshot.Ring, part: RingPart, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: ring.position.x, y: ring.position.y)
        ctx.rotate(by: .radians(ring.tilt))

        let rx = ring.radius
        let ry = ring.radius * ring.openness
        let thickness = (ring.radius - ring.hole) * 0.62
        // `back` = metade de cima (lado de trás da argola, escondido pelo pino);
        // `front` = metade de baixo.
        switch part {
        case .whole: break
        case .back: ctx.clip(to: Path(CGRect(x: -rx - 4, y: -ry - 4, width: rx * 2 + 8, height: ry + 4)))
        case .front: ctx.clip(to: Path(CGRect(x: -rx - 4, y: 0, width: rx * 2 + 8, height: ry + 4)))
        }

        let band = Path(ellipseIn: CGRect(x: -rx + thickness / 2, y: -ry + thickness / 2,
                                          width: (rx - thickness / 2) * 2, height: (ry - thickness / 2) * 2))
        let color = ringColors[ring.colorIndex % ringColors.count]
        ctx.stroke(band, with: .color(.black.opacity(0.28)), lineWidth: thickness + 2)
        ctx.stroke(band, with: .color(color), lineWidth: thickness)
        ctx.stroke(band, with: .color(.white.opacity(0.35)), lineWidth: max(1, thickness * 0.25))
    }
}
