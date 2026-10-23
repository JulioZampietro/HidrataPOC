import AVFoundation
import SwiftUI

/// Minijogos que rodam no aquário da Home. Cada um é desbloqueado ao alcançar
/// `requiredStreak` dias de streak; só um fica ativo por vez (ou nenhum, com `.noGame`:
/// o aquário fica só com as pedrinhas), escolhido na aba de minijogos (`MiniGamesView`) e
/// lembrado entre aberturas do app (`@AppStorage(MiniGame.selectedStorageKey)`). O escolhido
/// entra sozinho quando a meta do dia é batida, e com pelo menos `minimumStreakToPlay` dias
/// de streak dá pra jogar a qualquer hora tocando nele na aba.
///
/// Pra criar um jogo novo: adicione o `case` aqui (com título, ícone e streak necessária)
/// e trate o `case` na Home (`HomeView`), onde o jogo é desenhado e controlado.
enum MiniGame: String, CaseIterable, Identifiable {
    case noGame
    case rings
    case jump
    case pebbles
    case flappy
    case maze
    case slice
    case snake
    case mines
    case runner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noGame: "Sem jogo"
        case .rings: "Argolas"
        case .jump: "Gota Saltitante"
        case .pebbles: "Pedras Coloridas"
        case .flappy: "Gota Voadora"
        case .maze: "Rim Comilão"
        case .slice: "Quebra-Pedras"
        case .snake: "Cobrinha"
        case .mines: "Campo Minado"
        case .runner: "Gota Surfista"
        }
    }

    var subtitle: String {
        switch self {
        case .noGame: "Só a água e as pedrinhas, sem minijogo"
        case .rings: "Use os jatos d'água pra encaixar as argolas nos pinos"
        case .jump: "Pule de pedra em pedra e suba o mais alto que der"
        case .pebbles: "Mire e junte pedras da mesma cor para estourar"
        case .flappy: "Toque pra nadar e passe entre as pilhas de pedras"
        case .maze: "Coma as gotas do labirinto e fuja das pedras"
        case .slice: "Corte as pedras e não corte o rim"
        case .snake: "Coma as pedrinhas e cresça sem bater na borda"
        case .mines: "Abra as casas sem achar as pedras escondidas"
        case .runner: "Troque de pista, pule e abaixe pra desviar das pedras"
        }
    }

    var systemImage: String {
        switch self {
        case .noGame: "nosign"
        case .rings: "circle.circle"
        case .jump: "arrow.up.to.line"
        case .pebbles: "circle.hexagongrid.fill"
        case .flappy: "bird.fill"
        case .maze: "square.grid.3x3.topleft.filled"
        case .slice: "scissors"
        case .snake: "scribble.variable"
        case .mines: "flag.fill"
        case .runner: "figure.surfing"
        }
    }

    /// Dias de streak necessários pra desbloquear o jogo. Por enquanto todos liberam com 1 dia;
    /// a escada planejada era argolas 1, Gota Saltitante 3, Bolhas 5, Gota Voadora 7, Rim Comilão 10
    /// (o Quebra-Pedras, a Cobrinha, o Campo Minado e a Gota Surfista ainda não têm degrau).
    var requiredStreak: Int {
        switch self {
        case .noGame: 0
        case .rings, .jump, .pebbles, .flappy, .maze, .slice, .snake, .mines, .runner: 1
        }
    }

    /// `false` só pro `.noGame`, que é a opção de não jogar nada.
    var isPlayable: Bool { self != .noGame }

    func isUnlocked(streak: Int) -> Bool { streak >= requiredStreak }

    var tint: Color {
        switch self {
        case .noGame: Color(red: 0.55, green: 0.60, blue: 0.68)
        case .rings: Color(red: 0.93, green: 0.26, blue: 0.28)
        case .jump: Color(red: 0.25, green: 0.78, blue: 0.42)
        case .pebbles: Color(red: 0.66, green: 0.42, blue: 0.95)
        case .flappy: Color(red: 0.98, green: 0.56, blue: 0.20)
        case .maze: Color(red: 0.90, green: 0.45, blue: 0.47)
        case .slice: Color(red: 0.32, green: 0.70, blue: 0.36)
        case .snake: Color(red: 0.20, green: 0.68, blue: 0.78)
        case .mines: Color(red: 0.93, green: 0.26, blue: 0.28)
        case .runner: Color(red: 0.98, green: 0.62, blue: 0.24)
        }
    }

    /// Chave do `@AppStorage` com o `rawValue` do jogo escolhido (vazio = nunca escolheu).
    static let selectedStorageKey = "minigame.selected"
    /// Chave do `@AppStorage` com os jogos (separados por vírgula) cujo desbloqueio já foi
    /// anunciado — o aviso de "novo minijogo" aparece só uma vez por jogo.
    static let announcedStorageKey = "minigame.announced"
    /// Chave do `@AppStorage` com o recorde da Gota Saltitante.
    static let jumpBestStorageKey = "minigame.jump.best"
    /// Chave do `@AppStorage` com o recorde das Pedras Coloridas.
    static let pebblesBestStorageKey = "minigame.pebbles.best"
    /// Chave do `@AppStorage` com o recorde da Gota Voadora.
    static let flappyBestStorageKey = "minigame.flappy.best"
    /// Chave do `@AppStorage` com o recorde do Rim Comilão.
    static let mazeBestStorageKey = "minigame.maze.best"
    /// Chave do `@AppStorage` com o recorde do Quebra-Pedras.
    static let sliceBestStorageKey = "minigame.slice.best"
    /// Chave do `@AppStorage` com o recorde da Cobrinha.
    static let snakeBestStorageKey = "minigame.snake.best"
    /// Chave do `@AppStorage` com o recorde do Campo Minado.
    static let minesBestStorageKey = "minigame.mines.best"
    /// Chave do `@AppStorage` com o recorde da Gota Surfista.
    static let runnerBestStorageKey = "minigame.runner.best"

    /// Streak mínima pra jogar fora da meta batida (tocando no jogo na aba de minijogos).
    static let minimumStreakToPlay = 1

    /// Jogos de verdade (sem o `.noGame`) já liberados pela streak, na ordem de desbloqueio.
    static func unlocked(streak: Int) -> [MiniGame] {
        // Empate na streak (todos com 1 dia, por enquanto): vale a ordem do `enum`.
        let order = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
        return allCases.filter { $0.isPlayable && $0.isUnlocked(streak: streak) }
            .sorted { ($0.requiredStreak, order[$0] ?? 0) < ($1.requiredStreak, order[$1] ?? 0) }
    }

    /// Opção escolhida pra quando bater a meta: a do usuário, se ainda estiver liberada;
    /// senão o último jogo liberado; `.noGame` se a streak ainda não liberou nenhum.
    static func active(selected rawValue: String, streak: Int) -> MiniGame {
        if let selected = MiniGame(rawValue: rawValue), selected.isUnlocked(streak: streak) { return selected }
        return unlocked(streak: streak).last ?? .noGame
    }
}

