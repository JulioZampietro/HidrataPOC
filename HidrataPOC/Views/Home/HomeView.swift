import AVFoundation
import SwiftData
import SwiftUI


struct HomeView: View {
    let profile: UserProfile
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    // Barra e cartões têm tamanho fixo (o do texto em 100%): só o texto dentro deles acompanha
    // o Dynamic Type, limitado a `controlTextSizeRange` para caber sem ser cortado.
    private let progressBarHeight = TabScreenLayout.progressBarHeight
    // Estreitados por predicado: sem ele, cada atualização do `body` materializava as
    // tabelas inteiras de IntakeLog/DailyGoal para então filtrar em Swift. A Home só
    // olha o dia de hoje, nos dois casos. Os filtros em Swift abaixo continuam: o
    // predicado é fixado na criação da view, então depois da meia-noite ele deixa
    // passar o dia anterior, e é o filtro que mantém a conta certa.
    //
    // @Query síncrono de propósito, não `.syncedFetch`: a real causa da regressão do
    // A-2 (ver CORRECOES.md) foi isolada no `init` de ProfileView, construída fresca
    // no meio de `.navigationDestination(isPresented:)` — revertendo isoladamente
    // WaterHeaderView/HomeView/HistoricoView não bastou pra destravar a navegação,
    // só ProfileView era o problema. HomeView nunca é construída numa transição (o
    // RootView a desenha uma vez, dentro do LazyHStack fixo), então não corre o mesmo
    // risco. Com `.syncedFetch`, allLogs/allDailyGoals começavam vazios em toda
    // abertura do app, e a barra de progresso (que anima por `value: today.progress`)
    // tocava a animação de encher do zero a cada relançamento — o mesmo bug do
    // mascote em WaterHeaderView, mesma causa raiz, mesma correção.
    @Query private var allLogs: [IntakeLog]
    @Query private var allDailyGoals: [DailyGoal]

