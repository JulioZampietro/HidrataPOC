import SwiftUI

/// Todos os cosméticos equipados, empilhados no fundo do recipiente da Home (atrás do
/// mascote e dentro do conteúdo da água, então ondulam junto com a refração).
/// A ordem de desenho vem de `Cosmetic.layerOrder`, não da ordem da aba.
struct AquariumDecorationsView: View {
    let streak: Int
    /// Nível de água do dia (0…1) — o que boia fica abaixo da superfície.
    let waterLevel: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Cosmetic.allCases.sorted { $0.layerOrder < $1.layerOrder }) { item in
                CosmeticLayer(item: item, streak: streak, waterLevel: waterLevel)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Uma camada: lê se o item está equipado e só desenha se também estiver
/// desbloqueado — se a streak zerar, some mesmo que continue equipado.
private struct CosmeticLayer: View {
    let item: Cosmetic
    let streak: Int
    let waterLevel: Double

    @AppStorage private var isEquipped: Bool

    init(item: Cosmetic, streak: Int, waterLevel: Double) {
        self.item = item
        self.streak = streak
        self.waterLevel = waterLevel
        _isEquipped = AppStorage(wrappedValue: false, item.storageKey)
    }

    private var shows: Bool { isEquipped && item.isUnlocked(streak: streak) }

    var body: some View {
        ZStack(alignment: .bottom) {
            if shows {
                decoration
                    .transition(item.sitsOnFloor
                        ? .move(edge: .bottom).combined(with: .opacity)
                        : .opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shows)
    }

    @ViewBuilder
    private var decoration: some View {
        switch item {
        case .grass: GrassView().frame(height: 44)
        case .kidneys: KidneyCheerView()
        case .straw: StrawView()
        case .droplets: DropletFriendsView(waterLevel: waterLevel)
        case .fizz: FizzView(waterLevel: waterLevel)
        case .ice, .lemon, .mint, .cucumber, .berries:
            FloatingInfusionView(kind: item, waterLevel: waterLevel)
        }
    }
}

/// Topo aproximado da água no conteúdo do recipiente. O recipiente real pode se
/// estender sob a status bar (fica mais alto que o conteúdo), então isso fica um
/// pouco abaixo da superfície de verdade — o que mantém o que boia submerso.
private func waterTop(height: CGFloat, level: Double) -> CGFloat {
    height * (1 - CGFloat(min(max(level, 0), 1)))
}

/// 0 → 1 conforme a faixa de água disponível passa de `minimum` a `minimum + 40` pt:
/// com pouca água o que boia some suavemente em vez de ficar no ar.
private func floatOpacity(band: CGFloat, minimum: CGFloat) -> Double {
    Double(min(max((band - minimum) / 40, 0), 1))
}

private let waterBlue = Color(red: 0.32, green: 0.64, blue: 0.98)

// MARK: - Água saborizada (o que boia)

/// Pedaços que boiam na água, como numa jarra de água saborizada: cada `kind`
/// (gelo, limão, hortelã, pepino, frutas vermelhas) tem o seu conjunto de peças,
/// em posições e ritmos próprios pra não se sobreporem quando vários estão ligados.
struct FloatingInfusionView: View {
    let kind: Cosmetic
    let waterLevel: Double

    /// `depth`: 0 = colado na superfície, 1 = perto do fundo.
    private struct Piece { let x: CGFloat; let depth: CGFloat; let size: CGFloat; let phase: Double }

    private var pieces: [Piece] {
        switch kind {
        case .ice: [Piece(x: 0.22, depth: 0.02, size: 15, phase: 0), Piece(x: 0.50, depth: 0.0, size: 12, phase: 2.2), Piece(x: 0.80, depth: 0.03, size: 14, phase: 4.1)]
        case .lemon: [Piece(x: 0.42, depth: 0.70, size: 14, phase: 1.0), Piece(x: 0.68, depth: 0.15, size: 12, phase: 3.0), Piece(x: 0.90, depth: 0.55, size: 13, phase: 5.0)]
        case .mint: [Piece(x: 0.33, depth: 0.10, size: 11, phase: 0.5), Piece(x: 0.60, depth: 0.42, size: 10, phase: 2.7), Piece(x: 0.08, depth: 0.62, size: 9, phase: 4.4), Piece(x: 0.86, depth: 0.25, size: 10, phase: 1.6)]
        case .cucumber: [Piece(x: 0.26, depth: 0.50, size: 12, phase: 0.9), Piece(x: 0.76, depth: 0.38, size: 11, phase: 3.6)]
        case .berries: [Piece(x: 0.40, depth: 0.28, size: 9, phase: 0.3), Piece(x: 0.18, depth: 0.75, size: 8, phase: 2.0), Piece(x: 0.82, depth: 0.72, size: 9, phase: 3.3), Piece(x: 0.56, depth: 0.08, size: 6, phase: 4.8)]
        default: []
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 14
                let bottom = size.height - 40
                let band = max(bottom - top, 0)
                context.opacity = floatOpacity(band: band, minimum: 0)
                guard context.opacity > 0 else { return }
                for (i, piece) in pieces.enumerated() {
                    let bob = CGFloat(sin(t * 0.9 + piece.phase)) * 4
                    let drift = CGFloat(sin(t * 0.25 + piece.phase)) * 10
                    let center = CGPoint(x: size.width * piece.x + drift, y: top + band * piece.depth + bob)
                    var ctx = context
                    ctx.translateBy(x: center.x, y: center.y)
                    ctx.rotate(by: .radians(sin(t * 0.4 + piece.phase) * 0.5 + Double(i)))
                    draw(in: &ctx, size: piece.size, index: i)
                }
            }
        }
    }

    private func draw(in ctx: inout GraphicsContext, size r: CGFloat, index: Int) {
        switch kind {
        case .ice: drawIce(in: &ctx, r: r)
        case .lemon: drawCitrusSlice(in: &ctx, r: r,
                                     rind: Color(red: 0.98, green: 0.84, blue: 0.15),
                                     flesh: Color(red: 1.0, green: 0.95, blue: 0.55))
        case .mint: drawLeaf(in: &ctx, r: r)
        case .cucumber: drawCucumber(in: &ctx, r: r)
        case .berries: index.isMultiple(of: 2) ? drawStrawberry(in: &ctx, r: r) : drawBlueberry(in: &ctx, r: r)
        default: break
        }
    }

    private func drawIce(in ctx: inout GraphicsContext, r: CGFloat) {
        let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        let cube = Path(roundedRect: rect, cornerRadius: r * 0.35)
        ctx.fill(cube, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.85), Color(red: 0.80, green: 0.93, blue: 1.0).opacity(0.6)]),
            startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)
        ))
        ctx.stroke(cube, with: .color(.white), lineWidth: 1.2)
        var shine = Path()
        shine.move(to: CGPoint(x: -r * 0.55, y: r * 0.2))
        shine.addLine(to: CGPoint(x: -r * 0.55, y: -r * 0.55))
        shine.addLine(to: CGPoint(x: r * 0.2, y: -r * 0.55))
        ctx.stroke(shine, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawCitrusSlice(in ctx: inout GraphicsContext, r: CGFloat, rind: Color, flesh: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(rind))
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.84, y: -r * 0.84, width: r * 1.68, height: r * 1.68)), with: .color(.white.opacity(0.9)))
        for i in 0..<8 {
            let a0 = Double(i) * .pi / 4 + 0.08, a1 = Double(i + 1) * .pi / 4 - 0.08
            var wedge = Path()
            wedge.move(to: .zero)
            wedge.addArc(center: .zero, radius: r * 0.74, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(flesh))
        }
    }

    private func drawLeaf(in ctx: inout GraphicsContext, r: CGFloat) {
        var leaf = Path()
        leaf.move(to: CGPoint(x: -r, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: -r * 1.1))
        leaf.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: 0, y: r * 1.1))
        ctx.fill(leaf, with: .color(Color(red: 0.25, green: 0.72, blue: 0.40)))
        var vein = Path()
        vein.move(to: CGPoint(x: -r * 1.25, y: 0))
        vein.addLine(to: CGPoint(x: r * 0.8, y: 0))
        for x in [-0.4, 0.0, 0.4] {
            vein.move(to: CGPoint(x: r * x, y: 0))
            vein.addLine(to: CGPoint(x: r * (x + 0.3), y: -r * 0.35))
            vein.move(to: CGPoint(x: r * x, y: 0))
            vein.addLine(to: CGPoint(x: r * (x + 0.3), y: r * 0.35))
        }
        ctx.stroke(vein, with: .color(Color(red: 0.14, green: 0.52, blue: 0.27)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private func drawCucumber(in ctx: inout GraphicsContext, r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.16, green: 0.45, blue: 0.20)))
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.85, y: -r * 0.85, width: r * 1.7, height: r * 1.7)), with: .color(Color(red: 0.78, green: 0.92, blue: 0.62)))
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.5, y: -r * 0.5, width: r, height: r)), with: .color(Color(red: 0.88, green: 0.96, blue: 0.74)))
        for i in 0..<6 {
            let a = Double(i) * .pi / 3
            let p = CGPoint(x: cos(a) * r * 0.32, y: sin(a) * r * 0.32)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.8, width: 2.4, height: 3.6)), with: .color(Color(red: 0.95, green: 0.98, blue: 0.86)))
        }
    }

    private func drawStrawberry(in ctx: inout GraphicsContext, r: CGFloat) {
        var berry = Path()
        berry.move(to: CGPoint(x: 0, y: r * 1.2))
        berry.addCurve(to: CGPoint(x: 0, y: -r * 0.6), control1: CGPoint(x: -r * 1.5, y: r * 0.2), control2: CGPoint(x: -r * 1.0, y: -r * 0.9))
        berry.addCurve(to: CGPoint(x: 0, y: r * 1.2), control1: CGPoint(x: r * 1.0, y: -r * 0.9), control2: CGPoint(x: r * 1.5, y: r * 0.2))
        ctx.fill(berry, with: .color(Color(red: 0.92, green: 0.22, blue: 0.28)))
        for (x, y) in [(-0.4, -0.1), (0.35, -0.05), (0.0, 0.35), (-0.25, 0.6), (0.3, 0.55)] {
            ctx.fill(Path(ellipseIn: CGRect(x: r * x - 0.8, y: r * y - 1.1, width: 1.6, height: 2.2)), with: .color(Color(red: 1.0, green: 0.88, blue: 0.45)))
        }
        var crown = Path()
        for side in [-1.0, 0.0, 1.0] {
            crown.move(to: CGPoint(x: 0, y: -r * 0.6))
            crown.addLine(to: CGPoint(x: r * 0.6 * side, y: -r * (side == 0 ? 1.2 : 0.95)))
        }
        ctx.stroke(crown, with: .color(Color(red: 0.25, green: 0.65, blue: 0.30)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawBlueberry(in ctx: inout GraphicsContext, r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.28, green: 0.32, blue: 0.68)))
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.65, width: r * 0.55, height: r * 0.45)), with: .color(.white.opacity(0.35)))
        var star = Path()
        for i in 0..<5 {
            let a = Double(i) * 2 * .pi / 5
            star.move(to: CGPoint(x: 0, y: -r * 0.55))
            star.addLine(to: CGPoint(x: cos(a) * r * 0.3, y: -r * 0.55 + sin(a) * r * 0.3))
        }
        ctx.stroke(star, with: .color(Color(red: 0.16, green: 0.18, blue: 0.40)), lineWidth: 1)
    }
}

