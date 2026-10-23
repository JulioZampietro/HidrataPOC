import simd
import SwiftUI

/// Valores do jogo das Pedras Coloridas para ajustar à mão (mesma ideia de `JumpGameTuning`).
enum PebbleGameTuning {
    // Grade de pedrinhas (colmeia: linhas alternadas deslocadas meia pedrinha)
    static let colorCount = 4
    /// Pedrinhas da mesma cor juntas (contando a atirada) pra estourar, por fase: limpar a grade
    /// inteira passa pra próxima; a última fase se repete. Perder volta pra primeira.
    static let minMatchByLevel = [3, 4, 5]
    static let targetDiameter: Float = 34        // pt — o diâmetro real se ajusta pra fechar colunas inteiras
    static let minColumns = 8
    static let maxColumns = 12
    static let minRowsToDanger: Float = 7        // linhas que precisam caber entre o topo e a linha de perigo
    static let initialRows = 4
    static let gridTop: Float = 60               // pt — abaixo dos botões do cabeçalho do aquário

    // Canhão
    static let shooterBottomInset: Float = 38    // pt do fundo do aquário até o centro do canhão
    static let aimLimit: Float = 1.3             // rad (~75°) pra cada lado da vertical
    static let aimSpeedMin: Float = 0.5          // rad/s logo que aperta (mira fina)
    static let aimSpeedMax: Float = 1.8          // rad/s segurando por mais tempo
    static let aimAcceleration: Float = 2.2      // rad/s² — quão rápido vai de uma à outra
    static let aimPulseStep: Float = 0.06        // rad por toque rápido (VoiceOver, toque sem segurar)
    static let shotSpeed: Float = 950            // pt/s
    static let fireCooldown: Float = 0.25        // s entre tiros (o toque rápido também manda um pulso)
    static let hitFraction: Float = 0.8          // gruda quando chega a essa fração do diâmetro de outra
    static let aimGuideLength: Float = 300       // pt de linha de mira
    static let touchAimGuideLength: Float = 600  // pt de linha de mira enquanto o dedo mira

    // Ritmo
    static let missesBeforeNewRow = 7            // tiros sem estourar nada até descer uma linha nova
    static let rowSlideSpeed: Float = 7          // 1/s — quão rápido a linha nova desliza pra baixo
    static let pointsPerPop = 10
    static let pointsPerDrop = 20                // pedrinhas que ficaram soltas e caíram valem mais
    static let clearBonus = 500
    static let gameOverPause: Float = 1.6        // s mostrando "fim de jogo" antes de recomeçar
    static let popWaterPush: Float = 5           // agito na superfície a cada estouro

    /// Cores das pedrinhas (índice = `colorIndex`). Sem azul, que some na água.
    static let colors: [Color] = [
        Color(red: 0.95, green: 0.30, blue: 0.32),
        Color(red: 1.00, green: 0.78, blue: 0.22),
        Color(red: 0.28, green: 0.80, blue: 0.44),
        Color(red: 0.66, green: 0.42, blue: 0.95),
        Color(red: 1.00, green: 0.50, blue: 0.75),
    ]
}

/// Para que lado o canhão está girando com os botões.
enum PebbleGameSide: Int, CaseIterable {
    case left, right
}

/// Foto imutável da simulação num frame — o `Canvas` desenha a partir dela.
struct PebbleGameSnapshot: Sendable {
    struct Pebble: Sendable {
        let position: CGPoint
        let colorIndex: Int
        /// Semente do formato da pedrinha: fica a mesma a vida toda, então ela não muda de cara.
        let seed: Int
        var scale: CGFloat = 1
        var alpha: CGFloat = 1
    }