    init(profile: UserProfile) {
        self.profile = profile
        let userID = profile.userID
        let dayStart = Calendar.current.startOfDay(for: .now)
        _allLogs = Query(filter: #Predicate<IntakeLog> { $0.userID == userID && $0.timestamp >= dayStart },
                         sort: \IntakeLog.timestamp)
        let todayKey = DailyGoal.dayKey(for: .now)
        _allDailyGoals = Query(filter: #Predicate<DailyGoal> { $0.userID == userID && $0.dayKey == todayKey },
                               sort: \DailyGoal.dayKey)
    }
    @State private var isLogging = false
    @State private var highlightedCard: String? = nil
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isEditingCustomAmount = false
    @State private var showSiriTutorial = false
    @State private var showActionButtonTutorial = false
    @State private var showTodayLogs = false
    @State private var showSaveFailedAlert = false
    @State private var pendingRetry: (preset: Constants.IntakePreset, cardID: String)?
    @State private var tempContext: TemperatureAdjustmentContext?
    /// Minijogo da meta batida: o aquário (`WaterHeaderView`) desenha, aqui ficam os botões.
    @Environment(MiniGameController.self) private var miniGames
    @State private var pressedJets = [Bool](repeating: false, count: RingGameSide.allCases.count)
    @State private var pressedAimSides = [Bool](repeating: false, count: PebbleGameSide.allCases.count)
    @State private var isFirePressed = false
    @AppStorage(MiniGame.jumpBestStorageKey) private var jumpBestScore = 0
    @AppStorage(MiniGame.flappyBestStorageKey) private var flappyBestScore = 0
    /// Os dois botões de nadar da Gota Voadora (esquerda e direita).
    @State private var pressedFlapSides = [false, false]
    /// Última direção (e a outra metade, numa diagonal) mandada pelo joystick de quatro direções:
    /// só manda de novo quando muda.
    @State private var joystickDirections: [MazeDirection]?
    @AppStorage(MiniGame.mazeBestStorageKey) private var mazeBestScore = 0
    @AppStorage(MiniGame.sliceBestStorageKey) private var sliceBestScore = 0
    @AppStorage(MiniGame.snakeBestStorageKey) private var snakeBestScore = 0
    @AppStorage(MiniGame.minesBestStorageKey) private var minesBestScore = 0
    @AppStorage(MiniGame.runnerBestStorageKey) private var runnerBestScore = 0
    /// Campo Minado: tocar na água marca bandeira em vez de abrir (espelha `minesGame.flagMode`).
    @State private var minesFlagMode = false
    /// Os quatro cartões de ingestão viram os botões do jogo na mesma animação.
    @Namespace private var controlsNamespace

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }
    
    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }
    
    private var dailyGoals: [DailyGoal] {
        allDailyGoals.filter { $0.userID == profile.userID }
    }

    /// True once today's temperature adjustment has already been fetched and locked
    /// in (see `DailyGoal.recordToday`) — at that point a fresh WeatherKit call would
    /// only repeat work `recordedAdjustmentML` already covers, so it's skipped.
    private var isTodaysAdjustmentLocked: Bool {
        let key = DailyGoal.dayKey(for: .now)
        return dailyGoals.first { $0.dayKey == key }?.adjustmentLocked ?? false
    }

    private var effectiveGoalML: Int {
        HydrationMath.effectiveGoalML(
            baseGoalML: profile.metaDiariaML,
            tempContext: tempContext,
            recordedAdjustmentML: DailyGoalResolver.recordedAdjustmentML(in: dailyGoals, on: .now)
        )
    }

    private var progress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(effectiveGoalML))
    }
    
    /// Ingestão de hoje pra barra de progresso, calculada uma vez por atualização do `body`: o
    /// `GeometryReader` da tela refaz o conteúdo a cada frame enquanto a página desliza (o
    /// arrasto entre Home e Histórico), e filtrar todos os registros lá dentro travava o arrasto.
    private struct TodayIntake {
        let consumedML: Int
        let goalML: Int
        let progress: Double
    }

    var body: some View {
        let consumed = consumedToday
        let goal = effectiveGoalML
        let today = TodayIntake(consumedML: consumed, goalML: goal, progress: goal > 0 ? min(1, Double(consumed) / Double(goal)) : 0)
        ZStack {
            AppTheme.screenBackground(for: colorScheme)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: TabScreenLayout.spacing) {
                    // O recipiente de água (`WaterHeaderView`) é desenhado pelo
                    // `RootView`, fixo por cima das páginas; aqui fica só o espaço dele.
                    // Na tela do minijogo ele ocupa também o lugar da barra e da primeira
                    // linha de botões.
                    Color.clear
                        .frame(height: miniGames.showsGameControls
                            ? TabScreenLayout.gameWaterHeight(forVisibleHeight: geo.size.height, safeAreaTop: geo.safeAreaInsets.top)
                            : TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height, safeAreaTop: geo.safeAreaInsets.top))

                    if !miniGames.showsGameControls {
                        progressBarButton(today)
                            .padding(.horizontal, 20)
                    }

                    bottomControls(cardHeight: intakeCardHeight(forVisibleHeight: geo.size.height))
                        .padding(.horizontal, 20)
                }
                .padding(.top, TabScreenLayout.waterTop(safeAreaTop: geo.safeAreaInsets.top))
                // Travados enquanto o mascote anima (ver `MiniGameController.isMascotAnimating`).
                .allowsHitTesting(!miniGames.isMascotAnimating)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: miniGames.showsGameControls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
            }
        }
        // Keeps the Home Screen water tank widget filling against the same goal as the bar,
        // and snapshots it as today's goal so later edits never touch this day.
        .onChange(of: effectiveGoalML, initial: true) { _, goal in
            WidgetSync.saveEffectiveGoal(goal)
            DailyGoal.recordToday(userID: profile.userID, baseGoalML: profile.metaDiariaML, adjustmentML: tempContext?.adjustmentML, context: modelContext)
        }
        .onAppear {
            guard tempContext == nil, !isTodaysAdjustmentLocked else { return }
            Task {
                tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
            }
        }
        .sheet(isPresented: $isEditingCustomAmount) {
            CustomIntakeEditorView(title: "Outro", initialValueML: profile.customIntakeML, onSave: saveCustomAmount)
                .trackSheetLifecycle(.customAmountEditor, screen: .home, userID: profile.userID)
        }
        // Os botões do jogo somem (ex.: seta de voltar à ingestão) ou o jogo troca: solta o que estiver apertado.
        .onChange(of: miniGames.showsGameControls) { releaseGameButtons() }
        .onChange(of: miniGames.runningGame) { releaseGameButtons() }
        .sheet(isPresented: $showSiriTutorial) { SiriTutorialView() }
        .sheet(isPresented: $showActionButtonTutorial) { ActionButtonTutorialView() }
        .sheet(isPresented: $showTodayLogs) {
            // Same goal as the bar (base + temperature adjustment), so the sheet's
            // "X mL de Y mL" matches what the user just tapped.
            DayDetailSheet(
                dia: DiaHistorico(date: .now, percentualMeta: progress),
                metaDiariaML: effectiveGoalML,
                profile: profile,
                calendar: .current
            )
        }
        // M-2: ModelContext.saveLogging já loga a falha; sem isso, o toque só some da
        // tela no próximo lançamento do app, sem explicação (ver CORRECOES.md).
        .alert("Não foi possível registrar", isPresented: $showSaveFailedAlert) {
            Button("Tentar de novo") {
                if let pendingRetry {
                    logIntake(pendingRetry.preset, cardID: pendingRetry.cardID)
                }
            }
            Button("Cancelar", role: .cancel) { pendingRetry = nil }
        } message: {
            Text("O registro de água não foi salvo. Verifique o espaço de armazenamento do aparelho e tente de novo.")
        }
    }

    // MARK: - Subviews
    
    private let intakeGridSpacing = TabScreenLayout.intakeGridSpacing
    private let controlTextSizeRange = ...DynamicTypeSize.xxxLarge

    /// The two rows of intake cards share what's left below the progress bar, so the
    /// grid ends `TabScreenLayout.spacing` above the bottom safe area.
    private func intakeCardHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        TabScreenLayout.intakeCardHeight(forVisibleHeight: height)
    }

    /// Tapping the bar opens today's intake logs (same sheet as a day in Histórico).
    private func progressBarButton(_ today: TodayIntake) -> some View {
        Button {
            Haptic.tap.play()
            InteractionTracker.log("home_progress_bar_tap", screen: .home, userID: profile.userID, context: modelContext)
            showTodayLogs = true
        } label: {
            progressBar(today)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Consumo de hoje: \(today.consumedML) de \(today.goalML) mililitros")
        .accessibilityHint("Mostra os registros de hoje")
    }

    private func progressBar(_ today: TodayIntake) -> some View {
        GeometryReader { geo in
            let barWidth = max(geo.size.width * today.progress, 56)
            
            ZStack(alignment: .leading) {
                // trilha, elevada com a mesma sombra dos cartões de ingestão
                Capsule()
                    .fill(AppTheme.progressTrack(for: colorScheme))
                    .frame(height: progressBarHeight)
                    // Contorno só no escuro, onde a trilha azul-marinho quase some no fundo;
                    // no claro a trilha cinza aparece sozinha, sem borda.
                    .overlay {
                        if colorScheme == .dark {
                            Capsule().strokeBorder(Color.appControlOutline, lineWidth: 1)
                        }
                    }
                    .homeCardShadow()
                
                // preenchimento azul
                Capsule()
                    .fill(LinearGradient.waterHeader)
                    .frame(width: barWidth, height: progressBarHeight)
                    .animation(.easeOut(duration: 0.4), value: today.progress)
                
                // Texto sempre branco, sobre a trilha e sobre o preenchimento.
                progressLabel(today, color: .white)

                // Indica que a barra é tocável (abre os registros de hoje). Sempre branco,
                // igual ao texto da barra.
                Image(systemName: "info.circle")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: progressBarHeight)
        .dynamicTypeSize(controlTextSizeRange)
    }
    
    private func progressLabel(_ today: TodayIntake, color: Color) -> some View {
        Text("\(today.consumedML) mL / \(today.goalML) mL")
            .font(AppFont.subheadlineHeavy)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75) // 15 pt × 0.75 ≈ 11 pt: o menor texto do app (HIG)
            .padding(.leading, 18)
            .padding(.trailing, 52)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Os quatro cartões de ingestão; com a meta batida e um minijogo rodando, viram os botões
    /// do jogo (uma linha de três) no mesmo lugar (`matchedGeometryEffect`). A seta pra trás no
    /// cabeçalho do aquário sai do jogo (escolhe "Sem jogo") e volta aos cartões.
    private func bottomControls(cardHeight: CGFloat) -> some View {
        ZStack {
            if miniGames.showsGameControls, let game = miniGames.runningGame {
                gameControls(game, cardHeight: cardHeight)
            } else {
                intakeGrid(cardHeight: cardHeight)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: miniGames.showsGameControls)
    }

    /// Uma linha de três botões, no lugar da última linha de cartões: esquerda, meio e direita.
    /// Voltar à ingestão fica na seta pra trás do cabeçalho do aquário.
    @ViewBuilder
    private func gameControls(_ game: MiniGame, cardHeight: CGFloat) -> some View {
        HStack(spacing: intakeGridSpacing) {
            switch game {
            case .rings:
                jetButton(.left).matchedGeometryEffect(id: "gole", in: controlsNamespace)
                jetButton(.center).matchedGeometryEffect(id: "bottle", in: controlsNamespace)
                jetButton(.right).matchedGeometryEffect(id: "glass", in: controlsNamespace)
            case .pebbles:
                aimButton(.left).matchedGeometryEffect(id: "gole", in: controlsNamespace)
                fireButton.matchedGeometryEffect(id: "bottle", in: controlsNamespace)
                aimButton(.right).matchedGeometryEffect(id: "glass", in: controlsNamespace)
            case .flappy:
                // Um botão de nadar de cada lado, pra jogar com qualquer polegar; recorde no meio.
                flapButton(0).matchedGeometryEffect(id: "gole", in: controlsNamespace)
                JumpGameRecordCard(best: flappyBestScore, height: cardHeight)
                    .matchedGeometryEffect(id: "bottle", in: controlsNamespace)
                flapButton(1).matchedGeometryEffect(id: "glass", in: controlsNamespace)
            case .maze:
                recordRow(best: mazeBestScore, cardHeight: cardHeight) {
                    directionJoystick(label: "Joystick do rim") { miniGames.mazeGame.setDirection($0, alternate: $1) }
                }
            case .snake:
                // A cobrinha vira deslizando no aquário: no lugar dos controles, só a dica.
                recordRow(best: snakeBestScore, cardHeight: cardHeight) {
                    GameHintCard(title: "Deslize na água", subtitle: "Deslize o dedo pra controlar", height: cardHeight)
                }
            case .slice:
                // O corte é no aquário: no lugar dos controles, só a dica.
                recordRow(best: sliceBestScore, cardHeight: cardHeight) {
                    GameHintCard(title: "Deslize na água", subtitle: "Corte as pedras e não corte o rim", height: cardHeight)
                }
            case .mines:
                // As casas se abrem tocando no aquário; aqui fica a troca entre abrir e marcar.
                recordRow(best: minesBestScore, cardHeight: cardHeight) {
                    MinesModeCard(isFlagging: minesFlagMode, height: cardHeight) {
                        minesFlagMode.toggle()
                        miniGames.minesGame.flagMode = minesFlagMode
                    }
                    .onAppear { miniGames.minesGame.flagMode = minesFlagMode }
                }
            case .runner:
                // A gota desvia deslizando no aquário: no lugar dos controles, só a dica.
                recordRow(best: runnerBestScore, cardHeight: cardHeight) {
                    GameHintCard(title: "Deslize na água", subtitle: "Pros lados, pra cima ou pra baixo", height: cardHeight)
                }
            default:
                recordRow(best: jumpBestScore, cardHeight: cardHeight) { jumpJoystick }
            }
        }
        .frame(height: cardHeight)
        .dynamicTypeSize(controlTextSizeRange)
    }

    private func jetButton(_ side: RingGameSide) -> some View {
        RingGameControls(
            side: side,
            isPressed: pressedJets[side.rawValue],
            onPressChange: { isPressed in
                guard pressedJets[side.rawValue] != isPressed else { return }
                pressedJets[side.rawValue] = isPressed
                miniGames.ringGame.setJet(side, open: isPressed)
                if isPressed { Haptic.tap.play() }
            },
            onAccessibilityPulse: { miniGames.ringGame.pulseJet(side) }
        )
    }

    private func aimButton(_ side: PebbleGameSide) -> some View {
        GameHoldButton(
            symbol: side == .left ? "arrow.counterclockwise.circle.fill" : "arrow.clockwise.circle.fill",
            accessibilityLabel: side == .left ? "Mirar pra esquerda" : "Mirar pra direita",
            accessibilityHint: "Gira o canhão de bolhas enquanto estiver apertado",
            isPressed: pressedAimSides[side.rawValue],
            onPressChange: { isPressed in
                guard pressedAimSides[side.rawValue] != isPressed else { return }
                pressedAimSides[side.rawValue] = isPressed
                miniGames.pebbleGame.setAim(side, held: isPressed)
                if isPressed { Haptic.selection.play() }
            },
            onAccessibilityPulse: { miniGames.pebbleGame.pulseAim(side) }
        )
    }

    /// Atira ao apertar; o pulso do toque completo (ver `GameHoldButton`) só cobre o caso em
    /// que o `pressing` não chegou — a simulação ignora o segundo tiro enquanto o primeiro voa.
    /// Nada pra cima ao apertar; o pulso do toque completo (ver `GameHoldButton`) só cobre o caso
    /// em que o `pressing` não chegou — a simulação ignora braçadas coladas (`flapCooldown`).
    private func flapButton(_ index: Int) -> some View {
        GameHoldButton(
            symbol: "arrow.up.circle.fill",
            accessibilityLabel: "Nadar pra cima",
            accessibilityHint: "Faz a gota nadar pra cima; tocar no aquário também",
            isPressed: pressedFlapSides[index],
            onPressChange: { isPressed in
                guard pressedFlapSides[index] != isPressed else { return }
                pressedFlapSides[index] = isPressed
                if isPressed { miniGames.flappyGame.flap() }
            },
            onAccessibilityPulse: { miniGames.flappyGame.flap() }
        )
    }

    /// Recorde num terço à esquerda e o controle do jogo (joystick ou dica) nos outros dois terços,
    /// pro polegar ter espaço.
    private func recordRow(best: Int, cardHeight: CGFloat, @ViewBuilder control: () -> some View) -> some View {
        let joystick = control()
        return GeometryReader { geo in
            HStack(spacing: intakeGridSpacing) {
                JumpGameRecordCard(best: best, height: cardHeight)
                    .frame(width: (geo.size.width - intakeGridSpacing * 2) / 3)
                    .matchedGeometryEffect(id: "gole", in: controlsNamespace)
                joystick
                    .matchedGeometryEffect(id: "glass", in: controlsNamespace)
            }
        }
    }

    /// Gota Saltitante: joystick só na horizontal; quanto mais pro lado, mais rápido a gota anda.
    private var jumpJoystick: some View {
        GameJoystick(
            horizontalOnly: true,
            accessibilityLabel: "Joystick da gota",
            accessibilityActions: [
                ("Esquerda", { miniGames.jumpGame.pulseDirection(.left) }),
                ("Direita", { miniGames.jumpGame.pulseDirection(.right) }),
            ],
            onChange: { tilt in miniGames.jumpGame.setJoystick(Float(tilt.dx)) }
        )
    }

    /// Joystick de quatro direções (Rim Comilão): vira pro lado em que o
    /// polegar aponta mais, assim que ele sai um pouco do centro. Na diagonal (entre ~22° e ~68°
    /// de um eixo) manda as duas direções, e o jogo pega a que der primeiro.
    private func directionJoystick(label: String, onDirection: @escaping (MazeDirection, MazeDirection?) -> Void) -> some View {
        GameJoystick(
            horizontalOnly: false,
            accessibilityLabel: label,
            accessibilityActions: [
                ("Cima", { onDirection(.up, nil) }),
                ("Baixo", { onDirection(.down, nil) }),
                ("Esquerda", { onDirection(.left, nil) }),
                ("Direita", { onDirection(.right, nil) }),
            ],
            onChange: { tilt in
                guard hypot(tilt.dx, tilt.dy) > 0.4 else {
                    if tilt == .zero { joystickDirections = nil }
                    return
                }
                let horizontal: MazeDirection = tilt.dx > 0 ? .right : .left
                let vertical: MazeDirection = tilt.dy > 0 ? .down : .up
                let (major, minor) = abs(tilt.dx) > abs(tilt.dy) ? (horizontal, vertical) : (vertical, horizontal)
                // sen(22,5°) ≈ 0,38: o eixo menor pesa o bastante pra contar como diagonal.
                let isDiagonal = min(abs(tilt.dx), abs(tilt.dy)) / hypot(tilt.dx, tilt.dy) > 0.38
                let directions = isDiagonal ? [major, minor] : [major]
                guard directions != joystickDirections else { return }
                joystickDirections = directions
                Haptic.selection.play()
                onDirection(major, isDiagonal ? minor : nil)
            }
        )
    }

    private var fireButton: some View {
        GameHoldButton(
            symbol: "arrow.up.circle.fill",
            accessibilityLabel: "Atirar bolha",
            accessibilityHint: "Atira a bolha do canhão na direção da mira",
            isPressed: isFirePressed,
            onPressChange: { isPressed in
                guard isFirePressed != isPressed else { return }
                isFirePressed = isPressed
                if isPressed { miniGames.pebbleGame.fire() }
            },
            onAccessibilityPulse: { miniGames.pebbleGame.fire() }
        )
    }

    /// Solta qualquer botão de jogo que estivesse apertado (os botões sumiram ou o jogo trocou).
    private func releaseGameButtons() {
        pressedJets = [Bool](repeating: false, count: RingGameSide.allCases.count)
        for side in RingGameSide.allCases { miniGames.ringGame.setJet(side, open: false) }
        miniGames.jumpGame.setJoystick(0)
        pressedAimSides = [Bool](repeating: false, count: PebbleGameSide.allCases.count)
        isFirePressed = false
        pressedFlapSides = [false, false]
        joystickDirections = nil
        for side in PebbleGameSide.allCases { miniGames.pebbleGame.setAim(side, held: false) }
    }

    private func intakeGrid(cardHeight: CGFloat) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: intakeGridSpacing), GridItem(.flexible(), spacing: intakeGridSpacing)],
            spacing: intakeGridSpacing
        ) {
            goleCard(height: cardHeight)
                .matchedGeometryEffect(id: "gole", in: controlsNamespace)
            intakeCard(.glass, height: cardHeight)
                .matchedGeometryEffect(id: "glass", in: controlsNamespace)
            intakeCard(.bottle, height: cardHeight)
                .matchedGeometryEffect(id: "bottle", in: controlsNamespace)
            customIntakeCard(height: cardHeight)
                .matchedGeometryEffect(id: "custom", in: controlsNamespace)
        }
    }

    private func goleCard(height: CGFloat) -> some View {
        Button { logIntake(.gole, cardID: "gole") } label: {
            IntakeCardContent(
                icon: .symbol("drop.fill"),
                title: "Gole",
                subtitle: "40 mL",
                isHighlighted: highlightedCard == "gole",
                height: height
            )
        }
        .buttonStyle(.plain)
    }

    private func intakeCard(_ preset: Constants.IntakePreset, height: CGFloat) -> some View {
        Button { logIntake(preset, cardID: preset.label) } label: {
            IntakeCardContent(
                icon: intakeIcon(for: preset),
                title: preset.label,
                subtitle: "\(preset.volumeML) mL",
                isHighlighted: highlightedCard == preset.label,
                height: height
            )
        }
        .buttonStyle(.plain)
    }

    private func customIntakeCard(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { logIntake(.custom(volumeML: profile.customIntakeML), cardID: "custom") } label: {
                IntakeCardContent(
                    icon: .beaker,
                    title: "Outro",
                    subtitle: "\(profile.customIntakeML) mL",
                    isHighlighted: highlightedCard == "custom",
                    height: height
                )
            }
            .buttonStyle(.plain)
            
            Button {
                Haptic.tap.play()
                isEditingCustomAmount = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 30))
                    .foregroundStyle(Color.appAccentText)
                    .padding(7) // 30 pt de ícone + 7 de cada lado = alvo de 44 pt
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("Editar volume do botão personalizado")
        }
    }
    
    // MARK: - Helpers
    
    private func intakeIcon(for preset: Constants.IntakePreset) -> IntakeCardIcon? {
        switch preset {
        case .glass: return .symbol("mug.fill", mirrored: true)
        case .bottle: return .bottle
        case .gole: return .symbol("drop.fill")
        case .custom: return nil
        }
    }
    
    private func logIntake(_ preset: Constants.IntakePreset, cardID: String) {
        guard !isLogging else { return }
        isLogging = true
        playWaterSound()
        Haptic.drink.play()
        withAnimation(.easeInOut(duration: 0.15)) { highlightedCard = cardID }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeInOut(duration: 0.2)) { highlightedCard = nil }
        }
        Task {
            let saved = await NotificationScheduler.shared.recordManualIntake(preset: preset, userID: profile.userID, context: modelContext)
            isLogging = false
            if !saved {
                pendingRetry = (preset, cardID)
                Haptic.warning.play()
                showSaveFailedAlert = true
            }
        }
    }

    private func playWaterSound() {
        Task.detached(priority: .userInitiated) {
            guard let asset = NSDataAsset(name: "agua"),
                  let player = try? AVAudioPlayer(data: asset.data, fileTypeHint: AVFileType.mp3.rawValue) else { return }
            player.play()
            // Hand-off must be the last use: after it, the player belongs to the main
            // actor (which keeps it alive while it plays) and can't be touched here.
            await MainActor.run { audioPlayer = player }
        }
    }
    
    private func saveCustomAmount(_ newValue: Int) {
        Haptic.success.play()
        profile.customIntakeML = newValue
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        modelContext.saveLogging("volume personalizado")
        InteractionTracker.log("custom_amount_editor_save", screen: .home, userID: profile.userID, metadata: ["amountML": "\(newValue)"], context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
            await LiveActivityManager.shared.updateCustomAmount(newValue)
        }
    }
}

