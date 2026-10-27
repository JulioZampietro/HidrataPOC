import SwiftUI

/// Desenha o Campo Minado (`MinesGameSimulation`) dentro do recipiente de água, no mesmo lugar
/// dos outros minijogos — então passa pela refração do shader. Recebe toque: tocar numa casa abre
/// (ou marca, com o modo de marcar ligado) e segurar faz o contrário.
struct MinesGameView: View {
    let simulation: MinesGameSimulation
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
        // Toque e segurar como gestos próprios (não um `DragGesture` medindo o tempo): o aquário
        // fica dentro das páginas da Home, que seguram o começo do toque e faziam toques rápidos
        // se perderem. Segurar vem antes; se o dedo sai cedo, vale o toque.
        .gesture(
            LongPressGesture(minimumDuration: MinesGameTuning.longPress)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { value in
                    guard case let .second(true, drag?) = value else { return }
                    simulation.tap(at: drag.startLocation, longPress: true)
                }
                .exclusively(before: SpatialTapGesture().onEnded { simulation.tap(at: $0.location, longPress: false) })
        )
        .accessibilityHidden(true)
    }

    // MARK: - Desenho

    /// Pó de pedra quando uma pedra é achada.
    private static let dustColor = Color(red: 0.70, green: 0.60, blue: 0.48)
    private static let flagColor = Color(red: 0.93, green: 0.26, blue: 0.28)
    private static let ink = Color(red: 0.18, green: 0.13, blue: 0.10)
    private static let hiddenTop = Color(red: 0.62, green: 0.80, blue: 1.0).opacity(0.7)
    private static let hiddenBottom = Color(red: 0.28, green: 0.55, blue: 0.95).opacity(0.55)

    /// Cor de cada número (1…8), escura o bastante pra ler sobre a casa aberta clara.
    private static let numberColors: [Color] = [
        Color(red: 0.05, green: 0.34, blue: 0.82),
        Color(red: 0.10, green: 0.52, blue: 0.24),
        Color(red: 0.82, green: 0.18, blue: 0.20),
        Color(red: 0.24, green: 0.18, blue: 0.62),
        Color(red: 0.58, green: 0.12, blue: 0.14),
        Color(red: 0.05, green: 0.50, blue: 0.55),
        Color(red: 0.15, green: 0.15, blue: 0.18),
        Color(red: 0.42, green: 0.42, blue: 0.46),
    ]

    private static func draw(_ snapshot: MinesGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        let board = snapshot.board
        ctx.fill(Path(roundedRect: board.insetBy(dx: -4, dy: -4), cornerRadius: snapshot.tile * 0.3),
                 with: .color(.white.opacity(0.14)))
        for (index, cell) in snapshot.cells.enumerated() {
            let x = index % snapshot.columns, y = index / snapshot.columns
            let rect = CGRect(x: board.minX + CGFloat(x) * snapshot.tile, y: board.minY + CGFloat(y) * snapshot.tile,
                              width: snapshot.tile, height: snapshot.tile).insetBy(dx: 1.5, dy: 1.5)
            drawCell(cell, in: rect, seed: index, ctx: &ctx)
        }
        for particle in snapshot.particles {
            var dustCtx = ctx
            dustCtx.opacity = particle.alpha
            let r = particle.radius
            let rect = CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)
            dustCtx.fill(Path(ellipseIn: rect), with: .color(particle.isStone ? dustColor : .white.opacity(0.85)))
        }
        drawHUD(snapshot, size: size, in: &ctx)
        GameConfetti.draw(snapshot.confetti, colors: PebbleGameTuning.colors, in: &ctx)
    }

    /// Casa fechada: bolha de vidro translúcida com brilho em cima. Aberta: clara e lisa, com o
    /// número de pedras em volta.
    private static func drawCell(_ cell: MinesGameSnapshot.Cell, in rect: CGRect, seed: Int, ctx: inout GraphicsContext) {
        let corner = rect.width * 0.22
        let shape = Path(roundedRect: rect, cornerRadius: corner)
        switch cell {
        case .hidden, .flagged, .wrongFlag:
            // Vidro azulado: aparece tanto sobre a água quanto com o aquário ainda vazio.
            ctx.fill(shape, with: .linearGradient(
                Gradient(colors: [hiddenTop, hiddenBottom]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
            ctx.stroke(shape, with: .color(.white.opacity(0.6)), lineWidth: 1)
            let shine = CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.12,
                               width: rect.width * 0.3, height: rect.height * 0.14)
            ctx.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.5)))
            if cell != .hidden { drawFlag(in: rect, wrong: cell == .wrongFlag, ctx: &ctx) }
        case let .revealed(count):
            ctx.fill(shape, with: .color(.white.opacity(0.82)))
            if count > 0 {
                ctx.draw(
                    Text("\(count)")
                        .font(.custom("Nunito", size: rect.height * 0.62).weight(.black))
                        .foregroundStyle(numberColors[(count - 1) % numberColors.count]),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        case let .stone(exploded):
            ctx.fill(shape, with: .color(exploded ? flagColor.opacity(0.75) : .white.opacity(0.82)))
            let r = rect.width * 0.32
            PebbleDrawing.draw(center: CGPoint(x: rect.midX, y: rect.midY), radiusX: r, radiusY: r,
                               tint: PebbleDrawing.stoneBrown, seed: seed &* 7919, in: &ctx)
        }
    }

    /// Bandeirinha vermelha num mastro; `wrong` risca um X por cima (marcada sem pedra embaixo).
    private static func drawFlag(in rect: CGRect, wrong: Bool, ctx: inout GraphicsContext) {
        let w = rect.width
        let poleX = rect.minX + w * 0.42
        var pole = Path()
        pole.move(to: CGPoint(x: poleX, y: rect.minY + w * 0.22))
        pole.addLine(to: CGPoint(x: poleX, y: rect.maxY - w * 0.2))
        ctx.stroke(pole, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, w * 0.06), lineCap: .round))
        var flag = Path()
        flag.move(to: CGPoint(x: poleX, y: rect.minY + w * 0.2))
        flag.addLine(to: CGPoint(x: poleX + w * 0.34, y: rect.minY + w * 0.34))
        flag.addLine(to: CGPoint(x: poleX, y: rect.minY + w * 0.5))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(flagColor))
        var base = Path()
        base.move(to: CGPoint(x: poleX - w * 0.16, y: rect.maxY - w * 0.2))
        base.addLine(to: CGPoint(x: poleX + w * 0.16, y: rect.maxY - w * 0.2))
        ctx.stroke(base, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, w * 0.07), lineCap: .round))
        guard wrong else { return }
        var cross = Path()
        cross.move(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + w * 0.2))
        cross.addLine(to: CGPoint(x: rect.maxX - w * 0.2, y: rect.maxY - w * 0.2))
        cross.move(to: CGPoint(x: rect.maxX - w * 0.2, y: rect.minY + w * 0.2))
        cross.addLine(to: CGPoint(x: rect.minX + w * 0.2, y: rect.maxY - w * 0.2))
        ctx.stroke(cross, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: max(1.5, w * 0.07), lineCap: .round))
    }

    /// Pontos no meio do cabeçalho (entre a seta de voltar e o botão de minijogos), pedras que
    /// faltam marcar logo abaixo, e os avisos.
    private static func drawHUD(_ snapshot: MinesGameSnapshot, size: CGSize, in ctx: inout GraphicsContext) {
        var textCtx = ctx
        textCtx.addFilter(.shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6).opacity(0.45), radius: 3, y: 1))
        textCtx.draw(
            Text("\(snapshot.score)")
                .font(.custom("Nunito", size: 26).weight(.black))
                .foregroundStyle(.white),
            at: CGPoint(x: size.width / 2, y: 26)
        )
        textCtx.draw(
            Text("\(snapshot.stonesLeft) \(snapshot.stonesLeft == 1 ? "pedra" : "pedras")")
                .font(.custom("Nunito", size: 13).weight(.heavy))
                .foregroundStyle(.white.opacity(0.9)),
            at: CGPoint(x: size.width / 2, y: 49)
        )
        if snapshot.phase == .ready {
            GameStartPrompt.draw(hint: "Toque abre a casa, segure marca a pedra", centerY: snapshot.board.midY, size: size, in: &ctx)
        } else if snapshot.phase == .dying {
            GameStartPrompt.draw(title: "Fim de jogo", action: "Tentar novamente",
                                 hint: "\(snapshot.score) \(snapshot.score == 1 ? "ponto" : "pontos")",
                                 centerY: snapshot.board.midY, size: size, backdrop: true, compact: true, in: &ctx)
        } else if snapshot.phase == .won {
            GameStartPrompt.draw(title: "Parabéns!", action: "Toque pra recomeçar", hint: "Você limpou o campo!",
                                 centerY: snapshot.board.midY, size: size, backdrop: true, in: &ctx)
        }
    }
}