/// Sons dos minijogos, no catálogo de assets como data sets (igual ao "agua" da Home). Cada um é
/// carregado uma vez e reusado; tocar de novo recomeça do início.
@MainActor
enum MiniGameSound: String {
    /// Um rim aparece no Quebra-Pedras.
    case kidneyFlying = "RimVoando"
    /// O rim perde uma vida no Rim Comilão.
    case lifeLost = "SomDoPacman"

    private static var players: [MiniGameSound: AVAudioPlayer] = [:]

    func play() {
        guard FeedbackSettings.soundEffectsEnabled,
              let player = Self.players[self] ?? load() else { return }
        player.currentTime = 0
        player.play()
    }

    private func load() -> AVAudioPlayer? {
        guard let asset = NSDataAsset(name: rawValue),
              let player = try? AVAudioPlayer(data: asset.data, fileTypeHint: AVFileType.m4a.rawValue) else { return nil }
        // Metade do volume original — os sons dos jogos estavam altos demais.
        player.volume = 0.5
        player.prepareToPlay()
        Self.players[self] = player
        return player
    }
}

/// Estado dos minijogos dividido entre o aquário (`WaterHeaderView`, que desenha o jogo e
/// decide quando ele roda) e a Home (`HomeView`, onde ficam os botões do jogo). O `RootView`
/// cria um só e o passa pelo ambiente pros dois.
@MainActor
@Observable
final class MiniGameController {
    @ObservationIgnored let ringGame = RingGameSimulation()
    @ObservationIgnored let jumpGame = JumpGameSimulation()
    @ObservationIgnored let pebbleGame = PebbleGameSimulation()
    @ObservationIgnored let flappyGame = FlappyGameSimulation()
    @ObservationIgnored let mazeGame = MazeGameSimulation()
    @ObservationIgnored let sliceGame = SliceGameSimulation()
    @ObservationIgnored let snakeGame = SnakeGameSimulation()
    @ObservationIgnored let minesGame = MinesGameSimulation()
    @ObservationIgnored let runnerGame = RunnerGameSimulation()
    /// Jogo rodando no aquário agora (meta batida e um jogo de verdade escolhido) — quem
    /// define é o `WaterHeaderView`.
    var runningGame: MiniGame?
    /// O usuário tocou num jogo na aba de minijogos pra jogar agora, mesmo sem a meta batida.
    /// Acaba ao sair do jogo pela seta do aquário ou ao escolher "Sem jogo".
    var playsOnDemand = false
    /// Alguma animação do mascote está rodando (montagem do início do dia, bolhas de troca de
    /// estágio, explosão da meta batida) — quem define é o `WaterHeaderView`. Enquanto isso os
    /// botões do aquário e da Home não respondem ao toque.
    var isMascotAnimating = false

