import AVFoundation
import SwiftData
import SwiftUI


struct HomeView: View {
    let profile: UserProfile
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Medidas que acompanham o tamanho do texto: com Dynamic Type grande o rótulo da barra
    // e o ícone do cabeçalho não podem ser cortados por uma altura fixa.
    @ScaledMetric(relativeTo: .subheadline) private var progressBarHeight: CGFloat = 52
    private let headerButtonSize = TabScreenLayout.headerHeight // alvo mínimo de 44 pt; não cresce com o texto
    @Query private var allLogs: [IntakeLog]
    @Query private var allDailyGoals: [DailyGoal]
    @State private var isLogging = false
    @State private var highlightedCard: String? = nil
    @State private var audioPlayer: AVAudioPlayer?
    @State private var pendingDeleteLog: IntakeLog?
    @State private var isEditingCustomAmount = false
    @State private var showSiriTutorial = false
    @State private var showActionButtonTutorial = false
    @State private var showTodayLogs = false
    @State private var showShare = false
    @State private var weather: WeatherContext?
    @State private var isLoadingWeather = true
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var phraseIndex: Int = 0
    @State private var pokeCount: Int = 0
    @State private var isPoking: Bool = false
    @State private var overridePhrase: String? = nil
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

    private static let mascotPhrases: [String] = [
        "Não bebe água não",
        "Você nem sente sede né?",
        "Amo a sensação de boca seca!"
        
    ]

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }
    
    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }
    
    private var dailyGoals: [DailyGoal] {
        allDailyGoals.filter { $0.userID == profile.userID }
    }

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
    
    private var streak: Int {
        HydrationMath.currentStreak(allLogs.filter { $0.userID == profile.userID }, goalML: goalResolver.goalML(on:))
    }
    
    var body: some View {
        ZStack {
            AppTheme.screenBackground(for: colorScheme)
                .ignoresSafeArea()
            
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: TabScreenLayout.spacing) {
                        topSection(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height), width: geo.size.width - 20)
                            .padding(.horizontal, 10)

                        progressBarButton
                            .padding(.horizontal, 20)

                        intakeGrid(cardHeight: intakeCardHeight(forVisibleHeight: geo.size.height))
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, TabScreenLayout.spacing)
                    .disableScrollBounce()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task { await loadWeather() }
        // Keeps the Home Screen water tank widget filling against the same goal as the bar,
        // and snapshots it as today's goal so later edits never touch this day.
        .onChange(of: effectiveGoalML, initial: true) { _, goal in
            WidgetSync.saveEffectiveGoal(goal)
            DailyGoal.recordToday(userID: profile.userID, baseGoalML: profile.metaDiariaML, adjustmentML: tempContext?.adjustmentML, context: modelContext)
        }
        .onAppear {
            guard tempContext == nil else { return }
            Task {
                tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
            }
        }
        .confirmationDialog(
            "Excluir este registro?",
            isPresented: isPresentingDeleteConfirm,
            presenting: pendingDeleteLog
        ) { log in
            Button("Excluir", role: .destructive) { deleteLog(log) }
            Button("Cancelar", role: .cancel) {}
        } message: { log in
            Text("\(log.tipoEntrada.capitalized) · \(log.volumeML) mL será removido do seu histórico e da base de dados.")
        }
        .sheet(isPresented: $isEditingCustomAmount) {
            CustomIntakeEditorView(initialValueML: profile.customIntakeML, onSave: saveCustomAmount)
                .trackSheetLifecycle(.customAmountEditor, screen: .home, userID: profile.userID)
        }
        .sheet(isPresented: $showSiriTutorial) { SiriTutorialView() }
        .sheet(isPresented: $showShare) {
            ShareProgressView(snapshot: ShareProgressSnapshot(consumedML: consumedToday, goalML: effectiveGoalML, streakDias: streak))
                .trackSheetLifecycle(.shareProgress, screen: .home, userID: profile.userID)
        }
        .sheet(isPresented: $showActionButtonTutorial) { ActionButtonTutorialView() }
        .sheet(isPresented: $showTodayLogs) {
            // Same goal as the bar (base + temperature adjustment), so the sheet's
            // "X mL de Y mL" matches what the user just tapped.
            DayDetailSheet(
                dia: DiaHistorico(date: .now, percentualMeta: progress),
                metaDiariaML: effectiveGoalML,
                userID: profile.userID,
                calendar: .current
            )
        }
    }
    
    // MARK: - Subviews
    
    private var headerRow: some View {
        HStack {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.clear)

            Spacer()

            Button {
                InteractionTracker.log("home_share_tap", screen: .home, userID: profile.userID, context: modelContext)
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(.subheadline, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // o ícone cabe no círculo de 44 pt
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: headerButtonSize, height: headerButtonSize)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Compartilhar")
        }
    }
    
    private let intakeGridSpacing: CGFloat = 12

    /// The two rows of intake cards share what's left below the progress bar, so the
    /// grid ends `TabScreenLayout.spacing` above the tab bar.
    private func intakeCardHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        let gridHeight = TabScreenLayout.contentHeight(forVisibleHeight: height) - progressBarHeight - TabScreenLayout.spacing
        return max((gridHeight - intakeGridSpacing) / 2, 116)
    }

    private var containerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 32, bottomTrailingRadius: 32, topTrailingRadius: 32, style: .continuous)
    }

    private func topSection(height: CGFloat, width: CGFloat) -> some View {
        // Recipiente: vai do topo da tela até logo acima da barra de progresso e
        // enche de água conforme o progresso do dia.
        // O cabeçalho fica fora do conteúdo da água: a refração achata o conteúdo
        // numa imagem e o vidro dos botões deixa de enxergar o fundo (fica escuro).
        mascotPlaceholder(height: TabScreenLayout.mascotHeight(forWaterHeight: height), width: width)
            // Esse respiro abaixo do mascote (antes do `.frame` de altura fixa, pra
            // não aumentar a altura total do recipiente) é o que o afasta do fundo.
            .padding(.bottom, TabScreenLayout.mascotBottomPadding)
            .frame(maxWidth: .infinity)
            // `.bottom` (não `.center`): a altura extra do recipiente (reclamada do
            // cabeçalho) vira espaço de água acima do mascote, em vez de se dividir
            // igual entre cima e baixo e empurrar o mascote pra cima do centro.
            .frame(height: height, alignment: .bottom)
        .background {
            containerShape
                .fill(AppTheme.screenBackground(for: colorScheme))
        }
        .waterContainer(
            level: progress,
            in: containerShape,
            bleedsIntoTopSafeArea: true,
            motion: waterMotion
        )
        // Streak e botão de compartilhar flutuam por cima do recipiente (fora do
        // `.waterContainer`, então não passam pela refração da água — senão o vidro
        // dos botões perderia a transparência e ficaria escuro).
        .overlay(alignment: .top) {
            headerRow
                .padding(.horizontal, 10)
                .padding(.top, 14)
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                    .onTapGesture { pokeMascot() }
                    .simultaneousGesture(mascotDragGesture)

                MascotSpeechBubble(text: overridePhrase ?? Self.mascotPhrases[phraseIndex])
                    .offset(x: 8 + mascotDragOffset.width, y: -38 + mascotDragOffset.height)
                    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.55), value: mascotDragOffset)
                    // Mesmo motivo do `.animation(value: isPoking)` no mascote: precisa
                    // ser explícita pra sobreviver ao `.transaction` do ZStack pai.
                    .animation(.easeInOut(duration: 0.3), value: overridePhrase ?? Self.mascotPhrases[phraseIndex])
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            } else if let exploding = explodingMascot {
                // Mascote1 "quebrando": racha em pedaços que voam pra fora e caem, no
                // instante em que nasce em pedrinhas na água (`waterMotion.explodeIntoStones`).
                // Mesma correção de tamanho do mascote ao vivo (`scaleEffect` acima) —
                // sem ela, a imagem nascia no tamanho cheio da caixa, bem maior do que o
                // mascote normal, e parecia um "zoom" antes de quebrar.
                let correction = AppTheme.mascotSizeCorrection(for: exploding)
                MascotShatterView(imageName: exploding, width: height * 1.55 * correction, height: height * correction)
                    .frame(width: height * 1.55, height: height, alignment: .center)
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
            phraseIndex = Int.random(in: 0..<Self.mascotPhrases.count)
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
                try? await Task.sleep(for: .seconds(6))
                guard overridePhrase == nil else { continue }
                phraseIndex = (phraseIndex + 1) % Self.mascotPhrases.count
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            handleGoalTransition(from: oldValue, to: newValue)
        }
    }

    /// Garante que as pedrinhas batem com o progresso atual ao abrir a tela —
    /// sem explosão (isso só acontece ao vivo, em `handleGoalTransition`).
    private func syncStonesWithProgress() {
        if progress >= 1.0 {
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
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                waterMotion.explodeIntoStones()
                try? await Task.sleep(for: .milliseconds(160))
                explodingMascot = nil
            }
        } else if oldValue >= 1.0, newValue < 1.0 {
            waterMotion.clearStones()
        } else if let old = oldMascot, let new = newMascot, old != new, newValue > oldValue {
            bubbleMascot = old
            newMascotHidden = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func pokeMascot() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // A curva vem do `.animation(value: isPoking)` junto do `scaleEffect` —
        // só precisa setar o valor aqui.
        isPoking = true
        Task {
            try? await Task.sleep(for: .milliseconds(130))
            isPoking = false
        }

        pokeCount += 1

        if pokeCount >= 3 {
            pokeCount = 0
            overridePhrase = "Para de me cutucar zé mané"
            Task {
                try? await Task.sleep(for: .seconds(4))
                overridePhrase = nil
            }
        } else {
            phraseIndex = (phraseIndex + 1) % Self.mascotPhrases.count
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

    /// Tapping the bar opens today's intake logs (same sheet as a day in Histórico).
    private var progressBarButton: some View {
        Button {
            InteractionTracker.log("home_progress_bar_tap", screen: .home, userID: profile.userID, context: modelContext)
            showTodayLogs = true
        } label: {
            progressBar
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Consumo de hoje: \(consumedToday) de \(effectiveGoalML) mililitros")
        .accessibilityHint("Mostra os registros de hoje")
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let barWidth = max(geo.size.width * progress, 56)
            
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
                    .fill(Color.appAccent)
                    .frame(width: barWidth, height: progressBarHeight)
                    .animation(.easeOut(duration: 0.4), value: progress)
                
                // Texto sempre branco, sobre a trilha e sobre o preenchimento.
                progressLabel(color: .white)

                // Indica que a barra é tocável (abre os registros de hoje).
                // Nos tamanhos de acessibilidade o texto ocupa a barra toda e o ícone passaria
                // por cima dele; a barra continua tocável (rótulo e dica no botão).
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "info.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 18)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: progressBarHeight)
    }
    
    private func progressLabel(color: Color) -> some View {
        Text("\(consumedToday) mL / \(effectiveGoalML) mL")
            .font(AppFont.subheadlineHeavy)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75) // 15 pt × 0.75 ≈ 11 pt: o menor texto do app (HIG)
            .padding(.leading, 18)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 18 : 52)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intakeGrid(cardHeight: CGFloat) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: intakeGridSpacing), GridItem(.flexible(), spacing: intakeGridSpacing)],
            spacing: intakeGridSpacing
        ) {
            goleCard(height: cardHeight)
            intakeCard(.glass, height: cardHeight)
            intakeCard(.bottle, height: cardHeight)
            customIntakeCard(height: cardHeight)
        }
    }

    private func goleCard(height: CGFloat) -> some View {
        Button { logIntake(.custom(volumeML: 40), cardID: "gole") } label: {
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
                    icon: nil,
                    title: "Outro",
                    subtitle: "\(profile.customIntakeML) mL",
                    isHighlighted: highlightedCard == "custom",
                    height: height
                )
            }
            .buttonStyle(.plain)
            
            Button {
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
    
    private var isPresentingDeleteConfirm: Binding<Bool> {
        Binding(get: { pendingDeleteLog != nil }, set: { if !$0 { pendingDeleteLog = nil } })
    }
    
    private func intakeIcon(for preset: Constants.IntakePreset) -> IntakeCardIcon? {
        switch preset {
        case .glass: return .symbol("mug.fill", mirrored: true)
        case .bottle: return .bottle
        case .gole: return .symbol("drop.fill")
        case .custom: return nil
        }
    }
    
    private func loadWeather() async {
        weather = await WeatherContextService.shared.currentContext()
        isLoadingWeather = false
    }
    
    private func logIntake(_ preset: Constants.IntakePreset, cardID: String) {
        guard !isLogging else { return }
        isLogging = true
        playWaterSound()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) { highlightedCard = cardID }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeInOut(duration: 0.2)) { highlightedCard = nil }
        }
        Task {
            await NotificationScheduler.shared.recordManualIntake(preset: preset, userID: profile.userID, context: modelContext)
            isLogging = false
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
    
    private func deleteLog(_ log: IntakeLog) {
        Task { await NotificationScheduler.shared.deleteIntake(log, context: modelContext) }
    }
    
    private func saveCustomAmount(_ newValue: Int) {
        profile.customIntakeML = newValue
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
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

    /// Tinta do texto sobre o cartão liso (fora do ícone).
    private var titleInk: Color {
        isHighlighted ? .white : (colorScheme == .dark ? .primary : Color.appMutedInk)
    }

    private var subtitleInk: Color {
        isHighlighted ? .white : Color.appMutedInk
    }

    private var backgroundIconColor: Color {
        isHighlighted ? Color.white.opacity(0.28) : Color.appAccent
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
                    .fill(isHighlighted ? Color.appAccent : Color(UIColor.secondarySystemBackground))
                    .homeCardShadow()
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    /// `minHeight` (e não `height`): o cartão cresce com o Dynamic Type em vez de cortar o texto.
    private func textBlock(title titleColor: Color, subtitle subtitleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(AppFont.subheadline)
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: height)
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
        path.addQuadCurve(to: pt(0.81, 0.36), control: pt(0.81, 0.21))
        path.addLine(to: pt(0.81, 0.88))
        path.addQuadCurve(to: pt(0.71, 0.98), control: pt(0.81, 0.98))
        path.addLine(to: pt(0.29, 0.98))
        path.addQuadCurve(to: pt(0.19, 0.88), control: pt(0.19, 0.98))
        path.addLine(to: pt(0.19, 0.36))
        path.addQuadCurve(to: pt(0.40, 0.19), control: pt(0.19, 0.21))
        path.closeSubpath()

        return path
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
