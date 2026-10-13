import SwiftUI

/// Todos os cosméticos equipados, empilhados no fundo do aquário da Home (atrás do
/// mascote e dentro do conteúdo da água, então ondulam junto com a refração).
/// A ordem de desenho vem de `Cosmetic.layerOrder`, não da ordem da aba.
struct AquariumDecorationsView: View {
    let streak: Int
    /// Nível de água do dia (0…1) — os bichinhos que nadam ficam abaixo da superfície.
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
        case .shells: ShellsView()
        case .seaweed: SeaweedView()
        case .coral: CoralView()
        case .chest: TreasureChestView()
        case .bubbles: BubblesView(waterLevel: waterLevel)
        case .fish: FishSchoolView(waterLevel: waterLevel)
        case .jellyfish: JellyfishView(waterLevel: waterLevel)
        case .sunRays: SunRaysView()
        case .plankton: PlanktonView(waterLevel: waterLevel)
        }
    }
}

/// Topo aproximado da água no conteúdo do recipiente. O recipiente real pode se
/// estender sob a status bar (fica mais alto que o conteúdo), então isso fica um
/// pouco abaixo da superfície de verdade — o que mantém os bichos submersos.
private func waterTop(height: CGFloat, level: Double) -> CGFloat {
    height * (1 - CGFloat(min(max(level, 0), 1)))
}

/// 0 → 1 conforme a faixa de água disponível passa de `minimum` a `minimum + 40` pt:
/// com pouca água os bichos que nadam somem suavemente em vez de flutuar no ar.
private func swimOpacity(band: CGFloat, minimum: CGFloat) -> Double {
    Double(min(max((band - minimum) / 40, 0), 1))
}

// MARK: - Fundo

/// Conchinhas espalhadas no chão: uma vieira rosada, uma estrela-do-mar e um
/// caramujo em espiral.
struct ShellsView: View {
    var body: some View {
        Canvas { context, size in
            let floor = size.height - 8
            drawScallop(in: &context, at: CGPoint(x: size.width * 0.36, y: floor), radius: 13)
            drawStarfish(in: &context, at: CGPoint(x: size.width * 0.63, y: floor - 9), radius: 12)
            drawSpiral(in: &context, at: CGPoint(x: size.width * 0.52, y: floor - 4), radius: 6)
        }
    }

    private func drawScallop(in context: inout GraphicsContext, at base: CGPoint, radius: CGFloat) {
        var fan = Path()
        fan.move(to: base)
        fan.addArc(center: base, radius: radius, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
        fan.closeSubpath()
        context.fill(fan, with: .linearGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.80), Color(red: 0.93, green: 0.52, blue: 0.60)]),
            startPoint: CGPoint(x: base.x, y: base.y - radius), endPoint: base
        ))
        var ridges = Path()
        for i in 1..<6 {
            let angle = Angle.degrees(195 + Double(i) * 25).radians
            ridges.move(to: base)
            ridges.addLine(to: CGPoint(x: base.x + cos(angle) * radius, y: base.y + sin(angle) * radius))
        }
        context.stroke(ridges, with: .color(Color(red: 0.80, green: 0.38, blue: 0.48).opacity(0.7)), lineWidth: 1)
        context.fill(Path(ellipseIn: CGRect(x: base.x - 4, y: base.y - 3, width: 8, height: 4)),
                     with: .color(Color(red: 0.85, green: 0.45, blue: 0.53)))
    }

    private func drawStarfish(in context: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        var star = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = -Double.pi / 2 + Double(i) * .pi / 5 + 0.2
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            i == 0 ? star.move(to: point) : star.addLine(to: point)
        }
        star.closeSubpath()
        context.fill(star, with: .color(Color(red: 1.0, green: 0.55, blue: 0.25)))
        context.stroke(star, with: .color(Color(red: 0.88, green: 0.40, blue: 0.15)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        for i in 0..<5 {
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / 5 + 0.2
            let dot = CGPoint(x: center.x + cos(angle) * radius * 0.5, y: center.y + sin(angle) * radius * 0.5)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 1, y: dot.y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.8)))
        }
    }

    private func drawSpiral(in context: inout GraphicsContext, at center: CGPoint, radius: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(Color(red: 0.96, green: 0.88, blue: 0.72)))
        var spiral = Path()
        for step in 0...40 {
            let t = Double(step) / 40
            let angle = t * 4 * .pi
            let r = radius * 0.9 * (1 - t)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            step == 0 ? spiral.move(to: point) : spiral.addLine(to: point)
        }
        context.stroke(spiral, with: .color(Color(red: 0.72, green: 0.55, blue: 0.38)), lineWidth: 1.2)
    }
}

