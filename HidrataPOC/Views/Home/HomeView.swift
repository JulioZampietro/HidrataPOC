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
    @State private var weather: WeatherContext?
    @State private var isLoadingWeather = true
    @State private var tempContext: TemperatureAdjustmentContext?
    /// Minijogo da meta batida: o aquário (`WaterHeaderView`) desenha, aqui ficam os botões.
    @Environment(MiniGameController.self) private var miniGames
    @State private var pressedJets = [Bool](repeating: false, count: RingGameSide.allCases.count)
    @State private var pressedJumpSides = [Bool](repeating: false, count: JumpGameSide.allCases.count)
    @State private var pressedAimSides = [Bool](repeating: false, count: BubbleGameSide.allCases.count)
    @State private var isFirePressed = false
    @AppStorage(MiniGame.jumpBestStorageKey) private var jumpBestScore = 0
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
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: miniGames.showsGameControls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
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
            guard tempContext == nil, !isTodaysAdjustmentLocked else { return }
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
            Button("Cancelar", role: .cancel) { Haptic.dismiss.play() }
        } message: { log in
            Text("\(log.tipoEntrada.capitalized) · \(log.volumeML) mL será removido do seu histórico e da base de dados.")
        }
        .sheet(isPresented: $isEditingCustomAmount) {
            CustomIntakeEditorView(initialValueML: profile.customIntakeML, onSave: saveCustomAmount)
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
                userID: profile.userID,
                calendar: .current
            )
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
    /// do jogo (uma linha de três) no mesmo lugar (`matchedGeometryEffect`). A seta pra trás no cabeçalho do
    /// aquário volta aos cartões (tocar no aquário traz o jogo de volta).
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
            case .bubbles:
                aimButton(.left).matchedGeometryEffect(id: "gole", in: controlsNamespace)
                fireButton.matchedGeometryEffect(id: "bottle", in: controlsNamespace)
                aimButton(.right).matchedGeometryEffect(id: "glass", in: controlsNamespace)
            default:
                jumpButton(.left).matchedGeometryEffect(id: "gole", in: controlsNamespace)
                JumpGameRecordCard(best: jumpBestScore, height: cardHeight)
                    .matchedGeometryEffect(id: "bottle", in: controlsNamespace)
                jumpButton(.right).matchedGeometryEffect(id: "glass", in: controlsNamespace)
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

    private func jumpButton(_ side: JumpGameSide) -> some View {
        GameHoldButton(
            symbol: side == .left ? "arrow.left.circle.fill" : "arrow.right.circle.fill",
            accessibilityLabel: side == .left ? "Pular pra esquerda" : "Pular pra direita",
            accessibilityHint: "Leva a gota pro lado enquanto estiver apertado",
            isPressed: pressedJumpSides[side.rawValue],
            onPressChange: { isPressed in
                guard pressedJumpSides[side.rawValue] != isPressed else { return }
                pressedJumpSides[side.rawValue] = isPressed
                miniGames.jumpGame.setDirection(side, held: isPressed)
                if isPressed { Haptic.tap.play() }
            },
            onAccessibilityPulse: { miniGames.jumpGame.pulseDirection(side) }
        )
    }

    private func aimButton(_ side: BubbleGameSide) -> some View {
        GameHoldButton(
            symbol: side == .left ? "arrow.counterclockwise.circle.fill" : "arrow.clockwise.circle.fill",
            accessibilityLabel: side == .left ? "Mirar pra esquerda" : "Mirar pra direita",
            accessibilityHint: "Gira o canhão de bolhas enquanto estiver apertado",
            isPressed: pressedAimSides[side.rawValue],
            onPressChange: { isPressed in
                guard pressedAimSides[side.rawValue] != isPressed else { return }
                pressedAimSides[side.rawValue] = isPressed
                miniGames.bubbleGame.setAim(side, held: isPressed)
                if isPressed { Haptic.selection.play() }
            },
            onAccessibilityPulse: { miniGames.bubbleGame.pulseAim(side) }
        )
    }

    /// Atira ao apertar; o pulso do toque completo (ver `GameHoldButton`) só cobre o caso em
    /// que o `pressing` não chegou — a simulação ignora o segundo tiro enquanto o primeiro voa.
    private var fireButton: some View {
        GameHoldButton(
            symbol: "arrow.up.circle.fill",
            accessibilityLabel: "Atirar bolha",
            accessibilityHint: "Atira a bolha do canhão na direção da mira",
            isPressed: isFirePressed,
            onPressChange: { isPressed in
                guard isFirePressed != isPressed else { return }
                isFirePressed = isPressed
                if isPressed { miniGames.bubbleGame.fire() }
            },
            onAccessibilityPulse: { miniGames.bubbleGame.fire() }
        )
    }

    /// Solta qualquer botão de jogo que estivesse apertado (os botões sumiram ou o jogo trocou).
    private func releaseGameButtons() {
        pressedJets = [Bool](repeating: false, count: RingGameSide.allCases.count)
        for side in RingGameSide.allCases { miniGames.ringGame.setJet(side, open: false) }
        pressedJumpSides = [Bool](repeating: false, count: JumpGameSide.allCases.count)
        for side in JumpGameSide.allCases { miniGames.jumpGame.setDirection(side, held: false) }
        pressedAimSides = [Bool](repeating: false, count: BubbleGameSide.allCases.count)
        isFirePressed = false
        for side in BubbleGameSide.allCases { miniGames.bubbleGame.setAim(side, held: false) }
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
        Haptic.drink.play()
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
        Haptic.destructive.play()
        Task { await NotificationScheduler.shared.deleteIntake(log, context: modelContext) }
    }
    
    private func saveCustomAmount(_ newValue: Int) {
        Haptic.success.play()
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
            Spacer(minLength: 0)

            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(AppFont.subheadline)
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
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