    struct Spark: Sendable {
        let position: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    let radius: CGFloat
    let pebbles: [Pebble]           // grade + estourando + caindo
    let shot: Pebble?
    let sparks: [Spark]
    let shooter: CGPoint
    let aimAngle: CGFloat           // rad a partir da vertical, negativo = esquerda
    let aimGuide: [CGPoint]
    let isTouchAiming: Bool
    let loaded: Pebble
    let next: Pebble
    let dangerY: CGFloat
    let dangerLevel: CGFloat        // 0…1: quão perto a pedrinha mais baixa está da linha de perigo
    let shotsUntilNewRow: Int
    let score: Int
    /// Fase atual, a partir de 1, e quantas pedrinhas juntas estouram nela.
    let level: Int
    let minMatch: Int
    /// Esperando o primeiro toque da fase: a tela mostra "Fase N" e a mira fica parada.
    let isReady: Bool
    /// Limpou a última fase: mostra o "Parabéns!" e o confete até o toque que recomeça.
    let isCelebrating: Bool
    let confetti: [Confetto]
    let isGameOver: Bool
}

/// Bubble Shooter dentro do aquário, com pedrinhas coloridas no lugar das bolhas: elas ficam
/// presas no topo e um canhão no fundo atira uma por vez. Pra mirar, o dedo arrasta no aquário
/// (o canhão aponta pro dedo) e, ao soltar, atira; os botões da Home também giram e atiram. A
/// pedrinha atirada quica nas paredes e gruda na primeira que encostar; juntando `minMatch` (3, 4 e 5 pedrinhas
/// nas fases 1, 2 e 3) da mesma cor, elas estouram, e as que ficarem soltas do teto caem. A cada `missesBeforeNewRow`
/// tiros sem estourar nada desce uma linha nova; se alguma passar da linha de perigo é fim de
/// jogo, e outra partida começa logo depois. Física própria em Swift, no mesmo molde de
/// `JumpGameSimulation`.
@MainActor
final class PebbleGameSimulation {
    private struct Cell: Hashable {
        var row: Int
        var col: Int
    }

    private struct Stone: Equatable {
        let colorIndex: Int
        let seed: Int

        static func random(colors: [Int]? = nil) -> Stone {
            Stone(colorIndex: colors?.randomElement() ?? Int.random(in: 0..<PebbleGameTuning.colorCount),
                  seed: Int.random(in: 0..<1_000_000))
        }
    }

    private struct Shot {
        var position: SIMD2<Float>
        var direction: SIMD2<Float>
        let stone: Stone
    }

    /// Pedrinha estourando (cresce e some) ou caindo (solta do teto).
    private struct Loose {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        let stone: Stone
        var life: Float
        let lifetime: Float
        let isPopping: Bool
    }

    private struct Spark {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var radius: Float
        var life: Float
        let lifetime: Float
    }

    private(set) var isRunning = false
    /// Pontos da partida atual.
    private(set) var score = 0
    /// Chamado quando as pedrinhas passam da linha de perigo — com os pontos da partida que acabou.
    var onGameOver: ((Int) -> Void)?

    // Grade
    private var grid: [Cell: Stone] = [:]
    /// Alterna a cada linha nova que desce, pra cada linha manter o próprio deslocamento.
    private var rowParity = 0
    private var columns = 10
    private var diameter: Float = 34
    private var rowHeight: Float = 29
    private var gridLeft: Float = 0
    private var gridRight: Float = 0
    private var dangerY: Float = 0
    private var shooter: SIMD2<Float> = .zero
    /// Deslocamento visual (pt) da grade enquanto uma linha nova desliza pra dentro.
    private var slide: Float = 0

    // Canhão
    private var aim: Float = 0
    private var held = [Bool](repeating: false, count: PebbleGameSide.allCases.count)
    private var holdTime: Float = 0
    /// O dedo está no aquário mirando (a linha de mira fica mais comprida).
    private var isTouchAiming = false
    private var loaded = Stone.random()
    private var next = Stone.random()
    private var shot: Shot?
    private var fireCooldown: Float = 0
    private var misses = 0
    /// Fase atual a partir de 0 (índice de `PebbleGameTuning.minMatchByLevel`).
    private var levelIndex = 0
    private var minMatch: Int { PebbleGameTuning.minMatchByLevel[levelIndex] }
    /// Antes do primeiro toque de cada fase: mostra "Fase N" e o toque que sai dela não atira.
    private var isReady = true
    /// O toque que está no aquário começou na tela de espera e só serve pra sair dela.
    private var ignoresTouch = false
    /// Última fase limpa: "Parabéns!" fica na tela até o toque que recomeça pela fase 1.
    private var isVictory = false

    // Efeitos
    private var loose: [Loose] = []
    private var sparks: [Spark] = []
    private var confetti = ConfettiShower()

    private var gameOverTimer: Float = 0
    private var needsReset = true
    private var lastFrame: Date?
    private var size: CGSize = .zero
    private var layoutSize: CGSize = .zero