// MARK: - Na água

/// Água com gás: muitas bolhinhas pequenas subindo rápido de todo o fundo.
struct FizzView: View {
    let waterLevel: Double

    private let bubbles: [(x: CGFloat, period: Double, phase: Double, r: CGFloat)] = {
        var rng = SeededGenerator(seed: 2026)
        return (0..<34).map { _ in
            (CGFloat.random(in: 0.04...0.96, using: &rng), Double.random(in: 1.8...3.4, using: &rng),
             Double.random(in: 0...1, using: &rng), CGFloat.random(in: 1...2.6, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 6
                let start = size.height - 6
                guard start - top > 16 else { return }
                for (i, bubble) in bubbles.enumerated() {
                    let raw = t / bubble.period + bubble.phase
                    let p = raw - floor(raw)
                    let y = start - (start - top) * CGFloat(p)
                    let x = size.width * bubble.x + CGFloat(sin(p * 12 + Double(i))) * 2.5
                    let fade = p > 0.9 ? (1 - p) / 0.1 : min(1, p / 0.08)
                    let r = bubble.r * (0.8 + 0.4 * CGFloat(p))
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(0.85 * fade)))
                }
            }
        }
    }
}

/// Gotinhas d'água sorridentes — as aliadas contra a pedra — passeando pela água.
struct DropletFriendsView: View {
    let waterLevel: Double

