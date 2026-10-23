import SwiftUI

/// Desenha o Quebra-Pedras (`SliceGameSimulation`) dentro do recipiente de água, no mesmo lugar
/// dos outros minijogos — então passa pela refração do shader. Recebe toque: deslizar o dedo
/// pela água corta as pedras.
struct SliceGameView: View {
    let simulation: SliceGameSimulation
    let water: WaterMotion

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                // Avança a simulação uma vez por frame (mesmo padrão de `JumpGameView`).
                let _ = simulation.advance(to: context.date, size: geo.size, water: water)
                let snapshot = simulation.snapshot()
                Canvas { ctx, size in
                    Self.draw(snapshot, size: size, in: &ctx)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { simulation.swipe(to: $0.location) }
                .onEnded { _ in simulation.endSwipe() }
        )
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    private static func draw(_ snapshot: SliceGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        for half in snapshot.halves { drawHalf(half, in: &ctx) }
        for thing in snapshot.things {
            if thing.isKidney { drawKidney(thing, in: &ctx) } else { drawStone(thing, in: &ctx) }
        }
        for particle in snapshot.particles { drawParticle(particle, in: &ctx) }
        drawTrail(snapshot.trail, in: &ctx)
        drawHUD(snapshot, size: size, in: &ctx)
    }

    private static func tint(_ index: Int) -> Color {
        SliceGameTuning.colors[index % SliceGameTuning.colors.count].mix(with: PebbleDrawing.stoneBrown, by: 0.12)
    }