    private var radius: Float { diameter / 2 }

    // MARK: Ciclo de vida

    func start() {
        guard !isRunning else { return }
        isRunning = true
        needsReset = true
        lastFrame = nil
    }

    func stop() {
        isRunning = false
        grid.removeAll()
        loose.removeAll()
        sparks.removeAll()
        confetti.clear()
        isVictory = false
        shot = nil
        held = [Bool](repeating: false, count: PebbleGameSide.allCases.count)
        isTouchAiming = false
        score = 0
        lastFrame = nil
    }

    // MARK: Controles

    func setAim(_ side: PebbleGameSide, held isHeld: Bool) {
        if isHeld { beginIfReady() }
        held[side.rawValue] = isHeld
        if !held.contains(true) { holdTime = 0 }
    }

    /// Gira um pouquinho, pra quem aciona o botão sem segurar (VoiceOver, toque rápido).
    func pulseAim(_ side: PebbleGameSide) {
        beginIfReady()
        aim += (side == .left ? -1 : 1) * PebbleGameTuning.aimPulseStep
        aim = clampedAim(aim)
    }

    /// Dedo arrastando no aquário (`location` nas coordenadas do jogo): o canhão aponta pra ele.
    /// Com o dedo abaixo do canhão, a mira fica no limite do lado em que ele está.
    func touchAim(at location: CGPoint) {
        guard isRunning, !needsReset else { return }
        if isReady {
            beginIfReady()
            ignoresTouch = true
        }
        guard !ignoresTouch else { return }
        if !isTouchAiming { Haptic.selection.play() }
        isTouchAiming = true
        let dx = Float(location.x) - shooter.x
        let dy = max(shooter.y - Float(location.y), 1)
        aim = clampedAim(atan2(dx, dy))
    }

    /// Dedo solto: atira na última direção mirada. Soltar abaixo do canhão cancela o tiro.
    func touchRelease(at location: CGPoint) {
        if ignoresTouch {
            ignoresTouch = false
            return
        }
        guard isTouchAiming else { return }
        touchAim(at: location)
        isTouchAiming = false
        if Float(location.y) < shooter.y { fire() }
    }

    /// Atira a pedrinha do canhão, se não houver outra no ar.
    func fire() {
        guard isRunning, !needsReset, shot == nil, fireCooldown <= 0, gameOverTimer <= 0 else { return }
        // O primeiro toque da fase só tira o "Fase N" da tela.
        if isReady {
            beginIfReady()
            return
        }
        shot = Shot(position: shooter, direction: SIMD2(sin(aim), -cos(aim)), stone: loaded)
        loaded = next
        next = randomStone()
        fireCooldown = PebbleGameTuning.fireCooldown
        Haptic.tap.play()
    }

    /// Tira o "Fase N" (ou o "Parabéns!") da tela e libera o jogo.
    private func beginIfReady() {
        guard isReady else { return }
        isReady = false
        isVictory = false
        Haptic.tap.play()
    }

    /// Nova partida: mede a grade pro tamanho do aquário e enche as primeiras linhas.
    private func reset() {
        needsReset = false
        layoutSize = size
        let width = Float(size.width), height = Float(size.height)
        shooter = SIMD2(width / 2, height - PebbleGameTuning.shooterBottomInset)

        // Colunas inteiras com o diâmetro mais perto do desejado; se o aquário for baixo, as
        // pedrinhas encolhem até caberem `minRowsToDanger` linhas acima da linha de perigo.
        var d = width / Float(max(PebbleGameTuning.minColumns, min(PebbleGameTuning.maxColumns,
                                                                   Int((width / PebbleGameTuning.targetDiameter).rounded()))))
        let room = shooter.y - PebbleGameTuning.gridTop
        // room = 0,5 d (topo até o centro da 1ª linha) + (linhas − 1) × 0,866 d + 1,5 d (até o canhão)
        let fitting = room / (2 + (PebbleGameTuning.minRowsToDanger - 1) * 0.866)
        d = min(d, fitting)
        columns = min(PebbleGameTuning.maxColumns, Int(width / d))
        diameter = d
        rowHeight = d * 0.866
        gridLeft = (width - Float(columns) * d) / 2
        gridRight = width - gridLeft
        dangerY = shooter.y - d * 1.5

        score = 0
        misses = 0
        levelIndex = 0
        isReady = true
        ignoresTouch = false
        isVictory = false
        confetti.clear()
        rowParity = 0
        aim = 0
        shot = nil
        isTouchAiming = false
        gameOverTimer = 0
        loose.removeAll()
        sparks.removeAll()
        fillInitialRows()
        loaded = randomStone()
        next = randomStone()
    }