    /// Botões do jogo no lugar dos cartões de ingestão.
    var showsGameControls: Bool { runningGame != nil }
}

/// Aba aberta pelo botão de minijogos no aquário: lista os jogos e, com um toque, escolhe
/// qual aparece quando a meta do dia for batida e já começa a jogá-lo no aquário (com pelo
/// menos `MiniGame.minimumStreakToPlay` dias de streak). Jogos ainda bloqueados (streak abaixo
/// de `MiniGame.requiredStreak`) aparecem com cadeado e não respondem ao toque.
struct MiniGamesView: View {
    let streak: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(MiniGameController.self) private var miniGames
    @AppStorage(MiniGame.selectedStorageKey) private var selectedRaw = ""

    private var canPlay: Bool { streak >= MiniGame.minimumStreakToPlay }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var activeGame: MiniGame { MiniGame.active(selected: selectedRaw, streak: streak) }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Toque num jogo pra jogar agora. Ele também entra quando você bate a meta do dia, e cada dia de streak libera jogos novos!")
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if !canPlay {
                    Label("Você precisa de pelo menos \(MiniGame.minimumStreakToPlay) dia de streak pra jogar. Bata a meta de hoje pra começar!",
                          systemImage: "lock.fill")
                        .font(.custom("Nunito", size: 14).weight(.bold))
                        .foregroundStyle(Color.appAccentText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(MiniGame.allCases) { game in
                        MiniGameItemButton(
                            game: game,
                            isUnlocked: game.isUnlocked(streak: streak),
                            isSelected: activeGame == game,
                            canPlay: canPlay
                        ) {
                            select(game)
                        }
                    }
                }
                .padding(20)
            }
            .appScreenBackground()
            .navigationTitle("Minijogos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Escolhe o jogo; com streak suficiente, fecha a aba e ele começa no aquário na hora.
    /// "Sem jogo" encerra uma partida que estivesse rolando fora da meta batida.
    private func select(_ game: MiniGame) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedRaw = game.rawValue }
        guard game.isPlayable else {
            miniGames.playsOnDemand = false
            return
        }
        guard canPlay else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { miniGames.playsOnDemand = true }
        dismiss()
    }
}

/// Cartão de um jogo: toque escolhe o jogo. Escolhido = borda e selo azuis.
/// Bloqueado = apagado, com cadeado e o requisito no lugar da descrição.
private struct MiniGameItemButton: View {
    let game: MiniGame
    let isUnlocked: Bool
    let isSelected: Bool
    let canPlay: Bool
    let onSelect: () -> Void