/// Cartão ao lado do recorde no Campo Minado: troca o que o toque faz na água — abrir a casa ou
/// marcar uma bandeira. Mesmo jeito do `GameHintCard`; ligado, fica azul, como um cartão de
/// ingestão tocado.
struct MinesModeCard: View {
    let isFlagging: Bool
    let height: CGFloat
    let onToggle: () -> Void

    var body: some View {
        Button {
            Haptic.selection.play()
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isFlagging ? "flag.fill" : "hand.tap.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(isFlagging ? Color.white : Color.appAccent)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isFlagging ? "Marcando pedras" : "Abrindo casas")
                        .font(AppFont.headline)
                        .foregroundStyle(isFlagging ? Color.white : Color.appAccentText)
                    Text(isFlagging ? "Toque aqui pra voltar a abrir" : "Toque aqui ou segure na casa pra marcar")
                        .font(AppFont.subheadline)
                        .foregroundStyle(isFlagging ? Color.white : Color.appSecondary)
                }
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFlagging ? AnyShapeStyle(LinearGradient.waterHeader) : AnyShapeStyle(Color(UIColor.secondarySystemBackground)))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modo de marcar pedras")
        .accessibilityValue(isFlagging ? "Ligado" : "Desligado")
        .accessibilityHint("Com ele ligado, tocar na água marca uma bandeira em vez de abrir a casa")
    }
}