    /// Recoloca o canhão e a linha de perigo pra altura nova, mantendo a grade e o tamanho das pedrinhas.
    private func relayoutVertically() {
        layoutSize = size
        shooter.y = Float(size.height) - PebbleGameTuning.shooterBottomInset
        dangerY = shooter.y - diameter * 1.5
    }

    private func fillInitialRows() {
        grid.removeAll()
        let rows = PebbleGameTuning.initialRows
        for row in 0..<rows {
            for col in 0..<columnCount(row: row) {
                grid[Cell(row: row, col: col)] = .random()
            }
        }
        slide = Float(rows) * rowHeight + diameter
    }

    // MARK: Simulação

    /// Avança até `date`. `water` recebe o agito de cada estouro.
    func advance(to date: Date, size: CGSize, water: WaterMotion) {
        self.size = size
        guard isRunning, size.width > 0, size.height > 0 else { return }
        // Largura nova muda a grade inteira: recomeça. Só a altura (o aquário estica e encolhe
        // entre a tela do jogo e a de ingestão) só move o canhão, sem perder a partida.
        if needsReset || size.width != layoutSize.width { reset() } else if size.height != layoutSize.height { relayoutVertically() }
        guard let last = lastFrame else { lastFrame = date; return }
        let dt = Float(min(date.timeIntervalSince(last), 1.0 / 20.0))
        guard dt > 1e-4 else { return }
        lastFrame = date

        fireCooldown = max(0, fireCooldown - dt)
        slide *= exp(-PebbleGameTuning.rowSlideSpeed * dt)
        if slide < 0.3 { slide = 0 }
        updateLoose(dt: dt)
        updateSparks(dt: dt)
        confetti.update(dt: dt)

        if gameOverTimer > 0 {
            gameOverTimer -= dt
            if gameOverTimer <= 0 { reset() }
            return
        }

        updateAim(dt: dt)
        updateShot(dt: dt, water: water)
    }

    private func updateAim(dt: Float) {
        guard !isReady else { holdTime = 0; return }
        var direction: Float = 0
        if held[PebbleGameSide.left.rawValue] { direction -= 1 }
        if held[PebbleGameSide.right.rawValue] { direction += 1 }
        guard direction != 0 else { holdTime = 0; return }
        holdTime += dt
        let speed = min(PebbleGameTuning.aimSpeedMax, PebbleGameTuning.aimSpeedMin + PebbleGameTuning.aimAcceleration * holdTime)
        aim = clampedAim(aim + direction * speed * dt)
    }

    private func clampedAim(_ value: Float) -> Float {
        max(-PebbleGameTuning.aimLimit, min(PebbleGameTuning.aimLimit, value))
    }

    /// Anda com a pedrinha atirada em passos curtos (pra não atravessar outra), quicando nas
    /// paredes, até encostar no teto ou numa pedrinha da grade.
    private func updateShot(dt: Float, water: WaterMotion) {
        guard var current = shot else { return }
        var remaining = PebbleGameTuning.shotSpeed * dt
        while remaining > 0 {
            let step = min(remaining, radius * 0.5)
            remaining -= step
            current.position += current.direction * step
            reflectOffWalls(&current.position, direction: &current.direction)
            let hit = collidingCell(at: current.position)
            if hit != nil || current.position.y <= gridTopY + radius {
                shot = nil
                attach(current, touching: hit, water: water)
                return
            }
        }
        shot = current
    }

    private func reflectOffWalls(_ position: inout SIMD2<Float>, direction: inout SIMD2<Float>) {
        if position.x < gridLeft + radius {
            position.x = 2 * (gridLeft + radius) - position.x
            direction.x = abs(direction.x)
        } else if position.x > gridRight - radius {
            position.x = 2 * (gridRight - radius) - position.x
            direction.x = -abs(direction.x)
        }
    }

    private func collidingCell(at point: SIMD2<Float>) -> Cell? {
        let reach = diameter * PebbleGameTuning.hitFraction
        var best: (cell: Cell, distance: Float)?
        for cell in grid.keys {
            let distance = simd_distance(center(of: cell), point)
            if distance < reach, distance < best?.distance ?? .infinity { best = (cell, distance) }
        }
        return best?.cell
    }

