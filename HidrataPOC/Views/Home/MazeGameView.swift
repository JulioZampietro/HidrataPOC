import SwiftUI

/// Desenha o Rim Comilão (`MazeGameSimulation`) dentro do recipiente de água, no mesmo lugar dos
/// outros minijogos — então passa pela refração do shader. Recebe toque: deslizar no aquário
/// vira o rim pra direção do deslize (os botões na Home fazem o mesmo).
struct MazeGameView: View {
    let simulation: MazeGameSimulation
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
        .onTapGesture { simulation.begin() }
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

    private static func draw(_ snapshot: MazeGameSnapshot, time: Double, size: CGSize, in ctx: inout GraphicsContext) {
        drawWalls(snapshot, in: &ctx)
        let tile = snapshot.tile

        for pellet in snapshot.pellets { drawDrop(at: pellet, radius: tile * 0.12, in: &ctx) }
        let pulse = 1 + 0.12 * CGFloat(sin(time * 6))
        for power in snapshot.powers { drawDrop(at: power, radius: tile * 0.22 * pulse, in: &ctx) }

        for rock in snapshot.rocks { drawRock(rock, tile: tile, time: time, in: &ctx) }
        drawPlayer(snapshot, in: &ctx)
        drawHUD(snapshot, size: size, in: &ctx)
    }

    private static let wallColor = Color(red: 0.55, green: 0.47, blue: 0.40)