// MARK: - IntakeCardContent

/// Ícone de fundo dos cartões de ingestão.
enum IntakeCardIcon {
    /// SF Symbol; `mirrored` espelha na horizontal (ex.: alça do copo do lado cortado).
    case symbol(String, mirrored: Bool = false)
    /// Garrafa sólida desenhada à mão — o `waterbottle.fill` tem uma gota vazada no meio.
    case bottle
    /// Béquer sólido (tampa + corpo com marcas de volume vazadas), usado no cartão "Outro".
    case beaker

    /// Quanto do ícone (fração do lado) fica para fora da borda esquerda.
    var leadingOverflow: CGFloat {
        switch self {
        case .symbol(_, mirrored: true): return 0.36 // copo espelhado: empurra mais para a esquerda
        default: return 0.28
        }
    }
}

struct IntakeCardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: IntakeCardIcon?
    let title: String
    let subtitle: String
    var isHighlighted: Bool = false
    var height: CGFloat? = nil
    /// Texto no topo do cartão em vez de no rodapé, longe da parte mais cheia do ícone.
    var textOnTop: Bool = false

    /// Tinta do texto sobre o cartão liso (fora do ícone).
    private var titleInk: Color {
        isHighlighted ? .white : (colorScheme == .dark ? .primary : Color.appMutedInk)
    }

    private var subtitleInk: Color {
        isHighlighted ? .white : Color.appMutedInk
    }

    private var backgroundIconColor: AnyShapeStyle {
        isHighlighted ? AnyShapeStyle(Color.white.opacity(0.28)) : AnyShapeStyle(LinearGradient.waterHeader)
    }

    var body: some View {
        // Texto escuro sobre o cartão e branco sobre o ícone azul: o mesmo texto é
        // desenhado duas vezes e a versão branca é recortada no formato do ícone (a
        // mesma ideia da barra de progresso). Assim cada letra tem contraste com o que
        // está atrás, mesmo quando o texto passa da borda do ícone para o cartão claro.
        textBlock(title: titleInk, subtitle: subtitleInk)
            .overlay {
                if let icon, !isHighlighted {
                    textBlock(title: .white, subtitle: .white)
                        .mask { iconLayer(icon) }
                        .accessibilityHidden(true)
                }
            }
            .background(alignment: .leading) {
                // Ícone grande como fundo do cartão, deslocado para a esquerda e cortado pela borda.
                if let icon {
                    iconLayer(icon)
                        .foregroundStyle(backgroundIconColor)
                        .accessibilityHidden(true)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isHighlighted ? AnyShapeStyle(LinearGradient.waterHeader) : AnyShapeStyle(Color(UIColor.secondarySystemBackground)))
                    .homeCardShadow()
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // o cartão tem altura fixa; o texto não passa dela
    }

    /// Altura fixa: o cartão não muda com o Dynamic Type.
    private func textBlock(title titleColor: Color, subtitle subtitleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !textOnTop { Spacer(minLength: 0) }

            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(AppFont.subheadline)
                .foregroundStyle(subtitleColor)

            if textOnTop { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.top, textOnTop ? 20 : 0) // no topo, desce um pouco pra não colar na borda
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: height)
    }

    private func iconLayer(_ icon: IntakeCardIcon) -> some View {
        GeometryReader { geo in
            let side = geo.size.height * 1.15
            backgroundIcon(icon)
                .frame(width: side, height: side)
                .offset(x: -side * icon.leadingOverflow, y: (geo.size.height - side) / 2 + side * 0.15)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func backgroundIcon(_ icon: IntakeCardIcon) -> some View {
        switch icon {
        case let .symbol(name, mirrored):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        case .bottle:
            BottleShape()
        case .beaker:
            BeakerShape()
        }
    }
}

/// Garrafa sólida (tampa + gargalo + corpo), mais larga que o SF Symbol para cobrir o texto do cartão.
private struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()

        // Tampa
        path.addRoundedRect(
            in: CGRect(origin: pt(0.36, 0.02), size: CGSize(width: rect.width * 0.28, height: rect.height * 0.10)),
            cornerSize: CGSize(width: rect.width * 0.03, height: rect.width * 0.03),
            style: .continuous
        )

        // Gargalo, ombros e corpo
        path.move(to: pt(0.40, 0.15))
        path.addLine(to: pt(0.60, 0.15))
        path.addLine(to: pt(0.60, 0.19))
        path.addQuadCurve(to: pt(0.87, 0.36), control: pt(0.87, 0.21))
        path.addLine(to: pt(0.87, 0.88))
        path.addQuadCurve(to: pt(0.77, 0.98), control: pt(0.87, 0.98))
        path.addLine(to: pt(0.23, 0.98))
        path.addQuadCurve(to: pt(0.13, 0.88), control: pt(0.13, 0.98))
        path.addLine(to: pt(0.13, 0.36))
        path.addQuadCurve(to: pt(0.40, 0.19), control: pt(0.13, 0.21))
        path.closeSubpath()

        return path
    }
}