    /// Gruda a pedrinha na célula livre mais perto, encostada na atingida (ou no teto), e
    /// resolve o que acontece: estouro, pedrinhas soltas caindo, linha nova, fim de jogo.
    private func attach(_ shot: Shot, touching hit: Cell?, water: WaterMotion) {
        var candidates = hit.map { neighbors(of: $0).filter { grid[$0] == nil } } ?? []
        if hit == nil || shot.position.y < gridTopY + radius + rowHeight / 2 {
            candidates += (0..<columnCount(row: 0)).map { Cell(row: 0, col: $0) }.filter { grid[$0] == nil }
        }
        if candidates.isEmpty { candidates = attachableCells() }
        guard let cell = candidates.min(by: { simd_distance(center(of: $0), shot.position) < simd_distance(center(of: $1), shot.position) })
        else { return }
        grid[cell] = shot.stone

        let colorIndex = shot.stone.colorIndex
        let group = connected(from: cell) { grid[$0]?.colorIndex == colorIndex }
        if group.count >= minMatch {
            for member in group {
                if let stone = grid.removeValue(forKey: member) { pop(at: center(of: member), stone: stone) }
            }
            let dropped = dropFloatingStones()
            score += group.count * PebbleGameTuning.pointsPerPop + dropped * PebbleGameTuning.pointsPerDrop
            water.disturb(atU: center(of: cell).x / Float(size.width),
                          strength: PebbleGameTuning.popWaterPush * (dropped > 0 ? 2 : 1))
            (dropped > 0 ? Haptic.success : Haptic.primary).play()
        } else {
            Haptic.ripple.play()
            misses += 1
            if misses >= PebbleGameTuning.missesBeforeNewRow {
                misses = 0
                insertRow()
                water.disturb(atU: 0.5, strength: PebbleGameTuning.popWaterPush)
            }
        }

        if grid.isEmpty {
            score += PebbleGameTuning.clearBonus
            misses = 0
            let finishedLastLevel = levelIndex == PebbleGameTuning.minMatchByLevel.count - 1
            levelIndex = finishedLastLevel ? 0 : levelIndex + 1
            isReady = true
            isTouchAiming = false
            fillInitialRows()
            if finishedLastLevel {
                isVictory = true
                celebrateVictory()
                water.disturb(atU: 0.5, strength: PebbleGameTuning.popWaterPush * 3)
            } else {
                Haptic.celebrate.play() // o confete da última fase já vibra junto
            }
        }
        refreshCannonColors()

        if grid.keys.contains(where: { center(of: $0).y > dangerY }) { endGame() }
    }

    /// Toda célula livre onde uma pedrinha pode grudar (no teto ou encostada em outra) — só pro
    /// caso raro de a atingida não ter vizinha livre.
    private func attachableCells() -> [Cell] {
        let lastRow = (grid.keys.map(\.row).max() ?? 0) + 1
        return (0...lastRow).flatMap { row in
            (0..<columnCount(row: row)).map { Cell(row: row, col: $0) }
        }.filter { cell in
            grid[cell] == nil && (cell.row == 0 || neighbors(of: cell).contains { grid[$0] != nil })
        }
    }

    /// Solta (e faz cair) toda pedrinha que não está mais ligada ao teto. Devolve quantas caíram.
    private func dropFloatingStones() -> Int {
        let roots = grid.keys.filter { $0.row == 0 }
        var anchored = Set<Cell>()
        for root in roots where !anchored.contains(root) {
            anchored.formUnion(connected(from: root) { grid[$0] != nil })
        }
        let floating = grid.keys.filter { !anchored.contains($0) }
        for cell in floating {
            if let stone = grid.removeValue(forKey: cell) {
                loose.append(Loose(position: center(of: cell), velocity: SIMD2(Float.random(in: -60...60), Float.random(in: -80...0)),
                                   stone: stone, life: 1.4, lifetime: 1.4, isPopping: false))
            }
        }
        return floating.count
    }