/// Algas nas duas laterais, balançando devagar como se houvesse correnteza.
struct SeaweedView: View {
    private struct Strand { let x: CGFloat; let heightFraction: CGFloat; let phase: Double; let color: Color }

    private let strands: [Strand] = [
        Strand(x: 0.04, heightFraction: 0.42, phase: 0.0, color: Color(red: 0.16, green: 0.58, blue: 0.42)),
        Strand(x: 0.08, heightFraction: 0.30, phase: 1.3, color: Color(red: 0.24, green: 0.70, blue: 0.48)),
        Strand(x: 0.12, heightFraction: 0.22, phase: 2.1, color: Color(red: 0.12, green: 0.50, blue: 0.36)),
        Strand(x: 0.90, heightFraction: 0.26, phase: 0.7, color: Color(red: 0.24, green: 0.70, blue: 0.48)),
        Strand(x: 0.95, heightFraction: 0.38, phase: 1.9, color: Color(red: 0.16, green: 0.58, blue: 0.42)),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for strand in strands {
                    let segments = 14
                    let length = size.height * strand.heightFraction
                    var previous = CGPoint(x: size.width * strand.x, y: size.height + 4)
                    for s in 1...segments {
                        let f = CGFloat(s) / CGFloat(segments)
                        let sway = sin(t * 1.1 + strand.phase + Double(f) * 2.4) * 10 * Double(f)
                        let point = CGPoint(x: size.width * strand.x + CGFloat(sway), y: size.height + 4 - length * f)
                        var segment = Path()
                        segment.move(to: previous)
                        segment.addLine(to: point)
                        context.stroke(segment, with: .color(strand.color),
                                       style: StrokeStyle(lineWidth: 9 - 6 * f, lineCap: .round))
                        previous = point
                    }
                }
            }
        }
    }
}

/// Recife no canto direito: um coral rosa ramificado e um menor, roxo.
struct CoralView: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 42)
            drawBranch(in: &context, from: CGPoint(x: size.width * 0.74, y: size.height - 4), angle: -.pi / 2 - 0.15,
                       length: 22, width: 5, depth: 3, color: Color(red: 0.68, green: 0.45, blue: 0.86), rng: &rng)
            drawBranch(in: &context, from: CGPoint(x: size.width * 0.83, y: size.height - 2), angle: -.pi / 2 + 0.1,
                       length: 30, width: 7, depth: 4, color: Color(red: 1.0, green: 0.48, blue: 0.52), rng: &rng)
        }
    }

    private func drawBranch(in context: inout GraphicsContext, from start: CGPoint, angle: Double, length: CGFloat,
                            width: CGFloat, depth: Int, color: Color, rng: inout SeededGenerator) {
        let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        guard depth > 0 else {
            context.fill(Path(ellipseIn: CGRect(x: end.x - width * 0.7, y: end.y - width * 0.7, width: width * 1.4, height: width * 1.4)),
                         with: .color(color.opacity(0.9)))
            return
        }
        for side in [-1.0, 1.0] {
            drawBranch(in: &context, from: end, angle: angle + side * Double.random(in: 0.3...0.6, using: &rng),
                       length: length * CGFloat.random(in: 0.62...0.8, using: &rng), width: width * 0.72,
                       depth: depth - 1, color: color, rng: &rng)
        }
    }
}

