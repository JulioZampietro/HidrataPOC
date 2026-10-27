import simd
import SwiftUI

/// Valores do Rim Comilão para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum MazeGameTuning {
    /// O labirinto, uma linha por fileira: `#` pedra, `.` gotinha, `o` gotona (deixa as pedras
    /// com medo), `-` porta da casinha das pedras, `G` casinha, `P` início do rim, espaço =
    /// corredor vazio. Fileira com corredor nas duas bordas é túnel: sai de um lado, entra do outro.
    static let layout: [String] = [
        "###############",
        "#......#......#",
        "#.##.#.#.#.##.#",
        "#o...........o#",
        "#.##.##.##.##.#",
        "#....#...#....#",
        "####.##-##.####",
        "    .#GGG#.    ",
        "####.#####.####",
        "#......#......#",
        "#.##.......##.#",
        "#o.#.##.##.#.o#",
        "#....#.P.#....#",
        "#.#####.#####.#",
        "#.............#",
        "###############",
    ]
    /// Casa logo acima da porta, onde as pedras saem da casinha (e pra onde voltam depois de comidas).
    static let houseExit = SIMD2<Int>(7, 5)

    static let topMargin: Float = 58             // pt — abaixo dos botões do cabeçalho do aquário
    static let bottomMargin: Float = 14          // pt

    // Velocidades, em casas por segundo
    static let playerSpeed: Float = 5.2
    static let rockSpeed: Float = 4.3
    static let scaredSpeed: Float = 2.8
    static let eatenSpeed: Float = 9

    static let powerDuration: Float = 6          // s com as pedras com medo depois de uma gotona…
    static let powerWarning: Float = 2           // …piscando nos últimos segundos
    static let firstRelease: Float = 0.6         // s até a primeira pedra sair da casinha
    static let releaseInterval: Float = 3        // s entre uma pedra e a próxima
    static let eatenReturnDelay: Float = 1.5     // s que a pedra comida espera na casinha
    static let catchDistance: Float = 0.6        // casas entre o rim e a pedra pra contar a batida
    static let lives = 3

    static let deathPause: Float = 1.4           // s da animação do rim sendo pego
    static let victoryTapLock: Float = 1.0       // s de confete antes de um toque poder recomeçar
    static let gameOverPause: Float = 1.8        // s mostrando "fim de jogo" antes de recomeçar

    static let pelletPoints = 10
    static let powerPoints = 50
    static let rockPoints = 200                  // dobra a cada pedra comida com a mesma gotona
    static let powerWaterPush: Float = 4         // agito na superfície ao comer gotona ou pedra
}

enum MazeDirection: Int, CaseIterable, Sendable {
    case up, down, left, right

    var delta: SIMD2<Int> {
        switch self {
        case .up: SIMD2(0, -1)
        case .down: SIMD2(0, 1)
        case .left: SIMD2(-1, 0)
        case .right: SIMD2(1, 0)
        }
    }

    var vector: SIMD2<Float> { SIMD2(Float(delta.x), Float(delta.y)) }

