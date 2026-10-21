import SwiftData
import SwiftUI

/// Recipiente de água do topo, compartilhado por Home e Histórico: o `RootView` o
/// desenha uma vez, fixo por cima das páginas, e só o conteúdo abaixo dele troca ao
/// arrastar. Enche com o progresso do dia e traz o mascote (com as pedrinhas, os rins e as
/// transições de estágio), o minijogo da meta batida e, no topo, os botões de compartilhar,
/// minijogos e perfil, junto da sequência de dias.
///
/// Só o mascote, os botões, a faixa de baixo (onde se brinca com as pedrinhas) e o jogo das
/// Bolhas Coloridas (mira com o dedo) recebem toques: o resto deixa o arrasto passar para as
/// páginas atrás, então dá para trocar de página arrastando sobre a água também.
struct WaterHeaderView: View {
    let profile: UserProfile
    /// Página visível — atribui os toques nos botões à tela certa.
    let screen: AppScreen
    let onOpenProfile: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    // Sem @Query com predicado de propósito — ver o comentário equivalente em
    // HomeView.swift (causa da regressão do A-2, documentada em CORRECOES.md).
    @State private var allLogs: [IntakeLog] = []
    @State private var allDailyGoals: [DailyGoal] = []
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var showShare = false
    @State private var showMiniGames = false
    @Environment(MiniGameController.self) private var miniGames
    /// Minijogo escolhido na aba de minijogos (ver `MiniGame.active`).
    @AppStorage(MiniGame.selectedStorageKey) private var selectedGameRaw = ""
    @AppStorage(MiniGame.announcedStorageKey) private var announcedGamesRaw = ""
    /// Jogo recém-liberado pela streak, mostrado num aviso no topo do aquário por alguns segundos.
    @State private var unlockedGameBanner: MiniGame?
    /// Tempo (s) entre a explosão do mascote e o aviso de jogo novo liberado aparecer.
    private static let gameStartDelay: Double = 1.4
    /// Tempo (s) da comemoração da meta batida: o mascote explode e as pedrinhas caem no fundo;
    /// só depois disso o jogo escolhido entra no aquário.
    private static let goalCelebrationDuration: Double = 1.8
    /// Meta batida "já comemorada": fica false durante `goalCelebrationDuration` depois que a
    /// meta é batida ao vivo, e é ela (não a meta em si) que libera o jogo no aquário. Abrindo o
    /// app já com a meta batida, vira true na hora.
    @State private var showsGoalReached = false
    /// Fala que o mascote solta sozinho, sorteada entre as liberadas para a situação (`MascotPhrases`).
    @State private var idlePhrase = ""
    @State private var pokeCount: Int = 0
    @State private var isPoking: Bool = false
    /// Fala temporária (cutucão, reação a um gole) que se sobrepõe à `idlePhrase`.
    @State private var overridePhrase: String? = nil
    @State private var overridePhraseReset: Task<Void, Never>?
    @GestureState private var mascotDragOffset: CGSize = .zero
    @State private var lastMascotDragTranslation: CGSize = .zero
    @State private var waterMotion = WaterMotion()
    @State private var explodingMascot: String? = nil
    /// Mascote do estágio anterior, só enquanto a transição de bolhas (estilo
    /// Bob Esponja) de troca de estágio está em andamento — ver `handleGoalTransition`.
    @State private var bubbleMascot: String? = nil
    /// true enquanto o mascote NOVO ainda não deve aparecer (ver
    /// `newMascotShowDelay` em `handleGoalTransition`) — sem isso, ele ficaria
    /// vivo por baixo desde o primeiro instante da transição, aparecendo junto
    /// do antigo pelas folgas transparentes da imagem/bolhas.
    @State private var newMascotHidden = false
    /// true enquanto a montagem do mascote (pedrinhas se juntando, ver
    /// `MascotShatterView(assembles:)`) ainda deve rodar. Começa true pra pegar a
    /// abertura do app; volta a true ao voltar do background. Só tem efeito com 0 mL.
    @State private var mascotAssemblyPending = true
    /// Durante a montagem: false enquanto só as pedrinhas soltas aparecem no fundo
    /// (`looseStonesDuration`), true quando os cacos começam a voar e se juntar.
    @State private var mascotAssemblyStarted = false
    /// Tempo (s) que as pedrinhas ficam soltas no fundo antes de serem puxadas pro meio.
    private static let looseStonesDuration: Double = 1.0
    /// Tempo máximo (s) esperando as pedrinhas se juntarem no meio — normalmente elas
    /// chegam antes (`WaterMotion.stonesGathered`) e o mascote já começa a se formar.
    private static let stonesGatherTimeout: Double = 1.5
    /// Tempo (s) que cada fala fica no balão antes de o mascote sortear a próxima.
    private static let idlePhraseInterval: Double = 20

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }

    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }

    private var dailyGoals: [DailyGoal] {
        allDailyGoals.filter { $0.userID == profile.userID }
    }

    /// True once today's temperature adjustment has already been fetched and locked
    /// in (see `DailyGoal.recordToday`) — at that point a fresh WeatherKit call would
    /// only repeat work `recordedAdjustmentML` already covers, so it's skipped. The
    /// only thing this loses is the live humidity reading for the mascot's "dia seco"
    /// flavor line, which isn't persisted — an acceptable trade for not re-fetching.
    private var isTodaysAdjustmentLocked: Bool {
        let key = DailyGoal.dayKey(for: .now)
        return dailyGoals.first { $0.dayKey == key }?.adjustmentLocked ?? false
    }

    /// Mesma meta da barra de progresso da Home (base + ajuste de temperatura).
    private var effectiveGoalML: Int {
        HydrationMath.effectiveGoalML(
            baseGoalML: profile.metaDiariaML,
            tempContext: tempContext,
            recordedAdjustmentML: DailyGoalResolver.recordedAdjustmentML(in: dailyGoals, on: .now)
        )
    }

    /// Past days are judged against the goal recorded for them, not today's.
    private var goalResolver: DailyGoalResolver {
        DailyGoalResolver(goals: dailyGoals, todayGoalML: effectiveGoalML, fallbackGoalML: profile.metaDiariaML)
    }

    private var progress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(effectiveGoalML))
    }

    // MARK: - Falas do mascote

    /// Situação de agora, que decide quais falas o mascote pode soltar.
    private var phraseContext: MascotPhraseContext {
        let lastLog = todayLogs.max { $0.timestamp < $1.timestamp }
        let stage = AppTheme.mascotStage(for: progress)

        var keptStage = false
        if let lastLog, effectiveGoalML > 0 {
            let before = Double(consumedToday - lastLog.volumeML) / Double(effectiveGoalML)
            keptStage = AppTheme.mascotStage(for: max(0, before)) == stage
        }

        return MascotPhraseContext(
            stage: stage,
            hour: Calendar.current.component(.hour, from: .now),
            lastIntakeWasGole: (lastLog?.volumeML ?? .max) <= Constants.IntakePreset.gole.volumeML,
            lastIntakeKeptStage: keptStage,
            isDryDay: (tempContext?.humidityPct ?? .infinity) < Constants.mascotDryHumidityPct
        )
    }

    /// Sorteia a próxima fala, sem repetir a que já está no balão quando há outra.
    private func pickIdlePhrase() {
        let options = MascotPhrases.idle(in: phraseContext)
        idlePhrase = options.filter { $0 != idlePhrase }.randomElement() ?? options.randomElement() ?? ""
    }

    /// Mostra `phrase` no balão por `seconds`; uma nova fala substitui a anterior.
    private func say(_ phrase: String, for seconds: Double) {
        overridePhrase = phrase
        overridePhraseReset?.cancel()
        overridePhraseReset = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            overridePhrase = nil
        }
    }

    /// Sequência de dias batendo a meta. Em `@State`, não computada a cada acesso:
    /// `currentStreak` caminha até 365 dias e o `body` a lê seis vezes (cabeçalho,
    /// duas sheets, `activeGame`, `runningGame` e o próprio `onChange`) — e o
    /// `GeometryReader` do aquário refaz o conteúdo a cada frame durante o arrasto
    /// entre Home e Histórico, o mesmo motivo que levou `TodayIntake` e
    /// `MonthSummary` a serem calculados uma vez por atualização.
    @State private var streak = 0

    private func recomputeStreak() {
        let totals = HydrationMath.totalsByDay(allLogs.filter { $0.userID == profile.userID })
        streak = HydrationMath.currentStreak(totalsByDay: totals, goalML: goalResolver.goalML(on:))
    }

    var body: some View {
        GeometryReader { geo in
            topSection(height: geo.size.height, width: geo.size.width)
        }
        .task {
            guard tempContext == nil, !isTodaysAdjustmentLocked else { return }
            tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
        }
        .sheet(isPresented: $showShare) {
            ShareProgressView(snapshot: ShareProgressSnapshot(consumedML: consumedToday, goalML: effectiveGoalML, streakDias: streak))
                .trackSheetLifecycle(.shareProgress, screen: screen, userID: profile.userID)
        }
        .sheet(isPresented: $showMiniGames) { MiniGamesView(streak: streak) }
        .onChange(of: runningGame, initial: true) { oldGame, newGame in
            miniGames.runningGame = newGame
            handleMiniGame(from: oldGame, to: newGame, isLiveTransition: oldGame != newGame)
        }
        .onChange(of: goalReached, initial: true) { wasReached, isReached in
            guard isReached else {
                showsGoalReached = false
                miniGames.playsOnDemand = false
                return
            }
            // Abrindo o app já com a meta batida (`initial`, sem mudança): sem comemoração.
            guard !wasReached else {
                showsGoalReached = true
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(Self.goalCelebrationDuration))
                guard goalReached else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showsGoalReached = true }
            }
        }
        .onChange(of: isMascotAnimating, initial: true) { _, isAnimating in
            miniGames.isMascotAnimating = isAnimating
        }
        .onChange(of: streak, initial: true) { _, newStreak in
            announceNewlyUnlockedGames(streak: newStreak)
        }
        // Entradas da sequência: registros do usuário (incluídos/excluídos, aqui ou em
        // outra tela) e a meta do dia, que muda quando a previsão do clima chega.
        .onChange(of: allLogs.count, initial: true) { recomputeStreak() }
        .onChange(of: effectiveGoalML) { recomputeStreak() }
        .syncedFetch($allLogs, context: modelContext) {
            let userID = profile.userID
            let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
            return FetchDescriptor<IntakeLog>(
                predicate: #Predicate { $0.userID == userID && $0.timestamp >= cutoff },
                sortBy: [SortDescriptor(\.timestamp)]
            )
        }
        .syncedFetch($allDailyGoals, context: modelContext) {
            let userID = profile.userID
            let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
            let cutoffKey = DailyGoal.dayKey(for: cutoff)
            return FetchDescriptor<DailyGoal>(
                predicate: #Predicate { $0.userID == userID && $0.dayKey >= cutoffKey },
                sortBy: [SortDescriptor(\.dayKey)]
            )
        }
    }

    // MARK: - Subviews

    /// Na tela do minijogo (Home com os botões do jogo) o cabeçalho só tem o botão de volta
    /// pra ingestão (seta pra trás, à esquerda) e o de minijogos.
    private var isGameLayout: Bool { miniGames.showsGameControls && screen == .home }

    private var miniGamesButton: some View {
        GlassCircleButton(systemImage: "gamecontroller.fill", accessibilityLabel: "Minijogos") {
            Haptic.tap.play()
            InteractionTracker.log("\(screen.rawValue)_minigames_tap", screen: screen, userID: profile.userID, context: modelContext)
            showMiniGames = true
        }
    }

    /// Configurações e a sequência à esquerda; minijogos e compartilhar à direita.
    @ViewBuilder
    private var headerRow: some View {
        if isGameLayout {
            HStack(spacing: 8) {
                // Sai do jogo: escolhe "Sem jogo" (nem a meta batida traz o jogo de volta, só a aba
                // de minijogos) e os cartões de ingestão voltam.
                GlassCircleButton(systemImage: "chevron.left", accessibilityLabel: "Sair do jogo") {
                    Haptic.tap.play()
                    InteractionTracker.log("\(screen.rawValue)_minigame_back_to_intake_tap", screen: screen, userID: profile.userID, context: modelContext)
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        selectedGameRaw = MiniGame.noGame.rawValue
                        miniGames.playsOnDemand = false
                    }
                }
                .accessibilityHint("Escolhe Sem jogo e volta pros botões de registrar água")

                Spacer()

                miniGamesButton
            }
        } else {
            HStack(spacing: 8) {
                GlassCircleButton(systemImage: "gear", accessibilityLabel: "Configurações") {
                    Haptic.tap.play()
                    InteractionTracker.log("\(screen.rawValue)_configuration_tap", screen: screen, userID: profile.userID, context: modelContext)
                    onOpenProfile()
                }

                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.appAccentText)
                    Text("\(streak)")
                        .font(AppFont.subheadlineStrong)
                    Text("dias")
                        .font(AppFont.subheadline)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .accessibilityElement(children: .combine)

                Spacer()

                miniGamesButton

                GlassCircleButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Compartilhar") {
                    Haptic.tap.play()
                    InteractionTracker.log("\(screen.rawValue)_share_tap", screen: screen, userID: profile.userID, context: modelContext)
                    showShare = true
                }
            }
        }
    }

    // MARK: - Água

    private var goalReached: Bool { progress >= 1 }

    /// Opção escolhida na aba de minijogos, entre as que a streak já liberou. Batendo a meta,
    /// a streak de hoje já conta, então um jogo liberado agora entra na mesma hora.
    private var activeGame: MiniGame { MiniGame.active(selected: selectedGameRaw, streak: streak) }

    /// Jogo rodando agora no aquário: com a meta batida (depois da comemoração, ver
    /// `showsGoalReached`), ou quando o usuário escolheu jogar pela aba de minijogos (com a
    /// streak mínima); nunca o `.noGame`.
    private var runningGame: MiniGame? {
        let playsNow = (goalReached && showsGoalReached) || (miniGames.playsOnDemand && streak >= MiniGame.minimumStreakToPlay)
        return playsNow && activeGame.isPlayable ? activeGame : nil
    }

    /// Jogando pela aba antes de bater a meta: o mascote ainda existe e sai de cena enquanto isso.
    private var hidesMascotForGame: Bool { runningGame != nil && !goalReached }

    /// Animação do mascote rodando: a montagem do início do dia (0 mL), as bolhas de troca de
    /// estágio ao passar de um marco de água e a explosão/comemoração da meta batida.
    private var isMascotAnimating: Bool {
        (mascotAssemblyPending && consumedToday == 0 && !hidesMascotForGame)
            || bubbleMascot != nil
            || explodingMascot != nil
            || (goalReached && !showsGoalReached)
    }

    private var containerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 32, bottomTrailingRadius: 32, topTrailingRadius: 32, style: .continuous)
    }

    private func topSection(height: CGFloat, width: CGFloat) -> some View {
        // Recipiente: enche de água conforme o progresso do dia. O cabeçalho fica fora do
        // conteúdo da água: a refração achata o conteúdo numa imagem e o vidro dos botões
        // deixa de enxergar o fundo (fica escuro).
        mascotPlaceholder(height: TabScreenLayout.mascotHeight(forWaterHeight: height), width: width)
            .opacity(hidesMascotForGame ? 0 : 1)
            .allowsHitTesting(!hidesMascotForGame)
            .animation(.easeInOut(duration: 0.3), value: hidesMascotForGame)
            // Esse respiro abaixo do mascote (antes do `.frame` de altura fixa, pra
            // não aumentar a altura total do recipiente) é o que o afasta do fundo.
            .padding(.bottom, TabScreenLayout.mascotBottomPadding)
            .frame(maxWidth: .infinity)
            // `.bottom` (não `.center`): a altura do recipiente que sobra vira espaço de
            // água acima do mascote, em vez de empurrar o mascote pra cima do centro.
            .frame(height: height, alignment: .bottom)
            // Meta do dia batida: os rins aparecem nos cantos de baixo comemorando.
            // Ficam, como o resto, dentro da água.
            .overlay(alignment: .bottom) {
                if goalReached {
                    KidneyCheerView()
                        .frame(height: 80)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: goalReached)
            // Minijogo: no conteúdo do recipiente, então passa pela mesma refração da água.
            // Os botões ficam na Home; só as Bolhas Coloridas (mirar e atirar) e a Gota Voadora
            // (nadar) recebem toque aqui.
            .overlay {
                Group {
                    switch runningGame {
                    case .rings:
                        RingGameView(simulation: miniGames.ringGame, water: waterMotion)
                    case .jump:
                        JumpGameView(simulation: miniGames.jumpGame, water: waterMotion)
                    case .bubbles:
                        BubbleGameView(simulation: miniGames.bubbleGame, water: waterMotion)
                    case .flappy:
                        FlappyGameView(simulation: miniGames.flappyGame, water: waterMotion)
                    case .noGame, nil:
                        EmptyView()
                    }
                }
                .allowsHitTesting(runningGame == .bubbles || runningGame == .flappy)
                .transition(.opacity)
            }
        .background {
            containerShape
                .fill(AppTheme.screenBackground(for: colorScheme))
                .allowsHitTesting(false)
        }
        .waterContainer(
            level: progress,
            in: containerShape,
            motion: waterMotion
        )
        // Os botões flutuam por cima do recipiente (fora do `.waterContainer`, então não
        // passam pela refração da água — senão o vidro dos botões ficaria escuro).
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                headerRow
                if let game = unlockedGameBanner {
                    Button {
                        Haptic.tap.play()
                        unlockedGameBanner = nil
                        showMiniGames = true
                    } label: {
                        MiniGameUnlockedBanner(game: game)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre os minijogos")
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(TabScreenLayout.containerInset)
            // Travados enquanto o mascote anima (montagem, bolhas, explosão da meta).
            .allowsHitTesting(!isMascotAnimating)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: unlockedGameBanner)
        }
    }

    private func mascotPlaceholder(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if mascotAssemblyPending, consumedToday == 0, let assembling = AppTheme.mascotImageName(for: 0) {
                // Abrindo o app com 0 mL: o inverso da explosão — os cacos sobem e se
                // juntam no meio, formando o primeiro mascote. Mesmo tamanho/correção
                // do mascote vivo, então a troca pro ramo de baixo no fim é invisível.
                // Antes disso, as pedrinhas ficam soltas no fundo por
                // `looseStonesDuration`, são puxadas pro meio e, assim que se juntam
                // (`WaterMotion.stonesGathered`), somem e os cacos se abrem dali.
                let correction = AppTheme.mascotSizeCorrection(for: assembling)
                ZStack {
                    if mascotAssemblyStarted {
                        MascotShatterView(imageName: assembling, width: height * 1.55 * correction, height: height * correction, assembles: true)
                    }
                }
                .frame(width: height * 1.55, height: height, alignment: .center)
                .allowsHitTesting(false)
                .task {
                    waterMotion.scatterStonesAtRest()
                    try? await Task.sleep(for: .seconds(Self.looseStonesDuration))
                    waterMotion.gatherStones(heightAboveBottom: TabScreenLayout.mascotBottomPadding + height / 2)
                    let gatherStart = Date.now
                    while !waterMotion.stonesGathered, Date.now.timeIntervalSince(gatherStart) < Self.stonesGatherTimeout {
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    waterMotion.clearStones()
                    mascotAssemblyStarted = true
                    try? await Task.sleep(for: .seconds(MascotShatterView.assembleDuration))
                    Haptic.primary.play()
                    mascotAssemblyPending = false
                    mascotAssemblyStarted = false
                }
            } else if let mascot = AppTheme.mascotImageName(for: progress), !newMascotHidden {
                Image(mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    // Slot de layout com largura e altura fixas, iguais para todos os
                    // mascotes: sem isso, cada imagem (recortada no seu próprio contorno,
                    // com proporção diferente) mudava o tamanho da ZStack e fazia o
                    // mascote "saltar" de posição ao trocar de estágio.
                    .frame(width: height * 1.55, height: height, alignment: .center)
                    .scaleEffect(
                        x: AppTheme.mascotSizeCorrection(for: mascot) * (isPoking ? 1.18 : 1.0),
                        y: AppTheme.mascotSizeCorrection(for: mascot) * (isPoking ? 0.82 : 1.0),
                        anchor: .center
                    )
                    // Precisa ser explícita (igual à de `mascotDragOffset` abaixo): o
                    // `.transaction { animation = nil }` no ZStack pai (pra trocar de
                    // mascote sem crossfade) zera a animação ambiente de toda a
                    // subárvore, incluindo o `withAnimation` do toque em `pokeMascot()`
                    // — sem essa linha, o "cutucão" ficava instantâneo (travado).
                    .animation(.interpolatingSpring(stiffness: 350, damping: 10), value: isPoking)
                    .offset(mascotDragOffset)
                    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.55), value: mascotDragOffset)
                    // Área de toque maior que o desenho: o `scaleEffect` acima encolhe
                    // a imagem (e o toque junto) pra ~55–65% do slot; aqui o toque
                    // volta a valer em 85% do slot, com folga em volta do mascote.
                    .contentShape(Rectangle().scale(0.85))
                    .onTapGesture { pokeMascot() }
                    .simultaneousGesture(mascotDragGesture)

                // Vazio só no primeiro quadro, antes do `onAppear` sortear a fala.
                if let phrase = overridePhrase ?? (idlePhrase.isEmpty ? nil : idlePhrase) {
                    MascotSpeechBubble(text: phrase)
                        .offset(x: 8 + mascotDragOffset.width, y: -38 + mascotDragOffset.height)
                        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.55), value: mascotDragOffset)
                        // Mesmo motivo do `.animation(value: isPoking)` no mascote: precisa
                        // ser explícita pra sobreviver ao `.transaction` do ZStack pai.
                        .animation(.easeInOut(duration: 0.3), value: phrase)
                        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            } else if let exploding = explodingMascot {
                // Mascote1 "quebrando": racha em pedaços que voam pra fora e caem, no
                // instante em que nasce em pedrinhas na água (`waterMotion.explodeIntoStones`).
                // Mesma correção de tamanho do mascote ao vivo (`scaleEffect` acima) —
                // sem ela, a imagem nascia no tamanho cheio da caixa, bem maior do que o
                // mascote normal, e parecia um "zoom" antes de quebrar.
                let correction = AppTheme.mascotSizeCorrection(for: exploding)
                MascotShatterView(imageName: exploding, width: height * 1.55 * correction, height: height * correction)
                    .frame(width: height * 1.55, height: height, alignment: .center)
                    .allowsHitTesting(false)
            } else {
                // Meta batida (ou mascote novo ainda escondido por `newMascotHidden`
                // durante a transição de bolhas): o mascote some, mas a largura fica
                // igual à dos outros branches — sem isso, a ZStack (alignment
                // .topTrailing) perde a referência de largura, encolhe/estica, e o
                // mascote parece "deslizar" de lado quando volta a aparecer.
                Color.clear.frame(width: height * 1.55, height: height)
            }
        }
        // Transição de bolhas ao trocar de estágio (mascote5→mascote4 etc.),
        // estilo Bob Esponja: o mascote ANTIGO fica sobreposto aqui, escondido
        // pela própria view em `oldMascotHideDelay`; o mascote NOVO (ramo acima)
        // só aparece em `newMascotShowDelay` — os dois tempos são independentes,
        // ver `handleGoalTransition`. Em `.overlay` (não dentro da ZStack de cima)
        // pra poder usar a largura cheia do recipiente (`width`, bem maior que a
        // caixa do mascote) sem fazer a ZStack de cima — que usa esse mesmo
        // tamanho pra alinhar o mascote com `.topTrailing` — mudar de largura e
        // deslocar o mascote. Independe do nível de água real, então funciona
        // igual com o recipiente cheio ou quase vazio.
        .overlay {
            if let bubbling = bubbleMascot {
                MascotBubbleTransitionView(imageName: bubbling, width: width, height: height, revealDelay: Self.oldMascotHideDelay)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)
            }
        }
        // Sem isso, a troca de ramo acima (mascote vivo → quebrando → vazio) herdava
        // a animação de 1,2s do nível da água (`WaterRefractionView`, que envolve todo
        // esse conteúdo) e o SwiftUI fazia um crossfade longo entre os dois: dava pra
        // ver o mascote inteiro parado atrás, com o balão, sumindo devagar por trás do
        // mascote quebrando. Com a animação ambiente cancelada aqui, a troca é instantânea
        // — só a física dos cacos (que tem sua própria `.animation` explícita) continua animada.
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            pickIdlePhrase()
            // `.onChange` abaixo só dispara numa transição ao vivo: se o app abre
            // já com a meta batida (de uma sessão anterior), ele nunca viu o
            // cruzamento, e sem isso o recipiente ficava vazio — nem mascote, nem
            // pedrinhas. Aqui o estado das pedrinhas é sincronizado com o progresso
            // atual assim que a tela aparece.
            syncStonesWithProgress()
            // Já abriu com água registrada: não há montagem, e ela não deve disparar
            // depois só porque um registro foi excluído e o total voltou a 0.
            if consumedToday > 0 { mascotAssemblyPending = false }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Voltar do background conta como "abrir o app" de novo.
            if oldPhase == .background, newPhase != .background, consumedToday == 0 {
                mascotAssemblyPending = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.idlePhraseInterval))
                guard overridePhrase == nil else { continue }
                pickIdlePhrase()
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            handleGoalTransition(from: oldValue, to: newValue)
        }
        // Mudou de estágio: a fala do balão passa a ser do estágio novo.
        .onChange(of: AppTheme.mascotStage(for: progress)) { pickIdlePhrase() }
        // Chegou o clima do dia (ou mudou a hora): libera as falas de "dia seco".
        .onChange(of: tempContext?.humidityPct) { pickIdlePhrase() }
        // Registrou água (por qualquer origem): o mascote reclama por alguns segundos.
        .onChange(of: consumedToday) { oldValue, newValue in
            guard newValue > oldValue, let reaction = MascotPhrases.drinkReactions.randomElement() else { return }
            say(reaction, for: 3)
        }
    }

    /// Garante que as pedrinhas batem com o progresso atual ao abrir a tela —
    /// sem explosão (isso só acontece ao vivo, em `handleGoalTransition`).
    private func syncStonesWithProgress() {
        if progress >= 1.0, runningGame == nil {
            waterMotion.explodeIntoStones()
        } else {
            waterMotion.clearStones()
        }
    }

    /// Ao bater a meta (mascote1 → nenhum mascote), ele "explode": primeiro quebra
    /// (`MascotShatterView`) e só quando essa quebra está quase no fim é que nascem
    /// as pedrinhas que caem no fundo do recipiente — uma depois da outra, não as
    /// duas coisas ao mesmo tempo. Se a meta deixar de estar batida (ex.: novo dia),
    /// as pedrinhas somem para o mascote voltar do zero. Entre estágios intermediários
    /// (mascote5→mascote4 etc., pra cima ou pra baixo, ex. ao excluir um registro),
    /// a transição de bolhas (`MascotBubbleTransitionView`) cobre a troca.
    /// Tempo (s) até a imagem do mascote ANTIGO (dentro da cortina de bolhas)
    /// desaparecer. Independente de `newMascotShowDelay` — pode ser maior,
    /// menor ou igual.
    private static let oldMascotHideDelay: Double = 0.75
    /// Tempo (s) até a imagem do mascote NOVO (por baixo de tudo) passar a
    /// aparecer. Independente de `oldMascotHideDelay` — se for menor, o novo
    /// aparece ANTES do antigo sumir (os dois ficam visíveis juntos por um
    /// tempo, sobrepostos pelas bolhas); se for maior, há um intervalo em que
    /// nenhum dos dois aparece (só a cortina de bolhas, sem mascote atrás).
    private static let newMascotShowDelay: Double = 0.75
    /// Tempo (ms) que a view de bolhas inteira continua montada antes de ser
    /// descartada. Deve ficar sempre >= o maior dos dois tempos acima, somado
    /// à maior duração de subida de bolha (`riseDuration` em
    /// `MascotBubbleTransitionView`), senão a animação é cortada antes do fim.
    private static let mascotBubbleTotalDuration: Int = 1900

    private func handleGoalTransition(from oldValue: Double, to newValue: Double) {
        let oldMascot = AppTheme.mascotImageName(for: oldValue)
        let newMascot = AppTheme.mascotImageName(for: newValue)

        if oldValue < 1.0, newValue >= 1.0, let mascot = oldMascot {
            explodingMascot = mascot
            Haptic.celebrate.play()
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                // Com um minijogo rodando, as pedrinhas não ficam soltas no aquário.
                if runningGame == nil { waterMotion.explodeIntoStones() }
                try? await Task.sleep(for: .milliseconds(160))
                explodingMascot = nil
            }
        } else if oldValue >= 1.0, newValue < 1.0 {
            waterMotion.clearStones()
        } else if let old = oldMascot, let new = newMascot, old != new, newValue > oldValue {
            bubbleMascot = old
            newMascotHidden = true
            Haptic.bubbles(cover: Self.oldMascotHideDelay, total: Double(Self.mascotBubbleTotalDuration) / 1000).play()
            Task {
                try? await Task.sleep(for: .milliseconds(Int(Self.newMascotShowDelay * 1000)))
                newMascotHidden = false
            }
            Task {
                try? await Task.sleep(for: .milliseconds(Self.mascotBubbleTotalDuration))
                bubbleMascot = nil
            }
        }
    }

    /// Liga o minijogo escolhido quando a meta é batida (ou quando o usuário troca de jogo com
    /// ela batida) e desliga os outros. Ao vivo, `runningGame` só muda depois da comemoração da
    /// meta (`goalCelebrationDuration`); ao abrir o app já com a meta batida, entra direto. Com um jogo rodando as pedrinhas somem
    /// do aquário; voltando pro "Sem jogo" com a meta batida, elas voltam pro fundo.
    private func handleMiniGame(from oldGame: MiniGame?, to newGame: MiniGame?, isLiveTransition: Bool) {
        if newGame != .rings { miniGames.ringGame.stop() }
        if newGame != .jump { miniGames.jumpGame.stop() }
        if newGame != .bubbles { miniGames.bubbleGame.stop() }
        if newGame != .flappy { miniGames.flappyGame.stop() }

        guard let newGame else {
            if goalReached, oldGame != nil { waterMotion.scatterStonesAtRest() }
            return
        }
        waterMotion.clearStones()
        miniGames.ringGame.onRoundComplete = {
            Haptic.success.play()
            InteractionTracker.log("ring_game_round_complete", screen: screen, userID: profile.userID, context: modelContext)
        }
        miniGames.jumpGame.onGameOver = { score in
            let best = UserDefaults.standard.integer(forKey: MiniGame.jumpBestStorageKey)
            (score > best ? Haptic.success : Haptic.warning).play()
            UserDefaults.standard.set(max(best, score), forKey: MiniGame.jumpBestStorageKey)
            InteractionTracker.log("jump_game_over", screen: screen, userID: profile.userID, context: modelContext)
        }
        miniGames.bubbleGame.onGameOver = { score in
            let best = UserDefaults.standard.integer(forKey: MiniGame.bubblesBestStorageKey)
            (score > best ? Haptic.success : Haptic.warning).play()
            UserDefaults.standard.set(max(best, score), forKey: MiniGame.bubblesBestStorageKey)
            InteractionTracker.log("bubbles_game_over", screen: screen, userID: profile.userID, context: modelContext)
        }
        miniGames.flappyGame.onGameOver = { score in
            let best = UserDefaults.standard.integer(forKey: MiniGame.flappyBestStorageKey)
            (score > best ? Haptic.success : Haptic.warning).play()
            UserDefaults.standard.set(max(best, score), forKey: MiniGame.flappyBestStorageKey)
            InteractionTracker.log("flappy_game_over", screen: screen, userID: profile.userID, context: modelContext)
        }
        // A comemoração da meta já acabou quando o jogo chega aqui (`showsGoalReached`): só
        // espera o aquário esticar pra tela do jogo.
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard runningGame == newGame else { return }
            switch newGame {
            case .rings: miniGames.ringGame.start()
            case .jump: miniGames.jumpGame.start()
            case .bubbles: miniGames.bubbleGame.start()
            case .flappy: miniGames.flappyGame.start()
            case .noGame: return
            }
            if isLiveTransition {
                InteractionTracker.log("\(newGame.rawValue)_game_start", screen: screen, userID: profile.userID, context: modelContext)
            }
        }
    }

    /// Streak subiu e liberou jogo(s) que o usuário ainda não viu: o mais novo passa a ser o
    /// escolhido (é ele que entra ao bater a meta) e aparece o aviso no topo do aquário.
    /// Cada jogo é anunciado uma vez só, mesmo que a streak zere e volte a liberá-lo.
    private func announceNewlyUnlockedGames(streak: Int) {
        let announced = Set(announcedGamesRaw.split(separator: ",").map(String.init))
        let fresh = MiniGame.unlocked(streak: streak).filter { !announced.contains($0.rawValue) }
        guard let newest = fresh.last else { return }
        announcedGamesRaw = announced.union(fresh.map(\.rawValue)).sorted().joined(separator: ",")
        selectedGameRaw = newest.rawValue
        InteractionTracker.log("minigame_unlocked_\(newest.rawValue)", screen: screen, userID: profile.userID, context: modelContext)
        Task {
            // Deixa a explosão do mascote acontecer antes do aviso aparecer.
            try? await Task.sleep(for: .seconds(Self.gameStartDelay))
            Haptic.celebrate.play()
            unlockedGameBanner = newest
            try? await Task.sleep(for: .seconds(4))
            if unlockedGameBanner == newest { unlockedGameBanner = nil }
        }
    }

    private func pokeMascot() {
        // A curva vem do `.animation(value: isPoking)` junto do `scaleEffect` —
        // só precisa setar o valor aqui.
        isPoking = true
        Task {
            try? await Task.sleep(for: .milliseconds(130))
            isPoking = false
        }

        pokeCount += 1

        if pokeCount >= 3 {
            Haptic.warning.play() // o mascote reclama
            pokeCount = 0
            say(MascotPhrases.pokeComplaints.randomElement() ?? "", for: 4)
        } else {
            Haptic.poke.play()
            say(MascotPhrases.pokes.randomElement() ?? "", for: 2.5)
        }
    }

    /// Arrastar o mascote: ele acompanha o dedo dentro de um raio curto e, ao soltar,
    /// a mola o traz de volta à posição original — sempre dentro do recipiente. O
    /// movimento também empurra a superfície da água (mesmo `WaterMotion` do
    /// `waterContainer`), como se o mascote estivesse mergulhado nela.
    private var mascotDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($mascotDragOffset) { value, state, _ in
                state = CGSize(
                    width: clampedDrag(value.translation.width, limit: 110),
                    height: clampedDrag(value.translation.height, limit: 45)
                )
            }
            .onChanged { value in
                let deltaX = value.translation.width - lastMascotDragTranslation.width
                let deltaY = value.translation.height - lastMascotDragTranslation.height
                lastMascotDragTranslation = value.translation
                disturbWaterFromDrag(deltaX: deltaX, deltaY: deltaY)
            }
            .onEnded { value in
                // Soltar "chacoalha" a água com força proporcional a quão longe o
                // mascote tinha ido, na direção em que ele está voltando para o centro.
                disturbWaterFromDrag(deltaX: -value.translation.width * 0.6, deltaY: -value.translation.height * 0.6)
                // Só arrasto de verdade solta a "marola"; o toque simples já vibra em `pokeMascot()`.
                if hypot(value.translation.width, value.translation.height) > 12 { Haptic.ripple.play() }
                lastMascotDragTranslation = .zero
            }
    }

    private func clampedDrag(_ translation: CGFloat, limit: CGFloat) -> CGFloat {
        max(-limit, min(limit, translation))
    }

    private func disturbWaterFromDrag(deltaX: CGFloat, deltaY: CGFloat) {
        let magnitude = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        guard magnitude > 0.01 else { return }
        let sign: CGFloat = deltaY >= 0 ? 1 : -1
        let strength = Float(magnitude * sign) * WaterTuning.dragPushGain
        waterMotion.disturb(atU: 0.5, strength: strength)
    }
}