/// Baú do tesouro no canto esquerdo, com moedas e um brilho piscando.
struct TreasureChestView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let cx = size.width * 0.22
                let bottom = size.height - 12
                let w: CGFloat = 50, bodyH: CGFloat = 26, lidH: CGFloat = 14
                let wood = Color(red: 0.55, green: 0.33, blue: 0.16)
                let woodDark = Color(red: 0.40, green: 0.23, blue: 0.10)
                let gold = Color(red: 1.0, green: 0.80, blue: 0.25)

                // Moedas em volta da base.
                for (dx, dy) in [(-32.0, 2.0), (-26.0, -1.0), (30.0, 1.0), (35.0, 3.0)] {
                    context.fill(Path(ellipseIn: CGRect(x: cx + dx - 5, y: bottom + dy - 3, width: 10, height: 5)), with: .color(gold))
                }

                let bodyRect = CGRect(x: cx - w / 2, y: bottom - bodyH, width: w, height: bodyH)
                context.fill(Path(roundedRect: bodyRect, cornerRadius: 3), with: .color(wood))

                var lid = Path()
                lid.move(to: CGPoint(x: cx - w / 2, y: bottom - bodyH))
                lid.addCurve(to: CGPoint(x: cx + w / 2, y: bottom - bodyH),
                             control1: CGPoint(x: cx - w / 2, y: bottom - bodyH - lidH * 1.3),
                             control2: CGPoint(x: cx + w / 2, y: bottom - bodyH - lidH * 1.3))
                lid.closeSubpath()
                context.fill(lid, with: .color(woodDark))

                for dx in [-w / 2 + 8, w / 2 - 8] {
                    let band = CGRect(x: cx + dx - 2.5, y: bottom - bodyH - lidH + 1, width: 5, height: bodyH + lidH - 1)
                    context.fill(Path(band), with: .color(gold))
                }
                context.fill(Path(CGRect(x: cx - w / 2, y: bottom - bodyH - 1.5, width: w, height: 3)), with: .color(gold))
                context.fill(Path(roundedRect: CGRect(x: cx - 5, y: bottom - bodyH - 2, width: 10, height: 11), cornerRadius: 2), with: .color(gold))
                context.fill(Path(ellipseIn: CGRect(x: cx - 1.5, y: bottom - bodyH + 2, width: 3, height: 3)), with: .color(woodDark))

                // Brilhinhos que piscam, cada um no seu ritmo.
                let sparkles: [(CGFloat, CGFloat, Double)] = [(-18, -48, 0), (20, -44, 1.7), (2, -56, 3.1)]
                for (dx, dy, phase) in sparkles {
                    let pulse = max(0, sin(t * 2.2 + phase))
                    guard pulse > 0.05 else { continue }
                    drawSparkle(in: &context, at: CGPoint(x: cx + dx, y: bottom + dy), size: 7 * pulse, color: gold)
                }
            }
        }
    }
}

// MARK: - Na água

/// Bolhas subindo de dois pontos do fundo até perto da superfície.
struct BubblesView: View {
    let waterLevel: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 12
                let start = size.height - 16
                guard start - top > 20 else { return }
                for (sourceIndex, sourceX) in [size.width * 0.24, size.width * 0.86].enumerated() {
                    let count = 7
                    for i in 0..<count {
                        let period = 4.5 + Double(i % 3) * 0.6
                        let raw = t / period + Double(i) / Double(count) + Double(sourceIndex) * 0.37
                        let p = raw - floor(raw)
                        let y = start - (start - top) * CGFloat(p)
                        let x = sourceX + CGFloat(sin(p * 9 + Double(i))) * 5
                        let r = 2 + CGFloat(i % 4)
                        let fade = p > 0.85 ? (1 - p) / 0.15 : min(1, p / 0.1)
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.75 * fade)), lineWidth: 1.2)
                        context.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.5, height: r * 0.5)),
                                     with: .color(.white.opacity(0.8 * fade)))
                    }
                }
            }
        }
    }
}

/// Três peixinhos atravessando o aquário em alturas e velocidades diferentes.
struct FishSchoolView: View {
    let waterLevel: Double

    private struct Fish { let speed: Double; let offset: Double; let depth: CGFloat; let size: CGFloat; let color: Color; let leftToRight: Bool }