/// Béquer sólido: tampa em cápsula, corpo reto e quatro marcas de volume vazadas no lado direito.
private struct BeakerShape: Shape {
    func path(in rect: CGRect) -> Path {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                   width: w * rect.width, height: h * rect.height)
        }
        var path = Path()

        // Tampa: cápsula, com a ponta direita arredondada.
        let lid = r(0.12, 0.02, 0.76, 0.045)
        path.addRoundedRect(in: lid, cornerSize: CGSize(width: lid.height / 2, height: lid.height / 2), style: .continuous)

        // Corpo.
        path.addRoundedRect(
            in: r(0.12, 0.093, 0.70, 0.887),
            cornerSize: CGSize(width: rect.width * 0.04, height: rect.width * 0.04),
            style: .continuous
        )

        // Marcas de volume (alinhadas à direita, alternando longa e curta).
        var ticks = Path()
        let marks: [(y: CGFloat, w: CGFloat)] = [(0.18, 0.135), (0.254, 0.086), (0.327, 0.135), (0.40, 0.086)]
        let tickRight: CGFloat = 0.78
        for mark in marks {
            let tick = r(tickRight - mark.w, mark.y, mark.w, 0.023)
            ticks.addRoundedRect(in: tick, cornerSize: CGSize(width: tick.height / 2, height: tick.height / 2), style: .continuous)
        }
        return path.subtracting(ticks)
    }
}

private extension View {
    /// Elevação compartilhada pelos cartões de ingestão e pela barra de progresso.
    func homeCardShadow() -> some View {
        shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 25, genero: nil, pesoKg: 70, alturaCm: 170, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2450)
    return HomeView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