    private struct Friend { let x: CGFloat; let depth: CGFloat; let size: CGFloat; let phase: Double }

    private let friends: [Friend] = [
        Friend(x: 0.14, depth: 0.25, size: 13, phase: 0),
        Friend(x: 0.86, depth: 0.45, size: 11, phase: 2.1),
        Friend(x: 0.30, depth: 0.70, size: 9, phase: 4.0),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 26
                let bottom = size.height - 56
                let band = bottom - top
                context.opacity = floatOpacity(band: band, minimum: 0)
                guard context.opacity > 0 else { return }
                for friend in friends {
                    let x = size.width * friend.x + CGFloat(sin(t * 0.5 + friend.phase)) * 14
                    let y = top + max(band, 0) * friend.depth + CGFloat(sin(t * 1.6 + friend.phase)) * 5
                    let blink = (t + friend.phase).truncatingRemainder(dividingBy: 4) < 0.15
                    drawDroplet(in: &context, at: CGPoint(x: x, y: y), r: friend.size,
                                tilt: sin(t * 1.6 + friend.phase) * 0.15, blinking: blink)
                }
            }
        }
    }

    private func drawDroplet(in context: inout GraphicsContext, at center: CGPoint, r: CGFloat, tilt: Double, blinking: Bool) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .radians(tilt))

        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -r * 1.6))
        drop.addCurve(to: CGPoint(x: 0, y: r), control1: CGPoint(x: r * 0.4, y: -r * 0.8), control2: CGPoint(x: r * 1.4, y: r))
        drop.addCurve(to: CGPoint(x: 0, y: -r * 1.6), control1: CGPoint(x: -r * 1.4, y: r), control2: CGPoint(x: -r * 0.4, y: -r * 0.8))
        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 1.0), waterBlue]),
            startPoint: CGPoint(x: 0, y: -r * 1.6), endPoint: CGPoint(x: 0, y: r)
        ))
        ctx.stroke(drop, with: .color(.white.opacity(0.7)), lineWidth: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.55, width: r * 0.3, height: r * 0.45)), with: .color(.white.opacity(0.75)))

        let eyeY = r * 0.05
        for dx in [-r * 0.3, r * 0.3] {
            if blinking {
                var lid = Path()
                lid.move(to: CGPoint(x: dx - 1.8, y: eyeY))
                lid.addLine(to: CGPoint(x: dx + 1.8, y: eyeY))
                ctx.stroke(lid, with: .color(Color(red: 0.08, green: 0.20, blue: 0.40)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: dx - 1.6, y: eyeY - 2, width: 3.2, height: 4)), with: .color(Color(red: 0.08, green: 0.20, blue: 0.40)))
            }
        }
        var smile = Path()
        smile.addArc(center: CGPoint(x: 0, y: r * 0.3), radius: r * 0.25, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(smile, with: .color(Color(red: 0.08, green: 0.20, blue: 0.40)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }
}

/// Canudinho listrado entrando pela borda de cima, do lado direito — acima da água
/// ele aparece reto, abaixo a refração entorta, como num copo de verdade.
struct StrawView: View {
    var body: some View {
        Canvas { context, size in
            var straw = Path()
            straw.move(to: CGPoint(x: size.width + 6, y: size.height * 0.10))
            straw.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.12))
            straw.addQuadCurve(to: CGPoint(x: size.width * 0.91, y: size.height * 0.18), control: CGPoint(x: size.width * 0.92, y: size.height * 0.12))
            straw.addLine(to: CGPoint(x: size.width * 0.80, y: size.height * 0.80))
            let style = StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            context.stroke(straw, with: .color(.white), style: style)
            context.stroke(straw, with: .color(Color(red: 0.95, green: 0.30, blue: 0.40)),
                           style: StrokeStyle(lineWidth: 10, lineCap: .butt, lineJoin: .round, dash: [7, 7]))
            context.stroke(straw, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - No fundo

/// Os dois rins nos cantos de baixo, pulando e torcendo pra você beber água.
struct KidneyCheerView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for (x, mirrored, phase) in [(size.width * 0.11, false, 0.0), (size.width * 0.89, true, 0.45)] {
                    // Pulinho: sobe rápido, cai devagar, e fica parado um tempinho.
                    let cycle = (t * 0.9 + phase).truncatingRemainder(dividingBy: 1)
                    let hop = cycle < 0.35 ? sin(cycle / 0.35 * .pi) : 0
                    let squash = cycle > 0.35 && cycle < 0.45 ? 0.08 * sin((cycle - 0.35) / 0.1 * .pi) : 0
                    drawKidney(in: &context, at: CGPoint(x: x, y: size.height - 26 - CGFloat(hop) * 10),
                               mirrored: mirrored, squash: squash, armsUp: hop > 0.3)
                }
            }
        }
    }

    private func drawKidney(in context: inout GraphicsContext, at center: CGPoint, mirrored: Bool, squash: Double, armsUp: Bool) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: (mirrored ? -1 : 1) * CGFloat(1 + squash), y: CGFloat(1 - squash))

        let skin = Color(red: 0.90, green: 0.45, blue: 0.47)
        let outline = Color(red: 0.62, green: 0.24, blue: 0.27)
        let ink = Color(red: 0.32, green: 0.12, blue: 0.14)

        // Bracinhos (atrás do corpo).
        var arms = Path()
        let armY: CGFloat = armsUp ? -20 : -2
        arms.move(to: CGPoint(x: -12, y: -4)); arms.addLine(to: CGPoint(x: -21, y: armY))
        arms.move(to: CGPoint(x: 10, y: -4)); arms.addLine(to: CGPoint(x: 19, y: armY))
        ctx.stroke(arms, with: .color(outline), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        // Corpo em feijão: a reentrância fica do lado de dentro (virado pro centro).
        var bean = Path()
        bean.move(to: CGPoint(x: 2, y: -18))
        bean.addCurve(to: CGPoint(x: 2, y: 18), control1: CGPoint(x: -26, y: -24), control2: CGPoint(x: -26, y: 24))
        bean.addCurve(to: CGPoint(x: 10, y: 4), control1: CGPoint(x: 12, y: 18), control2: CGPoint(x: 14, y: 10))
        bean.addQuadCurve(to: CGPoint(x: 10, y: -4), control: CGPoint(x: 5, y: 0))
        bean.addCurve(to: CGPoint(x: 2, y: -18), control1: CGPoint(x: 14, y: -10), control2: CGPoint(x: 12, y: -18))
        bean.closeSubpath()
        ctx.fill(bean, with: .linearGradient(
            Gradient(colors: [Color(red: 0.97, green: 0.60, blue: 0.60), skin]),
            startPoint: CGPoint(x: -10, y: -18), endPoint: CGPoint(x: 6, y: 18)
        ))
        ctx.stroke(bean, with: .color(outline), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: -14, y: -13, width: 5, height: 7)), with: .color(.white.opacity(0.45)))

        // Rosto (olhos fechadinhos de alegria + sorrisão + bochechas).
        var face = Path()
        for dx in [-8.0, 0.0] {
            face.addArc(center: CGPoint(x: dx, y: -4), radius: 2.2, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        }
        ctx.stroke(face, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: -8, y: 2))
        mouth.addQuadCurve(to: CGPoint(x: 0, y: 2), control: CGPoint(x: -4, y: 8))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(ink))
        for dx in [-12.0, 3.5] {
            ctx.fill(Path(ellipseIn: CGRect(x: dx, y: 0, width: 4, height: 2.5)), with: .color(Color(red: 1.0, green: 0.42, blue: 0.48).opacity(0.7)))
        }
    }
}

#Preview {
    RoundedRectangle(cornerRadius: 32)
        .fill(Color(red: 0.75, green: 0.88, blue: 1.0))
        .overlay { AquariumDecorationsView(streak: 5, waterLevel: 0.7) }
        .frame(height: 360)
        .padding()
        .onAppear {
            for item in Cosmetic.allCases { UserDefaults.standard.set(true, forKey: item.storageKey) }
        }
}