    private let school: [Fish] = [
        Fish(speed: 38, offset: 0, depth: 0.25, size: 1.0, color: Color(red: 1.0, green: 0.55, blue: 0.20), leftToRight: true),
        Fish(speed: 27, offset: 170, depth: 0.60, size: 0.8, color: Color(red: 1.0, green: 0.82, blue: 0.25), leftToRight: false),
        Fish(speed: 48, offset: 90, depth: 0.85, size: 0.7, color: Color(red: 0.30, green: 0.75, blue: 0.95), leftToRight: true),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 22
                let bottom = size.height - 60
                let band = bottom - top
                context.opacity = swimOpacity(band: band, minimum: 10)
                guard context.opacity > 0 else { return }
                let track = Double(size.width + 80)
                for (i, fish) in school.enumerated() {
                    let travelled = (t * fish.speed + fish.offset).truncatingRemainder(dividingBy: track)
                    let x = fish.leftToRight ? CGFloat(travelled) - 40 : size.width + 40 - CGFloat(travelled)
                    let y = top + band * fish.depth + CGFloat(sin(t * 1.4 + Double(i) * 2)) * 5
                    let wiggle = CGFloat(sin(t * 9 + Double(i)))
                    drawFish(in: &context, at: CGPoint(x: x, y: y), scale: fish.size, color: fish.color,
                             facingRight: fish.leftToRight, tailWiggle: wiggle)
                }
            }
        }
    }

    private func drawFish(in context: inout GraphicsContext, at center: CGPoint, scale: CGFloat, color: Color,
                          facingRight: Bool, tailWiggle: CGFloat) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: facingRight ? scale : -scale, y: scale)

        var tail = Path()
        tail.move(to: CGPoint(x: -9, y: 0))
        tail.addLine(to: CGPoint(x: -19, y: -7 + tailWiggle * 2))
        tail.addLine(to: CGPoint(x: -19, y: 7 + tailWiggle * 2))
        tail.closeSubpath()
        ctx.fill(tail, with: .color(color.opacity(0.85)))

        ctx.fill(Path(ellipseIn: CGRect(x: -12, y: -7, width: 24, height: 14)), with: .color(color))
        var fin = Path()
        fin.move(to: CGPoint(x: -3, y: -6))
        fin.addQuadCurve(to: CGPoint(x: 5, y: -6), control: CGPoint(x: 0, y: -12))
        ctx.fill(fin, with: .color(color.opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: 4, y: -3.5, width: 4.5, height: 4.5)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: 5.6, y: -2.3, width: 2.2, height: 2.2)), with: .color(.black))
    }
}

/// Uma água-viva translúcida subindo e descendo devagar, pulsando o sino.
struct JellyfishView: View {
    let waterLevel: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 30
                let bottom = size.height * 0.62
                let band = bottom - top
                context.opacity = swimOpacity(band: band, minimum: 0)
                guard context.opacity > 0 else { return }

                let cx = size.width * 0.80 + CGFloat(sin(t * 0.3)) * size.width * 0.04
                let cy = top + band * CGFloat(0.5 + 0.5 * sin(t * 0.45))
                let pulse = CGFloat(sin(t * 2.6))
                let bellW = 30 * (1 + 0.08 * pulse)
                let bellH = 22 * (1 - 0.08 * pulse)
                let pink = Color(red: 0.95, green: 0.55, blue: 0.85)