    var opposite: MazeDirection {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct MazeGameSnapshot: Sendable {
    enum Phase: Sendable { case ready, playing, dying, victory, gameOver }

    enum RockLook: Sendable { case normal, scared, flashing, eaten }

    struct Rock: Sendable {
        let position: CGPoint
        let index: Int          // qual das quatro pedras (escolhe a imagem do mascote)
        let look: RockLook
    }

    let tile: CGFloat
    let walls: [CGRect]
    let door: CGRect
    /// Casinha das pedras (dentro dela não tem parede desenhada, só um fundo).
    let house: CGRect
    let pellets: [CGPoint]
    let powers: [CGPoint]
    let player: CGPoint
    let playerFacing: CGFloat   // −1 esquerda, 1 direita
    let mouthOpen: CGFloat      // 0…1
    let rocks: [Rock]
    let score: Int
    let lives: Int
    let confetti: [Confetto]
    let phase: Phase
    let phaseProgress: CGFloat  // 0…1 dentro de `dying` e `gameOver`
}

/// Pac-Man dentro do aquário: o rim percorre o labirinto comendo as gotinhas d'água, e quatro
/// pedras (o mascote) o perseguem. Comer uma gotona deixa as pedras com medo por um tempo, e aí
/// é o rim que pode comê-las. Limpar todas as gotas termina o jogo com confete e "Parabéns!" (um toque
/// recomeça); ser pego custa uma vida, e sem vidas é fim de jogo. A partida começa com o primeiro deslize/botão.
/// Tudo anda em casas do labirinto (`pos` em casas, centro da casa em `n + 0,5`); o tamanho em pt
/// só entra no desenho, então o aquário pode esticar sem bagunçar a partida.
@MainActor
final class MazeGameSimulation {
    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    private struct Mover {
        var pos: SIMD2<Float>
        var dir: MazeDirection?
    }

    private enum RockState {
        case waiting(Float)     // na casinha, s até sair
        case chasing
        case scared
        case eaten              // voltando pra casinha
    }

    private struct Rock {
        var mover: Mover
        var state: RockState
        let index: Int
    }

    private(set) var isRunning = false
    /// Pontos da partida atual.
    private(set) var score = 0
    /// Chamado quando acabam as vidas — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?
    /// Chamado quando o jogo termina com o "Parabéns!" — com os pontos da partida (o recorde também vale).
    var onVictory: ((Int) -> Void)?

    private let columns: Int
    private let rows: Int
    private var walls: Set<Cell> = []
    private var houseCells: Set<Cell> = []
    private var door = Cell(x: 0, y: 0)
    private var playerStart = Cell(x: 0, y: 0)
    private var initialPellets: Set<Cell> = []
    private var initialPowers: Set<Cell> = []

    private var phase: MazeGameSnapshot.Phase = .ready
    private var phaseTimer: Float = 0
    private var phaseDuration: Float = 1
    private var pellets: Set<Cell> = []
    private var powers: Set<Cell> = []
    private var player = Mover(pos: .zero, dir: nil)
    private var desired: MazeDirection?
    /// Segunda direção, quando o joystick aponta na diagonal (ex.: cima + direita): o rim vira
    /// pra qualquer uma das duas que abrir primeiro.
    private var desiredAlternate: MazeDirection?
    private var facing: Float = 1
    private var chompClock: Float = 0
    private var rocks: [Rock] = []
    private var powerTimer: Float = 0
    private var rockCombo = 0
    private var lives = MazeGameTuning.lives
    private var confetti = ConfettiShower()
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero
    /// Medida de uma casa e onde o labirinto começa na tela (pt), pro tamanho atual do aquário.
    private var tile: Float = 20
    private var origin: SIMD2<Float> = .zero
    private var wallRects: [CGRect] = []
    private var pendingWaterPush = false
    /// Distância andando pelo labirinto (em casas) de cada casa até um alvo, por alvo. As paredes
    /// não mudam, então cada alvo é calculado uma vez só.
    private var pathDistanceCache: [Cell: [Int]] = [:]

    init() {
        let layout = MazeGameTuning.layout
        rows = layout.count
        columns = layout.map(\.count).max() ?? 0
        for (y, line) in layout.enumerated() {
            for (x, char) in line.enumerated() {
                let cell = Cell(x: x, y: y)
                switch char {
                case "#": walls.insert(cell)
                case "G": walls.insert(cell); houseCells.insert(cell)
                case "-": walls.insert(cell); door = cell
                case ".": initialPellets.insert(cell)
                case "o": initialPowers.insert(cell)
                case "P": playerStart = cell
                default: break
                }
            }
        }
    }

    // MARK: Ciclo de vida

    func start() {
        guard !isRunning else { return }
        isRunning = true
        needsReset = true
        lastFrame = nil
    }

    func stop() {
        isRunning = false
        rocks.removeAll()
        confetti.clear()
        score = 0
        lastFrame = nil
    }

    /// Toque na tela de espera: começa a partida (o rim espera o primeiro comando de direção).
    func begin() {
        guard isRunning, !needsReset else { return }
        if phase == .victory { restartAfterVictory() }
        guard phase == .ready else { return }
        phase = .playing
    }

    /// Toque depois do "Parabéns!": partida nova (só vale depois de uns instantes de confete, pra
    /// um toque do fim da partida não pular a comemoração).
    private func restartAfterVictory() {
        guard phaseTimer >= MazeGameTuning.victoryTapLock else { return }
        reset()
        phase = .playing
    }

    /// Direção escolhida (deslize no aquário ou joystick); `alternate` é a outra metade de uma
    /// diagonal. Na tela de espera, também começa a partida. Dar meia-volta (na direção
    /// principal) vale na hora; virar pra um lado espera o rim chegar no meio de uma casa.
    func setDirection(_ direction: MazeDirection, alternate: MazeDirection? = nil) {
        guard isRunning, !needsReset else { return }
        if phase == .victory {
            restartAfterVictory()
            return
        }
        desired = direction
        desiredAlternate = alternate
        if phase == .ready { phase = .playing }
        if let current = player.dir, direction == current.opposite { reverse(&player) }
    }

    /// Partida nova: vidas cheias e labirinto cheio de gotas.
    private func reset() {
        needsReset = false
        score = 0
        lives = MazeGameTuning.lives
        confetti.clear()
        pellets = initialPellets
        powers = initialPowers
        resetPositions()
    }

    /// Rim no começo e pedras de volta na casinha, saindo uma de cada vez; espera o próximo toque.
    private func resetPositions() {
        phase = .ready
        player = Mover(pos: center(of: playerStart), dir: nil)
        desired = nil
        desiredAlternate = nil
        facing = 1
        powerTimer = 0
        rocks = (0..<4).map { index in
            Rock(mover: Mover(pos: housePosition(index), dir: nil),
                 state: .waiting(MazeGameTuning.firstRelease + Float(index) * MazeGameTuning.releaseInterval),
                 index: index)
        }
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito ao comer gotona ou pedra.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        if size != self.size { self.size = size; layout() }
        guard isRunning, size.width > 0, size.height > 0 else { return }
        if needsReset { reset() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date
        confetti.update(dt: dt)

        if pendingWaterPush {
            pendingWaterPush = false
            water.disturb(atU: (origin.x + player.pos.x * tile) / Float(size.width), strength: MazeGameTuning.powerWaterPush)
        }

        switch phase {
        case .ready:
            return
        case .playing:
            updatePlaying(dt: dt)
        case .victory:
            phaseTimer += dt
        case .dying, .gameOver:
            phaseTimer += dt
            guard phaseTimer >= phaseDuration else { return }
            finishPause()
        }
    }

    private func updatePlaying(dt: Float) {
        powerTimer = max(0, powerTimer - dt)
        if powerTimer == 0 {
            for i in rocks.indices { if case .scared = rocks[i].state { rocks[i].state = .chasing } }
        }

        let wasMoving = player.dir != nil
        let wishes = [desired, desiredAlternate].compactMap { $0 }
        move(&player, distance: MazeGameTuning.playerSpeed * dt) { cell, current in
            self.playerChoice(at: cell, wishes: wishes, current: current)
        }
        if let dir = player.dir {
            if dir == .left { facing = -1 } else if dir == .right { facing = 1 }
        }
        if wasMoving || player.dir != nil { chompClock += dt }
        eatPellets()
        if phase != .playing { return } // a fase acabou de ser limpa

        for i in rocks.indices { updateRock(i, dt: dt) }
        checkRockCollisions()
    }

    /// Vira pra direção desejada se der; senão segue reto; parede na frente, para. Numa diagonal
    /// (`wishes` com duas), prefere a que é curva: seguir reto já é o que o rim faz sozinho, então
    /// a diagonal serve pra pegar a primeira saída pro lado. Recebe as direções em vez de ler
    /// `player`, que está emprestado pro `move` enquanto ele roda.
    private func playerChoice(at cell: Cell, wishes: [MazeDirection], current: MazeDirection?) -> MazeDirection? {
        if let turn = wishes.first(where: { $0 != current && $0 != current?.opposite && isOpen(cell, $0) }) { return turn }
        if let wish = wishes.first(where: { isOpen(cell, $0) }) { return wish }
        if let current, isOpen(cell, current) { return current }
        return nil
    }

    private func eatPellets() {
        let cell = self.cell(at: player.pos)
        guard simd_distance(player.pos, center(of: cell)) < 0.35 else { return }
        if pellets.remove(cell) != nil {
            score += MazeGameTuning.pelletPoints
        } else if powers.remove(cell) != nil {
            score += MazeGameTuning.powerPoints
            powerTimer = MazeGameTuning.powerDuration
            rockCombo = 0
            for i in rocks.indices {
                if case .chasing = rocks[i].state {
                    rocks[i].state = .scared
                    reverse(&rocks[i].mover)
                }
            }
            pendingWaterPush = true
            Haptic.primary.play()
        }
        if pellets.isEmpty, powers.isEmpty {
            phase = .victory
            phaseTimer = 0
            confetti.burst(in: size, colorCount: PebbleGameTuning.colors.count)
            onVictory?(score)
        }
    }

    private func updateRock(_ i: Int, dt: Float) {
        switch rocks[i].state {
        case .waiting(let remaining):
            if remaining - dt <= 0 {
                rocks[i].state = powerTimer > 0 ? .scared : .chasing
                rocks[i].mover = Mover(pos: center(of: Cell(x: MazeGameTuning.houseExit.x, y: MazeGameTuning.houseExit.y)),
                                       dir: Bool.random() ? .left : .right)
            } else {
                rocks[i].state = .waiting(remaining - dt)
            }
        case .chasing:
            let target = chaseTarget(for: i)
            move(&rocks[i].mover, distance: MazeGameTuning.rockSpeed * dt) { cell, dir in
                self.rockChoice(at: cell, coming: dir, toward: target)
            }
        case .scared:
            move(&rocks[i].mover, distance: MazeGameTuning.scaredSpeed * dt) { cell, dir in
                self.rockChoice(at: cell, coming: dir, toward: nil)
            }
        case .eaten:
            let exit = Cell(x: MazeGameTuning.houseExit.x, y: MazeGameTuning.houseExit.y)
            // Para no meio da casa de saída (`nil`) pra ser recolhida pra dentro da casinha.
            move(&rocks[i].mover, distance: MazeGameTuning.eatenSpeed * dt) { cell, dir in
                cell == exit ? nil : self.rockChoice(at: cell, coming: dir, toward: exit)
            }
            if cell(at: rocks[i].mover.pos) == exit, simd_distance(rocks[i].mover.pos, center(of: exit)) < 0.1 {
                rocks[i].mover = Mover(pos: housePosition(rocks[i].index), dir: nil)
                rocks[i].state = .waiting(MazeGameTuning.eatenReturnDelay)
            }
        }
    }

    /// Cada pedra persegue de um jeito, pra não andarem todas grudadas: a 0 vai direto no rim,
    /// a 1 mira 4 casas à frente dele, a 2 só persegue de perto (de longe volta pro canto) e a 3
    /// alterna entre perseguir e andar à toa.
    private func chaseTarget(for i: Int) -> Cell? {
        let playerCell = cell(at: player.pos)
        switch rocks[i].index {
        case 0:
            return playerCell
        case 1:
            let ahead = (player.dir ?? desired)?.delta ?? .zero
            return Cell(x: playerCell.x + ahead.x * 4, y: playerCell.y + ahead.y * 4)
        case 2:
            let distance = simd_distance(rocks[i].mover.pos, player.pos)
            return distance > 6 ? playerCell : Cell(x: 1, y: rows - 2)
        default:
            return Int(chompClock / 4) % 2 == 0 ? playerCell : nil
        }
    }

    /// No meio de uma casa: segue pros lados abertos sem dar meia-volta (só num beco sem saída),
    /// escolhendo o que encurta o caminho até o alvo pelo labirinto (em linha reta as pedras
    /// ficavam presas em bolsões); alvo fora do labirinto usa a distância em linha reta; sem
    /// alvo, sorteia.
    private func rockChoice(at cell: Cell, coming dir: MazeDirection?, toward target: Cell?) -> MazeDirection? {
        var options = MazeDirection.allCases.filter { isOpen(cell, $0) && $0 != dir?.opposite }
        if options.isEmpty, let back = dir?.opposite, isOpen(cell, back) { options = [back] }
        guard let target else { return options.randomElement() }
        let distances = pathDistances(to: target)
        func cost(_ direction: MazeDirection) -> Int {
            let next = neighbor(of: cell, direction)
            if let distances { return distances[next.y * columns + next.x] }
            return distanceSquared(next, target)
        }
        return options.min { cost($0) < cost($1) }
    }

    /// Distâncias andando de cada casa até `target` (busca em largura), ou nil se o alvo é parede
    /// ou está fora do labirinto. Casa sem caminho fica com `Int.max`.
    private func pathDistances(to target: Cell) -> [Int]? {
        guard target.x >= 0, target.x < columns, target.y >= 0, target.y < rows, !walls.contains(target) else { return nil }
        if let cached = pathDistanceCache[target] { return cached }
        var distances = [Int](repeating: .max, count: columns * rows)
        distances[target.y * columns + target.x] = 0
        var queue = [target]
        var head = 0
        while head < queue.count {
            let cell = queue[head]
            head += 1
            let distance = distances[cell.y * columns + cell.x]
            for direction in MazeDirection.allCases where isOpen(cell, direction) {
                let next = neighbor(of: cell, direction)
                guard distances[next.y * columns + next.x] == .max else { continue }
                distances[next.y * columns + next.x] = distance + 1
                queue.append(next)
            }
        }
        pathDistanceCache[target] = distances
        return distances
    }

    /// A casa vizinha na direção, dando a volta no túnel.
    private func neighbor(of cell: Cell, _ direction: MazeDirection) -> Cell {
        Cell(x: (cell.x + direction.delta.x + columns) % columns, y: cell.y + direction.delta.y)
    }

    private func checkRockCollisions() {
        for i in rocks.indices {
            if case .waiting = rocks[i].state { continue }
            if case .eaten = rocks[i].state { continue }
            guard simd_distance(rocks[i].mover.pos, player.pos) < MazeGameTuning.catchDistance else { continue }
            if case .scared = rocks[i].state {
                rockCombo += 1
                score += MazeGameTuning.rockPoints << (rockCombo - 1)
                rocks[i].state = .eaten
                pendingWaterPush = true
                Haptic.success.play()
            } else {
                Haptic.warning.play()
                beginPause(.dying, duration: MazeGameTuning.deathPause)
                MiniGameSound.lifeLost.play()
                return
            }
        }
    }

    private func beginPause(_ pause: MazeGameSnapshot.Phase, duration: Float) {
        phase = pause
        phaseTimer = 0
        phaseDuration = duration
    }

    /// Fim de uma pausa: perdeu a vida ou o "fim de jogo" já foi mostrado.
    private func finishPause() {
        switch phase {
        case .dying:
            lives -= 1
            if lives <= 0 {
                beginPause(.gameOver, duration: MazeGameTuning.gameOverPause)
                onGameOver?(score)
            } else {
                resetPositions()
            }
        case .gameOver:
            reset()
        case .ready, .playing, .victory:
            break
        }
    }

    // MARK: Movimento no labirinto

    /// Anda `distance` casas na direção atual, parando em cada centro de casa pra `choose` decidir
    /// pra onde seguir (ou parar, devolvendo nil). Sem direção, pergunta antes de sair do lugar.
    private func move(_ mover: inout Mover, distance: Float, choose: (Cell, MazeDirection?) -> MazeDirection?) {
        var remaining = distance
        var guardSteps = 0
        while remaining > 1e-5, guardSteps < 8 {
            guardSteps += 1
            guard let dir = mover.dir else {
                mover.dir = choose(cell(at: mover.pos), nil)
                if mover.dir == nil { return }
                continue
            }
            let target = nextCenter(from: mover.pos, toward: dir)
            let gap = simd_distance(target, mover.pos)
            if remaining < gap {
                mover.pos += dir.vector * remaining
                wrap(&mover.pos)
                return
            }
            mover.pos = target
            wrap(&mover.pos)
            remaining -= gap
            mover.dir = choose(cell(at: mover.pos), dir)
            if mover.dir == nil { return }
        }
    }

    /// O próximo centro de casa à frente na direção (um centro está em `n + 0,5`); parado em cima
    /// de um centro, é o da casa seguinte. Sem folga de propósito: com uma folga, quem parava a
    /// um fio antes de um centro pulava ele, sem passar pelo `choose`, e entrava na parede.
    private func nextCenter(from pos: SIMD2<Float>, toward dir: MazeDirection) -> SIMD2<Float> {
        func ahead(_ p: Float, _ sign: Int) -> Float {
            sign > 0 ? (p - 0.5).rounded(.down) + 1.5 : (p - 0.5).rounded(.up) - 0.5
        }
        var target = pos
        if dir.delta.x != 0 { target.x = ahead(pos.x, dir.delta.x) }
        if dir.delta.y != 0 { target.y = ahead(pos.y, dir.delta.y) }
        return target
    }

    /// Meia-volta. Entre dois centros vale sempre (volta pra casa de onde veio, que é aberta);
    /// bem em cima de um centro, a direção acabou de ser escolhida ali e a de trás pode ser
    /// parede, então só vira se ela estiver aberta.
    private func reverse(_ mover: inout Mover) {
        guard let back = mover.dir?.opposite else { return }
        let here = cell(at: mover.pos)
        if simd_distance(mover.pos, center(of: here)) < 1e-3, !isOpen(here, back) { return }
        mover.dir = back
    }

    /// Túnel: passou da borda esquerda, aparece na direita (e vice-versa).
    private func wrap(_ pos: inout SIMD2<Float>) {
        let width = Float(columns)
        if pos.x < 0 { pos.x += width } else if pos.x >= width { pos.x -= width }
    }

    private func isOpen(_ cell: Cell, _ dir: MazeDirection) -> Bool {
        var next = Cell(x: cell.x + dir.delta.x, y: cell.y + dir.delta.y)
        guard next.y >= 0, next.y < rows else { return false }
        next.x = (next.x + columns) % columns
        return !walls.contains(next)
    }

    private func cell(at pos: SIMD2<Float>) -> Cell {
        Cell(x: (Int(pos.x.rounded(.down)) + columns) % columns, y: Int(pos.y.rounded(.down)))
    }

    private func center(of cell: Cell) -> SIMD2<Float> { SIMD2(Float(cell.x) + 0.5, Float(cell.y) + 0.5) }

    private func distanceSquared(_ a: Cell, _ b: Cell) -> Int {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    /// Onde cada pedra espera dentro da casinha (as quatro lado a lado).
    private func housePosition(_ index: Int) -> SIMD2<Float> {
        SIMD2(Float(door.x) - 0.6 + Float(index) * 0.8 - 0.2, Float(door.y) + 1.5)
    }

    // MARK: Medidas na tela

    private func layout() {
        let width = Float(size.width), height = Float(size.height)
        guard width > 0, height > 0 else { return }
        let available = height - MazeGameTuning.topMargin - MazeGameTuning.bottomMargin
        tile = max(1, min(width / Float(columns), available / Float(rows)))
        origin = SIMD2((width - tile * Float(columns)) / 2,
                       MazeGameTuning.topMargin + (available - tile * Float(rows)) / 2)
        wallRects = walls.filter { $0 != door && !houseCells.contains($0) }.map(rect(of:))
    }

    private func rect(of cell: Cell) -> CGRect {
        CGRect(x: CGFloat(origin.x + Float(cell.x) * tile), y: CGFloat(origin.y + Float(cell.y) * tile),
               width: CGFloat(tile), height: CGFloat(tile))
    }

    private func point(_ pos: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(origin.x + pos.x * tile), y: CGFloat(origin.y + pos.y * tile))
    }

    // MARK: Foto pra desenhar

    func snapshot() -> MazeGameSnapshot {
        let rocks = rocks.map { rock -> MazeGameSnapshot.Rock in
            let look: MazeGameSnapshot.RockLook = switch rock.state {
            case .waiting, .chasing: .normal
            case .scared:
                powerTimer < MazeGameTuning.powerWarning && Int(powerTimer * 6) % 2 == 0 ? .flashing : .scared
            case .eaten: .eaten
            }
            return MazeGameSnapshot.Rock(position: point(rock.mover.pos), index: rock.index, look: look)
        }
        let isPaused = phase == .dying || phase == .gameOver
        return MazeGameSnapshot(
            tile: CGFloat(tile),
            walls: wallRects,
            door: rect(of: door),
            house: houseCells.map(rect(of:)).reduce(CGRect.null) { $0.union($1) },
            pellets: pellets.map { point(center(of: $0)) },
            powers: powers.map { point(center(of: $0)) },
            player: point(player.pos),
            playerFacing: CGFloat(facing),
            mouthOpen: CGFloat(abs(sin(chompClock * 12))),
            rocks: rocks,
            score: score,
            lives: lives,
            confetti: confetti.snapshot(),
            phase: phase,
            phaseProgress: isPaused ? CGFloat(min(1, phaseTimer / phaseDuration)) : 0
        )
    }
}