    /// Desce toda a grade uma linha e enche o topo com pedrinhas novas.
    private func insertRow() {
        var shifted: [Cell: Stone] = [:]
        for (cell, stone) in grid { shifted[Cell(row: cell.row + 1, col: cell.col)] = stone }
        grid = shifted
        rowParity ^= 1
        for col in 0..<columnCount(row: 0) {
            grid[Cell(row: 0, col: col)] = .random()
        }
        slide += rowHeight
        Haptic.warning.play()
    }

    /// Fim de jogo: a grade inteira desaba e uma nova partida começa depois da pausa.
    private func endGame() {
        for (cell, stone) in grid {
            loose.append(Loose(position: center(of: cell), velocity: SIMD2(Float.random(in: -80...80), Float.random(in: -120...0)),
                               stone: stone, life: 1.6, lifetime: 1.6, isPopping: false))
        }
        grid.removeAll()
        shot = nil
        isTouchAiming = false
        gameOverTimer = PebbleGameTuning.gameOverPause
        onGameOver?(score)
    }

    /// O canhão só carrega cores que ainda existem na grade (senão sobram tiros sem par).
    private func refreshCannonColors() {
        let present = Set(grid.values.map(\.colorIndex))
        guard !present.isEmpty else { return }
        if !present.contains(loaded.colorIndex) { loaded = randomStone() }
        if !present.contains(next.colorIndex) { next = randomStone() }
    }

    private func randomStone() -> Stone {
        let present = Array(Set(grid.values.map(\.colorIndex)))
        return .random(colors: present.isEmpty ? nil : present)
    }

    // MARK: Geometria da grade

    private var gridTopY: Float { PebbleGameTuning.gridTop }

    private func isShifted(row: Int) -> Bool { (row + rowParity) % 2 == 1 }

    private func columnCount(row: Int) -> Int { isShifted(row: row) ? columns - 1 : columns }

    private func center(of cell: Cell) -> SIMD2<Float> {
        let x = gridLeft + radius + Float(cell.col) * diameter + (isShifted(row: cell.row) ? radius : 0)
        let y = gridTopY + radius + Float(cell.row) * rowHeight
        return SIMD2(x, y)
    }

    /// As até seis vizinhas na colmeia. Numa linha deslocada, as vizinhas de cima e de baixo
    /// são as colunas `col` e `col + 1`; numa linha normal, `col − 1` e `col`.
    private func neighbors(of cell: Cell) -> [Cell] {
        let offset = isShifted(row: cell.row) ? 0 : -1
        let candidates = [
            Cell(row: cell.row, col: cell.col - 1), Cell(row: cell.row, col: cell.col + 1),
            Cell(row: cell.row - 1, col: cell.col + offset), Cell(row: cell.row - 1, col: cell.col + offset + 1),
            Cell(row: cell.row + 1, col: cell.col + offset), Cell(row: cell.row + 1, col: cell.col + offset + 1),
        ]
        return candidates.filter { $0.row >= 0 && $0.col >= 0 && $0.col < columnCount(row: $0.row) }
    }

    private func connected(from start: Cell, where include: (Cell) -> Bool) -> Set<Cell> {
        var visited: Set<Cell> = [start]
        var stack = [start]
        while let cell = stack.popLast() {
            for neighbor in neighbors(of: cell) where !visited.contains(neighbor) && include(neighbor) {
                visited.insert(neighbor)
                stack.append(neighbor)
            }
        }
        return visited
    }

    // MARK: Efeitos

    private func pop(at point: SIMD2<Float>, stone: Stone) {
        loose.append(Loose(position: point, velocity: .zero, stone: stone, life: 0.18, lifetime: 0.18, isPopping: true))
        for _ in 0..<6 {
            let angle = Float.random(in: 0...(2 * .pi))
            let lifetime = Float.random(in: 0.3...0.6)
            sparks.append(Spark(position: point, velocity: SIMD2(cos(angle), sin(angle)) * Float.random(in: 60...160),
                                radius: Float.random(in: 1.2...3), life: lifetime, lifetime: lifetime))
        }
        if sparks.count > 160 { sparks.removeFirst(sparks.count - 160) }
    }

    private func updateLoose(dt: Float) {
        let floor = Float(size.height) + diameter
        for i in loose.indices {
            loose[i].life -= dt
            guard !loose[i].isPopping else { continue }
            loose[i].velocity.y += 900 * dt
            loose[i].position += loose[i].velocity * dt
        }
        loose.removeAll { $0.life <= 0 || $0.position.y > floor }
    }