                var tentacles = Path()
                for i in 0..<4 {
                    let x0 = cx - bellW * 0.3 + CGFloat(i) * bellW * 0.2
                    tentacles.move(to: CGPoint(x: x0, y: cy))
                    for step in 1...8 {
                        let f = CGFloat(step) / 8
                        let sway = CGFloat(sin(t * 3 + Double(i) + Double(f) * 4)) * 3 * f
                        tentacles.addLine(to: CGPoint(x: x0 + sway, y: cy + 30 * f))
                    }
                }
                context.stroke(tentacles, with: .color(pink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                var bell = Path()
                bell.move(to: CGPoint(x: cx - bellW / 2, y: cy))
                bell.addCurve(to: CGPoint(x: cx + bellW / 2, y: cy),
                              control1: CGPoint(x: cx - bellW / 2, y: cy - bellH * 1.3),
                              control2: CGPoint(x: cx + bellW / 2, y: cy - bellH * 1.3))
                for i in 0..<4 {
                    let x1 = cx + bellW / 2 - CGFloat(i + 1) * bellW / 4
                    bell.addQuadCurve(to: CGPoint(x: x1, y: cy), control: CGPoint(x: x1 + bellW / 8, y: cy + 4))
                }
                bell.closeSubpath()
                context.fill(bell, with: .linearGradient(
                    Gradient(colors: [pink.opacity(0.85), pink.opacity(0.5)]),
                    startPoint: CGPoint(x: cx, y: cy - bellH), endPoint: CGPoint(x: cx, y: cy)
                ))
                context.fill(Path(ellipseIn: CGRect(x: cx - bellW * 0.28, y: cy - bellH * 0.8, width: bellW * 0.22, height: bellH * 0.3)),
                             with: .color(.white.opacity(0.6)))
            }
        }
    }
}

/// Feixes de luz entrando pelo topo do aquário, com um brilho que vai e vem.
struct SunRaysView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let light = Color(red: 1.0, green: 0.96, blue: 0.75)
                let rays: [(x: CGFloat, width: CGFloat, phase: Double)] = [(0.18, 26, 0), (0.42, 40, 1.4), (0.66, 22, 2.6), (0.86, 34, 4.0)]
                for ray in rays {
                    let shimmer = 0.5 + 0.5 * sin(t * 0.8 + ray.phase)
                    let topX = size.width * ray.x
                    let slant = size.height * 0.35
                    var beam = Path()
                    beam.move(to: CGPoint(x: topX - ray.width / 2, y: 0))
                    beam.addLine(to: CGPoint(x: topX + ray.width / 2, y: 0))
                    beam.addLine(to: CGPoint(x: topX + slant + ray.width, y: size.height))
                    beam.addLine(to: CGPoint(x: topX + slant - ray.width * 0.2, y: size.height))
                    beam.closeSubpath()
                    context.fill(beam, with: .linearGradient(
                        Gradient(colors: [light.opacity(0.10 + 0.22 * shimmer), light.opacity(0)]),
                        startPoint: CGPoint(x: topX, y: 0), endPoint: CGPoint(x: topX + slant, y: size.height * 0.9)
                    ))
                }
            }
        }
    }
}

/// Pontinhos bioluminescentes flutuando e piscando — ficam lindos no modo escuro.
struct PlanktonView: View {
    let waterLevel: Double

    private let specks: [(x: CGFloat, y: CGFloat, phase: Double)] = {
        var rng = SeededGenerator(seed: 2026)
        return (0..<28).map { _ in
            (CGFloat.random(in: 0.04...0.96, using: &rng), CGFloat.random(in: 0...1, using: &rng), Double.random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let top = waterTop(height: size.height, level: waterLevel) + 8
                let band = size.height - 8 - top
                guard band > 10 else { return }
                let glow = Color(red: 0.55, green: 1.0, blue: 0.92)
                for speck in specks {
                    let twinkle = 0.5 + 0.5 * sin(t * 1.8 + speck.phase)
                    let x = size.width * speck.x + CGFloat(sin(t * 0.3 + speck.phase)) * 8
                    let y = top + band * speck.y + CGFloat(cos(t * 0.25 + speck.phase)) * 6
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(glow.opacity(0.22 * twinkle)))
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)), with: .color(glow.opacity(0.4 + 0.6 * twinkle)))
                }
            }
        }
    }
}

/// Estrelinha de quatro pontas (o brilho do baú).
private func drawSparkle(in context: inout GraphicsContext, at center: CGPoint, size: CGFloat, color: Color) {
    var path = Path()
    path.move(to: CGPoint(x: center.x, y: center.y - size))
    path.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y), control: center)
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size), control: center)
    path.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y), control: center)
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size), control: center)
    context.fill(path, with: .color(color))
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