    /// Paredes de pedra: cada casa vira um bloco arredondado, emendado com os vizinhos pra formar
    /// corredores contínuos, com uma sombra leve embaixo.
    private static func drawWalls(_ snapshot: MazeGameSnapshot, in ctx: inout GraphicsContext) {
        let tile = snapshot.tile
        let inset = tile * 0.12
        let walls = Set(snapshot.walls.map { CellKey(rect: $0, tile: tile) })
        var path = Path()
        for rect in snapshot.walls {
            let key = CellKey(rect: rect, tile: tile)
            path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: tile * 0.3, height: tile * 0.3))
            // Emenda com o vizinho da direita e o de baixo.
            if walls.contains(CellKey(x: key.x + 1, y: key.y)) {
                path.addRect(CGRect(x: rect.midX, y: rect.minY + inset, width: tile, height: tile - inset * 2))
            }
            if walls.contains(CellKey(x: key.x, y: key.y + 1)) {
                path.addRect(CGRect(x: rect.minX + inset, y: rect.midY, width: tile - inset * 2, height: tile))
            }
            // Bloco 2×2: tapa o furinho que sobra no meio dos quatro.
            if walls.contains(CellKey(x: key.x + 1, y: key.y)), walls.contains(CellKey(x: key.x, y: key.y + 1)),
               walls.contains(CellKey(x: key.x + 1, y: key.y + 1)) {
                path.addRect(CGRect(x: rect.midX, y: rect.midY, width: tile, height: tile))
            }
        }
        // Fundo da casinha das pedras.
        ctx.fill(Path(roundedRect: snapshot.house.insetBy(dx: inset, dy: inset), cornerRadius: tile * 0.3),
                 with: .color(.black.opacity(0.08)))
        ctx.fill(path.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.15)))
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [wallColor.mix(with: .white, by: 0.15), wallColor.mix(with: .black, by: 0.1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: 600)
        ))
        drawWallTexture(path, snapshot.walls, tile: tile, in: &ctx)

        // Porta da casinha das pedras.
        let door = snapshot.door
        let bar = CGRect(x: door.minX, y: door.midY - tile * 0.08, width: door.width, height: tile * 0.16)
        ctx.fill(Path(roundedRect: bar, cornerRadius: tile * 0.08), with: .color(Color(red: 1.0, green: 0.72, blue: 0.78)))
    }

    /// Textura leve de pedra por cima das paredes: pintinhas claras e escuras sorteadas pela
    /// posição de cada casa (então ficam sempre nos mesmos lugares) e um brilho fino na borda.
    private static func drawWallTexture(_ path: Path, _ walls: [CGRect], tile: CGFloat, in context: inout GraphicsContext) {
        var ctx = context
        ctx.clip(to: path)
        var dark = Path()
        var light = Path()
        for rect in walls {
            let key = CellKey(rect: rect, tile: tile)
            var seed = UInt64(truncatingIfNeeded: (key.x &* 73_856_093) ^ (key.y &* 19_349_663))
            for n in 0..<3 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let fx = CGFloat((seed >> 33) % 1000) / 1000
                let fy = CGFloat((seed >> 13) % 1000) / 1000
                let r = tile * (0.05 + 0.03 * CGFloat((seed >> 50) % 3))
                let dot = CGRect(x: rect.minX + fx * tile - r, y: rect.minY + fy * tile - r, width: r * 2, height: r * 2)
                if n == 0 { light.addEllipse(in: dot) } else { dark.addEllipse(in: dot) }
            }
        }
        ctx.fill(dark, with: .color(.black.opacity(0.12)))
        ctx.fill(light, with: .color(.white.opacity(0.16)))
        // Chanfro: faixa clara na borda de cima e escura na de baixo, recortando a parede com
        // ela mesma deslocada. Um traço no contorno riscaria a emenda de cada bloco por dentro.
        let bounds = path.boundingRect.insetBy(dx: -4, dy: -4)
        var top = ctx
        top.clip(to: path.offsetBy(dx: 0, dy: 2), options: .inverse)
        top.fill(Path(bounds), with: .color(.white.opacity(0.22)))
        var bottom = ctx
        bottom.clip(to: path.offsetBy(dx: 0, dy: -2), options: .inverse)
        bottom.fill(Path(bounds), with: .color(.black.opacity(0.10)))
    }

    /// Posição de uma parede em casas, pra achar os vizinhos sem guardar o labirinto na foto.
    private struct CellKey: Hashable {
        let x: Int
        let y: Int

        init(x: Int, y: Int) { self.x = x; self.y = y }

        init(rect: CGRect, tile: CGFloat) {
            x = Int((rect.minX / tile).rounded())
            y = Int((rect.minY / tile).rounded())
        }
    }

    /// Gota d'água pra comer, centrada no ponto (a gota desenhada vai de −2,1 r a r em y).
    private static func drawDrop(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: point.x, y: point.y + radius * 0.55)
        DropDrawing.draw(radius: radius, facing: 0, eyes: false, in: &ctx)
    }

    /// As pedras são o mascote: cada uma com a imagem de um estágio (as mais bravas). Com medo,
    /// viram a pedra derrotada (`mascote1`), piscando quando o medo está acabando; comidas,
    /// voltam pra casinha como uma pedrinha pequena.
    private static let rockImages = ["mascote5", "mascote4", "mascote3", "mascote2"]

    private static func drawRock(_ rock: MazeGameSnapshot.Rock, tile: CGFloat, time: Double, in context: inout GraphicsContext) {
        var ctx = context
        if rock.look == .eaten {
            PebbleDrawing.draw(center: rock.position, radiusX: tile * 0.22, radiusY: tile * 0.22,
                               tint: Color(red: 0.6, green: 0.6, blue: 0.62), seed: rock.index * 31, in: &ctx)
            return
        }
        let name = rock.look == .normal ? rockImages[rock.index % rockImages.count] : "mascote1"
        if rock.look == .flashing { ctx.opacity = 0.45 }
        let image = ctx.resolve(Image(name))
        let box = tile * 1.7 * AppTheme.mascotSizeCorrection(for: name)
        let aspect = image.size.width / max(image.size.height, 1)
        let drawSize = aspect >= 1 ? CGSize(width: box, height: box / aspect) : CGSize(width: box * aspect, height: box)
        // Balancinho pra parecer vivo, cada pedra no seu ritmo.
        let bob = CGFloat(sin(time * 5 + Double(rock.index))) * tile * 0.05
        let rect = CGRect(x: rock.position.x - drawSize.width / 2, y: rock.position.y - drawSize.height / 2 + bob,
                          width: drawSize.width, height: drawSize.height)
        ctx.draw(image, in: rect)
    }

    private static let kidneyOutline = Color(red: 0.62, green: 0.24, blue: 0.27)
    private static let kidneyInk = Color(red: 0.32, green: 0.12, blue: 0.14)

    /// O rim (o mesmo feijão dos rins do aquário, `KidneyCheerView.beanPath`), olhando pra onde
    /// anda e mastigando com a boca na reentrância. Pego por uma pedra, encolhe e some.
    private static func drawPlayer(_ snapshot: MazeGameSnapshot, in context: inout GraphicsContext) {
        var ctx = context
        var scale = snapshot.tile * 0.92 / 36
        if snapshot.phase == .dying { scale *= max(0, 1 - snapshot.phaseProgress) }
        if snapshot.phase == .gameOver { return }
        guard scale > 0.01 else { return }
        ctx.translateBy(x: snapshot.player.x, y: snapshot.player.y)
        ctx.scaleBy(x: scale * snapshot.playerFacing, y: scale)

        let bean = KidneyCheerView.beanPath
        ctx.fill(bean, with: .linearGradient(
            Gradient(colors: [Color(red: 0.97, green: 0.60, blue: 0.60), Color(red: 0.90, green: 0.45, blue: 0.47)]),
            startPoint: CGPoint(x: -10, y: -18), endPoint: CGPoint(x: 6, y: 18)
        ))
        ctx.stroke(bean, with: .color(kidneyOutline), lineWidth: 1.8)
        ctx.fill(Path(ellipseIn: CGRect(x: -14, y: -13, width: 5, height: 7)), with: .color(.white.opacity(0.45)))

        // Olhos abertos, olhando pra frente.
        for dx: CGFloat in [-9, -1] {
            ctx.fill(Path(ellipseIn: CGRect(x: dx - 2.6, y: -9, width: 5.2, height: 6.4)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: dx - 0.6, y: -7.5, width: 3, height: 3.6)), with: .color(kidneyInk))
        }
        // Boca na reentrância, abrindo e fechando enquanto anda.
        let open = 1 + 7 * snapshot.mouthOpen
        ctx.fill(Path(ellipseIn: CGRect(x: 1, y: 2 - open / 2, width: 8, height: open)), with: .color(kidneyInk))
    }

    /// Pontos e vidas no meio do cabeçalho (entre a seta de voltar e o botão de minijogos) e os
    /// avisos de cada momento da partida no meio do labirinto.
    private static func drawHUD(_ snapshot: MazeGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 24).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 20)
        )
        // Vidas: rinzinhos embaixo dos pontos.
        for i in 0..<max(0, snapshot.lives) {
            var lifeCtx = ctx
            lifeCtx.translateBy(x: size.width / 2 + (CGFloat(i) - CGFloat(snapshot.lives - 1) / 2) * 16, y: 42)
            lifeCtx.scaleBy(x: 0.3, y: 0.3)
            lifeCtx.fill(KidneyCheerView.beanPath, with: .color(Color(red: 0.95, green: 0.55, blue: 0.56)))
            lifeCtx.stroke(KidneyCheerView.beanPath, with: .color(kidneyOutline), lineWidth: 3)
        }

        let message: String? = switch snapshot.phase {
        case .levelClear: "Fase limpa!"
        case .gameOver: "Fim de jogo"
        case .ready, .playing, .dying: nil
        }
        if let message {
            textCtx.draw(
                Text(message)
                    .font(.custom("Nunito", size: 20).weight(.black))
                    .foregroundStyle(.white),
                at: CGPoint(x: size.width / 2, y: size.height * 0.62)
            )
        }
        if snapshot.phase == .ready {
            GameStartPrompt.draw(title: "Fase \(snapshot.level)", hint: "Deslize pra guiar o rim e comer as gotas",
                                 centerY: size.height * 0.62, size: size, in: &ctx)
        }
    }
}