    /// Última fase limpa: confete sai dos dois cantos de baixo e cai do alto da tela.
    private func celebrateVictory() {
        confetti.burst(in: size, colorCount: PebbleGameTuning.colors.count)
    }

    private func updateSparks(dt: Float) {
        for i in sparks.indices {
            sparks[i].life -= dt
            sparks[i].velocity *= exp(-3 * dt)
            sparks[i].velocity.y -= 100 * dt // bolha sobe
            sparks[i].position += sparks[i].velocity * dt
        }
        sparks.removeAll { $0.life <= 0 }
    }

    // MARK: Mira

    /// Pontos da linha de mira: sai do canhão, quica nas paredes e para na primeira pedrinha
    /// (ou no teto).
    private func aimGuide() -> [CGPoint] {
        guard shot == nil, gameOverTimer <= 0, !isReady else { return [] }
        var position = shooter
        var direction = SIMD2(sin(aim), -cos(aim))
        var travelled: Float = 0
        var points: [CGPoint] = []
        let spacing: Float = 14
        let length = isTouchAiming ? PebbleGameTuning.touchAimGuideLength : PebbleGameTuning.aimGuideLength
        var sinceLast: Float = radius * 1.4 - spacing // o primeiro ponto fica fora do canhão
        while travelled < length {
            let step: Float = 4
            position += direction * step
            travelled += step
            sinceLast += step
            reflectOffWalls(&position, direction: &direction)
            if position.y <= gridTopY + radius || collidingCell(at: position) != nil { break }
            if sinceLast >= spacing {
                sinceLast = 0
                points.append(CGPoint(x: CGFloat(position.x), y: CGFloat(position.y)))
            }
        }
        return points
    }

    // MARK: Foto pra desenhar

    func snapshot() -> PebbleGameSnapshot {
        let offset = CGFloat(slide)
        func point(_ p: SIMD2<Float>, slides: Bool = true) -> CGPoint {
            CGPoint(x: CGFloat(p.x), y: CGFloat(p.y) - (slides ? offset : 0))
        }
        func pebble(_ stone: Stone, at p: CGPoint, scale: CGFloat = 1, alpha: CGFloat = 1) -> PebbleGameSnapshot.Pebble {
            PebbleGameSnapshot.Pebble(position: p, colorIndex: stone.colorIndex, seed: stone.seed, scale: scale, alpha: alpha)
        }
        var pebbles = grid.map { pebble($0.value, at: point(center(of: $0.key))) }
        for item in loose {
            let progress = CGFloat(1 - item.life / item.lifetime)
            pebbles.append(item.isPopping
                ? pebble(item.stone, at: point(item.position, slides: false), scale: 1 + 0.5 * progress, alpha: 1 - progress)
                : pebble(item.stone, at: point(item.position, slides: false), alpha: min(1, CGFloat(item.life / item.lifetime) * 2)))
        }
        let lowest = grid.keys.map { center(of: $0).y }.max() ?? gridTopY
        let dangerLevel = max(0, min(1, 1 - (dangerY - lowest) / (rowHeight * 3)))
        let cannon = point(shooter, slides: false)
        return PebbleGameSnapshot(
            radius: CGFloat(radius),
            pebbles: pebbles,
            shot: shot.map { pebble($0.stone, at: point($0.position, slides: false)) },
            sparks: sparks.map {
                PebbleGameSnapshot.Spark(position: point($0.position, slides: false), radius: CGFloat($0.radius),
                                         alpha: CGFloat($0.life / $0.lifetime) * 0.8)
            },
            shooter: cannon,
            aimAngle: CGFloat(aim),
            aimGuide: aimGuide(),
            isTouchAiming: isTouchAiming,
            loaded: pebble(loaded, at: cannon),
            next: pebble(next, at: CGPoint(x: cannon.x + CGFloat(radius) * 2.6, y: cannon.y + CGFloat(radius) * 0.3), scale: 0.6),
            dangerY: CGFloat(dangerY),
            dangerLevel: CGFloat(dangerLevel),
            shotsUntilNewRow: PebbleGameTuning.missesBeforeNewRow - misses,
            score: score,
            level: levelIndex + 1,
            minMatch: minMatch,
            isReady: isReady,
            isCelebrating: isVictory,
            confetti: confetti.snapshot(),
            isGameOver: gameOverTimer > 0
        )
    }
}