    private static func drawStone(_ thing: SliceGameSnapshot.Thing, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: thing.position.x, y: thing.position.y)
        ctx.rotate(by: .radians(Double(thing.angle)))
        PebbleDrawing.draw(center: .zero, radiusX: thing.radius, radiusY: thing.radius, tint: tint(thing.colorIndex),
                           seed: thing.seed, castsShadow: true, in: &ctx)
    }

    /// Metade da pedra: a pedra inteira, recortada pelo lado `side` da linha do corte.
    private static func drawHalf(_ half: SliceGameSnapshot.Half, in context: inout GraphicsContext) {
        var ctx = context
        ctx.opacity = half.alpha
        ctx.translateBy(x: half.position.x, y: half.position.y)
        ctx.rotate(by: .radians(Double(half.angle)))
        var clipCtx = ctx
        clipCtx.rotate(by: .radians(Double(half.cutAngle)))
        let r = half.radius * 1.3
        clipCtx.clip(to: Path(CGRect(x: -r, y: half.side > 0 ? 0 : -r, width: r * 2, height: r)))
        clipCtx.rotate(by: .radians(Double(-half.cutAngle)))
        PebbleDrawing.draw(center: .zero, radiusX: half.radius, radiusY: half.radius, tint: tint(half.colorIndex),
                           seed: half.seed, in: &clipCtx)
    }

    /// O rim (o feijão de `KidneyCheerView.beanPath`), girando, com cara de assustado: é ele que
    /// o jogador tem que deixar passar.
    private static func drawKidney(_ thing: SliceGameSnapshot.Thing, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: thing.position.x, y: thing.position.y)
        ctx.rotate(by: .radians(Double(thing.angle)))
        let scale = thing.radius * 2 / 36
        ctx.scaleBy(x: scale, y: scale)
        let bean = KidneyCheerView.beanPath
        let outline = Color(red: 0.62, green: 0.24, blue: 0.27)
        let ink = Color(red: 0.32, green: 0.12, blue: 0.14)
        ctx.fill(bean.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.15)))
        ctx.fill(bean, with: .linearGradient(
            Gradient(colors: [Color(red: 0.97, green: 0.60, blue: 0.60), Color(red: 0.90, green: 0.45, blue: 0.47)]),
            startPoint: CGPoint(x: -10, y: -18), endPoint: CGPoint(x: 6, y: 18)
        ))
        ctx.stroke(bean, with: .color(outline), lineWidth: 1.8)
        ctx.fill(Path(ellipseIn: CGRect(x: -14, y: -13, width: 5, height: 7)), with: .color(.white.opacity(0.45)))
        // Olhos arregalados e boquinha em "o".
        for dx: CGFloat in [-9, -1] {
            ctx.fill(Path(ellipseIn: CGRect(x: dx - 3, y: -9, width: 6, height: 7)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: dx - 1.3, y: -7, width: 2.6, height: 3)), with: .color(ink))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: -7, y: 2, width: 4, height: 5)), with: .color(ink))
    }

    private static func drawParticle(_ particle: SliceGameSnapshot.Particle, in context: inout GraphicsContext) {
        var ctx = context
        ctx.opacity = particle.alpha
        let r = particle.radius
        let rect = CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)
        if particle.isKidney {
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.92, green: 0.48, blue: 0.50)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.62, green: 0.24, blue: 0.27)), lineWidth: 0.6)
        } else {
            ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.16, green: 0.52, blue: 0.95)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: 0.8)
        }
    }

    /// Rastro do dedo: fino no começo, grosso na ponta, branco com brilho azul.
    private static func drawTrail(_ trail: [CGPoint], in ctx: inout GraphicsContext) {
        guard trail.count > 1 else { return }
        for i in 1..<trail.count {
            let progress = CGFloat(i) / CGFloat(trail.count - 1)
            var segment = Path()
            segment.move(to: trail[i - 1])
            segment.addLine(to: trail[i])
            ctx.stroke(segment, with: .color(Color(red: 0.55, green: 0.80, blue: 1.0).opacity(0.5 * progress)),
                       style: StrokeStyle(lineWidth: 2 + 9 * progress, lineCap: .round))
            ctx.stroke(segment, with: .color(.white.opacity(0.95 * progress)),
                       style: StrokeStyle(lineWidth: 1 + 4 * progress, lineCap: .round))
        }
    }

    /// Pontos e pedras perdidas no meio do cabeçalho (entre a seta de voltar e o botão de
    /// minijogos), combos subindo e os avisos de cada momento da partida.
    private static func drawHUD(_ snapshot: SliceGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 24).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 20)
        )
        // Pedras que caíram inteiras: X vermelho; as que ainda podem cair: X apagado.
        for i in 0..<SliceGameTuning.strikes {
            let x = size.width / 2 + (CGFloat(i) - CGFloat(SliceGameTuning.strikes - 1) / 2) * 18
            var mark = Path()
            mark.move(to: CGPoint(x: x - 5, y: 37)); mark.addLine(to: CGPoint(x: x + 5, y: 47))
            mark.move(to: CGPoint(x: x + 5, y: 37)); mark.addLine(to: CGPoint(x: x - 5, y: 47))
            let isUsed = i < snapshot.strikes
            ctx.stroke(mark, with: .color(isUsed ? Color(red: 0.92, green: 0.25, blue: 0.3) : .white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        for popup in snapshot.popups {
            var popupCtx = textCtx
            popupCtx.opacity = popup.alpha
            popupCtx.draw(
                Text(popup.text)
                    .font(.custom("Nunito", size: 22).weight(.black))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3)),
                at: popup.position
            )
        }
        let message: String? = switch snapshot.phase {
        case .gameOver: "Fim de jogo"
        case .ready, .playing: nil
        }
        if let message {
            textCtx.draw(
                Text(message)
                    .font(.custom("Nunito", size: 22).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: size.height * 0.45)
            )
        }
        if snapshot.phase == .ready {
            GameStartPrompt.draw(hint: "Deslize pra cortar as pedras, não o rim", centerY: size.height * 0.45, size: size, in: &ctx)
        }
    }
}

/// Cartão ao lado do recorde nos jogos controlados só pelo dedo no aquário (Quebra-Pedras,
/// Cobrinha e Gota Surfista): lembra como se joga, no lugar dos botões.
struct GameHintCard: View {
    let title: String
    let subtitle: String
    let height: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.appAccentText)
                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appSecondary)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle).")
    }
}