    private var showsSelected: Bool { isUnlocked && isSelected }

    private var lockedText: String {
        "Desbloqueie com \(game.requiredStreak) \(game.requiredStreak == 1 ? "dia" : "dias") de streak"
    }

    var body: some View {
        Button {
            if isSelected { Haptic.tap.play() } else { Haptic.primary.play() }
            onSelect()
        } label: {
            VStack(spacing: 10) {
                MiniGameIcon(game: game)
                    .foregroundStyle(isUnlocked ? AnyShapeStyle(LinearGradient.waterHeader) : AnyShapeStyle(Color.appSecondary))
                    .frame(height: 56)
                    .opacity(isUnlocked ? 1 : 0.4)
                Text(game.title)
                    .font(.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundStyle(isUnlocked ? Color.primary : Color.appSecondary)
                Text(isUnlocked ? game.subtitle : lockedText)
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(showsSelected ? AnyShapeStyle(LinearGradient.waterHeader) : AnyShapeStyle(.clear), lineWidth: 3)
            }
            .overlay(alignment: .topTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                        .padding(12)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.appAccent)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityLabel(game.title)
        .accessibilityValue(isUnlocked ? (isSelected ? "Escolhido" : "Não escolhido") : "Bloqueado")
        .accessibilityHint(isUnlocked ? (game.isPlayable ? (canPlay ? "Toque para jogar agora" : "Toque para jogar este quando bater a meta") : "Toque para não jogar nada quando bater a meta") : lockedText)
    }
}

/// Ícone do jogo na aba de minijogos, na cor do `foregroundStyle` (como um SF Symbol), com o
/// gradiente cobrindo o quadro todo do ícone. Cada jogo tem um desenho com a cena dele; só o
/// "Sem jogo" e as Pedras Coloridas usam o `systemImage`.
private struct MiniGameIcon: View {
    let game: MiniGame

    var body: some View {
        switch game {
        case .noGame, .pebbles:
            Image(systemName: game.systemImage)
                .font(.system(size: 36, weight: .semibold))
        default:
            Rectangle()
                .fill(.foreground)
                .mask {
                    Canvas { ctx, size in
                        // Desenho num quadrado de 1×1 centrado; os recortes (furos, olhos, vãos entre
                        // as peças) apagam o que já foi pintado, então a cena fica numa cor só.
                        let side = min(size.width, size.height)
                        ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
                        ctx.scaleBy(x: side, y: side)
                        Self.draw(game, in: &ctx)
                    }
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
        }
    }

    private static func draw(_ game: MiniGame, in ctx: inout GraphicsContext) {
        switch game {
        case .rings: drawRings(in: &ctx)
        case .jump: drawJump(in: &ctx)
        case .flappy: drawFlappy(in: &ctx)
        case .maze: drawMaze(in: &ctx)
        case .slice: drawSlice(in: &ctx)
        case .snake: drawSnake(in: &ctx)
        case .mines: drawMines(in: &ctx)
        case .runner: drawRunner(in: &ctx)
        case .noGame, .pebbles: break
        }
    }

    /// Tinta da máscara: o que for pintado com ela aparece na cor do ícone.
    private static let ink = GraphicsContext.Shading.color(.black)

    /// Vão entre peças sobrepostas, pra uma não grudar na outra.
    private static let gap: CGFloat = 0.035

    private static func fill(_ path: Path, in ctx: inout GraphicsContext) {
        ctx.fill(path, with: ink)
    }

    /// Apaga `path` (mais o vão em volta) do que já foi pintado.
    private static func cut(_ path: Path, outline: CGFloat = gap, in ctx: inout GraphicsContext) {
        var eraser = ctx
        eraser.blendMode = .destinationOut
        eraser.fill(path, with: .color(.black))
        if outline > 0 { eraser.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: outline * 2, lineJoin: .round)) }
    }

    /// Pinta `path` com um vão em volta, por cima do que já foi pintado.
    private static func layer(_ path: Path, in ctx: inout GraphicsContext) {
        cut(path, in: &ctx)
        fill(path, in: &ctx)
    }

    /// Contorno arredondado e irregular de pedrinha, passando pelo meio de cada lado do polígono.
    private static func pebble(center c: CGPoint, radiusX rx: CGFloat, radiusY ry: CGFloat, jitter: [CGFloat]) -> Path {
        let points = jitter.indices.map { i in
            let angle = CGFloat(i) / CGFloat(jitter.count) * 2 * .pi - .pi / 2
            return CGPoint(x: c.x + cos(angle) * rx * jitter[i], y: c.y + sin(angle) * ry * jitter[i])
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        path.move(to: mid(points[points.count - 1], points[0]))
        for i in points.indices {
            path.addQuadCurve(to: mid(points[i], points[(i + 1) % points.count]), control: points[i])
        }
        path.closeSubpath()
        return path
    }

    /// Argolas: o pino com duas argolas enfiadas, o pino passando por dentro delas.
    private static func drawRings(in ctx: inout GraphicsContext) {
        let rings = [CGRect(x: 0.17, y: 0.6, width: 0.66, height: 0.22), CGRect(x: 0.17, y: 0.4, width: 0.66, height: 0.22)]
        let band: CGFloat = 0.085
        // Metade de trás (de cima) de cada argola: fica atrás do pino.
        for ring in rings {
            var back = ctx
            back.clip(to: Path(CGRect(x: 0, y: 0, width: 1, height: ring.midY)))
            back.stroke(Path(ellipseIn: ring), with: ink, lineWidth: band)
        }

        var post = Path(roundedRect: CGRect(x: 0.445, y: 0.16, width: 0.11, height: 0.74), cornerRadius: 0.03)
        post.addEllipse(in: CGRect(x: 0.42, y: 0.06, width: 0.16, height: 0.16))
        layer(post, in: &ctx)
        fill(Path(roundedRect: CGRect(x: 0.16, y: 0.86, width: 0.68, height: 0.09), cornerRadius: 0.045), in: &ctx)

        // Metade da frente (de baixo): passa por cima do pino. A tinta começa um pouco acima do
        // meio pra emendar com a metade de trás sem deixar risco nas pontas.
        for ring in rings {
            let ellipse = Path(ellipseIn: ring)
            var eraser = ctx
            eraser.clip(to: Path(CGRect(x: 0, y: ring.midY, width: 1, height: 1 - ring.midY)))
            eraser.blendMode = .destinationOut
            eraser.stroke(ellipse, with: .color(.black), lineWidth: band + gap * 2)
            var front = ctx
            front.clip(to: Path(CGRect(x: 0, y: ring.midY - 0.02, width: 1, height: 1 - ring.midY + 0.02)))
            front.stroke(ellipse, with: ink, lineWidth: band)
        }
    }

    /// Gota Saltitante: a gota com olhinhos pulando em cima de uma laje de pedra.
    private static func drawJump(in ctx: inout GraphicsContext) {
        // Laje facetada, com um risco separando a face de cima.
        var slab = Path()
        slab.addLines([CGPoint(x: 0.13, y: 0.8), CGPoint(x: 0.24, y: 0.75), CGPoint(x: 0.5, y: 0.735), CGPoint(x: 0.77, y: 0.75),
                       CGPoint(x: 0.88, y: 0.79), CGPoint(x: 0.83, y: 0.88), CGPoint(x: 0.6, y: 0.92), CGPoint(x: 0.32, y: 0.91), CGPoint(x: 0.17, y: 0.87)])
        slab.closeSubpath()
        fill(slab, in: &ctx)
        var facet = Path()
        facet.addLines([CGPoint(x: 0.27, y: 0.805), CGPoint(x: 0.5, y: 0.795), CGPoint(x: 0.73, y: 0.805)])
        var eraser = ctx
        eraser.blendMode = .destinationOut
        eraser.stroke(facet, with: .color(.black), style: StrokeStyle(lineWidth: 0.025, lineCap: .round, lineJoin: .round))

        let r: CGFloat = 0.17
        let c = CGPoint(x: 0.5, y: 0.52)
        let drop = dropPath(center: c, radius: r)
        fill(drop, in: &ctx)

        // Olhinhos recortados.
        for dx: CGFloat in [-0.055, 0.055] {
            cut(Path(ellipseIn: CGRect(x: c.x + dx - 0.024, y: c.y - 0.05, width: 0.048, height: 0.068)), outline: 0, in: &ctx)
        }

        // Risquinhos de pulo nos dois lados, entre a gota e a laje.
        var lines = Path()
        for side: CGFloat in [-1, 1] {
            lines.move(to: CGPoint(x: 0.5 + side * 0.25, y: 0.66))
            lines.addLine(to: CGPoint(x: 0.5 + side * 0.32, y: 0.6))
        }
        ctx.stroke(lines, with: ink, style: StrokeStyle(lineWidth: 0.045, lineCap: .round))
    }

    /// Cobrinha: a cobra de pedrinhas indo pra direita, com uma pedrinha na frente.
    private static func drawSnake(in ctx: inout GraphicsContext) {
        // Do rabo pra cabeça, cada pedra por cima da de trás.
        let body: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0.07, y: 0.56), 0.05),
            (CGPoint(x: 0.17, y: 0.63), 0.06),
            (CGPoint(x: 0.3, y: 0.66), 0.07),
            (CGPoint(x: 0.44, y: 0.62), 0.08),
        ]
        for (i, (center, r)) in body.enumerated() {
            let jitter: [CGFloat] = (0..<7).map { 0.88 + 0.12 * CGFloat(($0 * 5 + i * 3) % 7) / 6 }
            layer(pebble(center: center, radiusX: r, radiusY: r, jitter: jitter), in: &ctx)
        }

        let head = CGPoint(x: 0.6, y: 0.52)
        layer(pebble(center: head, radiusX: 0.125, radiusY: 0.12, jitter: [1, 0.95, 1, 0.97, 0.94, 1, 0.96, 0.98]), in: &ctx)
        // Olhos olhando pra frente (direita).
        for dy: CGFloat in [-0.048, 0.048] {
            cut(Path(ellipseIn: CGRect(x: head.x + 0.03, y: head.y + dy - 0.028, width: 0.056, height: 0.056)), outline: 0, in: &ctx)
        }

        fill(pebble(center: CGPoint(x: 0.89, y: 0.52), radiusX: 0.075, radiusY: 0.07, jitter: [1, 0.86, 0.98, 0.9, 1, 0.88, 0.95]), in: &ctx)
    }

    /// Gota da `DropDrawing` (círculo embaixo com centro em `c`, ponta em cima), girada por `angle`.
    private static func dropPath(center c: CGPoint, radius r: CGFloat, angle: Angle = .zero) -> Path {
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -r * 2.1))
        drop.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.35, y: -r * 1.5), control2: CGPoint(x: r, y: -r * 0.8))
        drop.addArc(center: .zero, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        drop.addCurve(to: CGPoint(x: 0, y: -r * 2.1), control1: CGPoint(x: -r, y: -r * 0.8), control2: CGPoint(x: -r * 0.35, y: -r * 1.5))
        drop.closeSubpath()
        return drop.applying(CGAffineTransform(rotationAngle: angle.radians).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }

    /// Gota Voadora: a gota passando pelo vão entre duas pilhas de pedras.
    private static func drawFlappy(in ctx: inout GraphicsContext) {
        let stones: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 0.64, y: 0.11), 0.12, 0.08),
            (CGPoint(x: 0.62, y: 0.26), 0.11, 0.075),
            (CGPoint(x: 0.63, y: 0.76), 0.11, 0.075),
            (CGPoint(x: 0.65, y: 0.91), 0.12, 0.08),
        ]
        for (i, (center, rx, ry)) in stones.enumerated() {
            let jitter: [CGFloat] = (0..<7).map { 0.86 + 0.14 * CGFloat(($0 * 4 + i * 5) % 7) / 6 }
            layer(pebble(center: center, radiusX: rx, radiusY: ry, jitter: jitter), in: &ctx)
        }

        // Gota deitada, com a ponta pra trás (esquerda), indo pra direita pelo vão.
        let c = CGPoint(x: 0.58, y: 0.51)
        layer(dropPath(center: c, radius: 0.11, angle: .degrees(-80)), in: &ctx)
        cut(Path(ellipseIn: CGRect(x: c.x + 0.025, y: c.y - 0.05, width: 0.045, height: 0.06)), outline: 0, in: &ctx)

        // Risquinhos de velocidade atrás dela.
        var lines = Path()
        for (y, start) in [(0.42, 0.14), (0.52, 0.06), (0.62, 0.14)] as [(CGFloat, CGFloat)] {
            lines.move(to: CGPoint(x: start, y: y))
            lines.addLine(to: CGPoint(x: start + 0.14, y: y))
        }
        ctx.stroke(lines, with: ink, style: StrokeStyle(lineWidth: 0.045, lineCap: .round))
    }

    /// Rim Comilão: um labirinto de 4×4 casas, com entrada em cima e saída embaixo, e as gotinhas
    /// pelo corredor.
    private static func drawMaze(in ctx: inout GraphicsContext) {
        let origin: CGFloat = 0.12
        let cell: CGFloat = 0.19
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin + x * cell, y: origin + y * cell) }
        let walls: [[(CGFloat, CGFloat)]] = [
            [(1, 0), (4, 0), (4, 4), (3, 4)],
            [(2, 4), (0, 4), (0, 0)],
            [(1, 1), (1, 3), (2, 3)],
            [(2, 0), (2, 2), (3, 2)],
            [(3, 1), (4, 1)],
            [(3, 3), (3, 4)],
        ]
        var path = Path()
        for wall in walls {
            path.addLines(wall.map { point($0.0, $0.1) })
        }
        ctx.stroke(path, with: ink, style: StrokeStyle(lineWidth: 0.065, lineCap: .round, lineJoin: .round))

        for (x, y) in [(0.5, 2.5), (1.5, 0.5), (1.5, 1.5), (2.5, 2.5)] as [(CGFloat, CGFloat)] {
            let c = point(x, y)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 0.03, y: c.y - 0.03, width: 0.06, height: 0.06)), with: ink)
        }
    }

    /// Campo Minado: um pedaço do campo 3×3 — casas fechadas, uma com bandeira, uma aberta e
    /// vazia, e uma aberta com a pedra que estava escondida.
    private static func drawMines(in ctx: inout GraphicsContext) {
        let tile: CGFloat = 0.27, spacing: CGFloat = 0.045, start: CGFloat = 0.065
        func cell(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: start + CGFloat(x) * (tile + spacing), y: start + CGFloat(y) * (tile + spacing), width: tile, height: tile)
        }
        let open: Set<[Int]> = [[0, 2], [1, 1]]
        for y in 0..<3 {
            for x in 0..<3 {
                let rect = cell(x, y)
                if open.contains([x, y]) {
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.016, dy: 0.016), cornerRadius: 0.05), with: ink, lineWidth: 0.032)
                } else {
                    fill(Path(roundedRect: rect, cornerRadius: 0.06), in: &ctx)
                }
            }
        }

        // Bandeira recortada na casa de cima à direita.
        let flagCell = cell(2, 0)
        var flag = Path()
        let poleX = flagCell.minX + tile * 0.36
        flag.addRect(CGRect(x: poleX - 0.012, y: flagCell.minY + tile * 0.18, width: 0.024, height: tile * 0.62))
        flag.move(to: CGPoint(x: poleX, y: flagCell.minY + tile * 0.16))
        flag.addLine(to: CGPoint(x: poleX + tile * 0.42, y: flagCell.minY + tile * 0.32))
        flag.addLine(to: CGPoint(x: poleX, y: flagCell.minY + tile * 0.48))
        flag.closeSubpath()
        flag.addRect(CGRect(x: poleX - tile * 0.2, y: flagCell.maxY - tile * 0.22, width: tile * 0.4, height: 0.026))
        cut(flag, outline: 0, in: &ctx)

        // Pedra na casa do meio, aberta.
        let stoneCell = cell(1, 1)
        fill(pebble(center: CGPoint(x: stoneCell.midX, y: stoneCell.midY), radiusX: tile * 0.3, radiusY: tile * 0.27,
                    jitter: [1, 0.86, 0.98, 0.9, 1, 0.88, 0.95]), in: &ctx)
    }

    /// Gota Surfista: a gota com olhinhos na prancha, numa pista que some no horizonte.
    private static func drawRunner(in ctx: inout GraphicsContext) {
        // Bordas da pista e a faixa do meio, afinando pro fundo.
        var edges = Path()
        edges.move(to: CGPoint(x: 0.04, y: 0.96))
        edges.addLine(to: CGPoint(x: 0.4, y: 0.12))
        edges.move(to: CGPoint(x: 0.96, y: 0.96))
        edges.addLine(to: CGPoint(x: 0.6, y: 0.12))
        ctx.stroke(edges, with: ink, style: StrokeStyle(lineWidth: 0.05, lineCap: .round))
        for (top, bottom, width) in [(0.12, 0.2, 0.024), (0.27, 0.37, 0.034)] as [(CGFloat, CGFloat, CGFloat)] {
            fill(Path(roundedRect: CGRect(x: 0.5 - width / 2, y: top, width: width, height: bottom - top), cornerRadius: width / 2), in: &ctx)
        }

        let board = Path(ellipseIn: CGRect(x: 0.27, y: 0.8, width: 0.46, height: 0.12))
        layer(board, in: &ctx)
        let r: CGFloat = 0.15
        let c = CGPoint(x: 0.5, y: 0.8 - r)
        layer(dropPath(center: c, radius: r), in: &ctx)
        for dx: CGFloat in [-0.05, 0.05] {
            cut(Path(ellipseIn: CGRect(x: c.x + dx - 0.022, y: c.y - 0.045, width: 0.044, height: 0.062)), outline: 0, in: &ctx)
        }
    }

    /// Quebra-Pedras: uma pedra cortada ao meio, as metades se afastando, com o rastro do corte
    /// passando entre elas.
    private static func drawSlice(in ctx: inout GraphicsContext) {
        let center = CGPoint(x: 0.5, y: 0.52)
        let stone = pebble(center: .zero, radiusX: 0.3, radiusY: 0.27, jitter: [1, 0.9, 0.98, 0.88, 1, 0.92, 0.97, 0.9])
        let cutAngle = Angle.degrees(-38)
        // Cada metade: a pedra cortada na reta do corte (no espaço girado) e empurrada pro lado dela.
        for side: CGFloat in [-1, 1] {
            var half = ctx
            half.translateBy(x: center.x, y: center.y)
            half.rotate(by: cutAngle)
            half.translateBy(x: side * 0.03, y: side * 0.1)
            half.rotate(by: .degrees(Double(side) * 14))
            half.clip(to: Path(CGRect(x: -0.5, y: side > 0 ? 0 : -0.5, width: 1, height: 0.5)))
            half.fill(stone, with: ink)
        }

        // Rastro: vem de baixo, fino na cauda e mais grosso perto da ponta, ao longo da reta do corte.
        let direction = CGVector(dx: cos(cutAngle.radians), dy: sin(cutAngle.radians))
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let samples = 24
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let along = (t - 0.62) * 0.95
            let bend = -0.06 * (1 - pow(2 * t - 1, 2))
            let width = 0.045 * pow(t, 1.5) * pow(1 - t, 0.35)
            let base = CGPoint(x: center.x + direction.dx * along + normal.dx * bend, y: center.y + direction.dy * along + normal.dy * bend)
            top.append(CGPoint(x: base.x + normal.dx * width, y: base.y + normal.dy * width))
            bottom.append(CGPoint(x: base.x - normal.dx * width, y: base.y - normal.dy * width))
        }
        var trail = Path()
        trail.addLines(top + bottom.reversed())
        trail.closeSubpath()
        layer(trail, in: &ctx)
    }
}

/// Aviso no topo do aquário quando a streak libera um jogo novo.
struct MiniGameUnlockedBanner: View {
    let game: MiniGame

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(Color.appAccentText)
            VStack(alignment: .leading, spacing: 0) {
                Text("Novo minijogo liberado!")
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(Color.appSecondary)
                Text(game.title)
                    .font(.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MiniGamesView(streak: 0)
        .environment(MiniGameController())
}
