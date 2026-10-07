import AVFoundation
import SwiftData
import SwiftUI

//private let accentBlue = Color(red: 0.1098, green: 0.4627, blue: 0.9922)
private let accentBlue = Color(red: 0.1098, green: 0.4627, blue: 0.9922)

struct HomeView: View {
    let profile: UserProfile
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
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

    private static let mascotPhrases: [String] = [
        "Não bebe água não",
        "Você nem sente sede né?",
        "Amo a sensação de boca seca!"
        
    ]

    private var todayLogs: [IntakeLog] {
        allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
    }
    
    private var consumedToday: Int { HydrationMath.totalML(todayLogs, on: .now) }
    
    private var effectiveGoalML: Int {
        HydrationMath.effectiveGoalML(baseGoalML: profile.metaDiariaML, tempContext: tempContext)
    }
    
    private var progress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(effectiveGoalML))
    }
    
    private var streak: Int {
        HydrationMath.currentStreak(allLogs.filter { $0.userID == profile.userID }, metaDiariaML: profile.metaDiariaML)
    }
    
    var body: some View {
        ZStack {
            AppTheme.screenBackground(for: colorScheme)
                .ignoresSafeArea()
            
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: TabScreenLayout.spacing) {
                        topSection(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height))
                            .padding(.horizontal, 10)

                        progressBarButton
                            .padding(.horizontal, 20)

                        intakeGrid(cardHeight: intakeCardHeight(forVisibleHeight: geo.size.height))
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, TabScreenLayout.spacing)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task { await loadWeather() }
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
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(accentBlue)
                Text("\(streak)")
                    .font(.custom("Nunito", size: 15).bold())
                Text("dias")
                    .font(.custom("Nunito", size: 15))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Compartilhar")
        }
    }
    
    private let progressBarHeight: CGFloat = 52
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

    private func topSection(height: CGFloat) -> some View {
        // Recipiente: vai do topo da tela até logo acima da barra de progresso e
        // enche de água conforme o progresso do dia.
        // O cabeçalho fica fora do conteúdo da água: a refração achata o conteúdo
        // numa imagem e o vidro dos botões deixa de enxergar o fundo (fica escuro).
        mascotPlaceholder(height: TabScreenLayout.mascotHeight(forWaterHeight: height))
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

    private func mascotPlaceholder(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let mascot = AppTheme.mascotImageName(for: progress) {
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
                // Meta batida: o mascote some, mas o espaço fica para o layout não pular.
                Color.clear.frame(height: height)
            }

            // Transição de bolhas ao trocar de estágio (mascote5→mascote4 etc.),
            // estilo Bob Esponja: o mascote novo já está sendo exibido normalmente
            // no ramo acima; isso sobrepõe o mascote ANTIGO, que a própria view
            // esconde no auge da cobertura das bolhas, revelando o novo por baixo.
            // Independe do nível de água real, então funciona igual com o
            // recipiente cheio ou quase vazio.
            if let bubbling = bubbleMascot {
                let correction = AppTheme.mascotSizeCorrection(for: bubbling)
                MascotBubbleTransitionView(imageName: bubbling, width: height * 1.55 * correction, height: height * correction)
                    .frame(width: height * 1.55, height: height, alignment: .center)
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
        } else if let old = oldMascot, let new = newMascot, old != new {
            bubbleMascot = old
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                try? await Task.sleep(for: .milliseconds(1900))
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
                    .frame(height: 52)
                    .homeCardShadow()
                
                // preenchimento azul
                Capsule()
                    .fill(accentBlue)
                    .frame(width: barWidth, height: 52)
                    .animation(.easeOut(duration: 0.4), value: progress)
                
                Text("\(consumedToday) mL / \(effectiveGoalML) mL")
                    .font(.custom("Nunito", size: 15).weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.leading, 18)

                // Indica que a barra é tocável (abre os registros de hoje). Fica branco
                // quando o preenchimento azul já chegou embaixo dele.
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(barWidth >= geo.size.width - 36 ? .white : accentBlue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: progressBarHeight)
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
                icon: "drop.fill",
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
                icon: iconName(for: preset),
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
                    icon: "plus",
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
                    .foregroundStyle(accentBlue)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Editar volume do botão personalizado")
        }
    }
    
    // MARK: - Helpers
    
    private var isPresentingDeleteConfirm: Binding<Bool> {
        Binding(get: { pendingDeleteLog != nil }, set: { if !$0 { pendingDeleteLog = nil } })
    }
    
    private func iconName(for preset: Constants.IntakePreset) -> String {
        switch preset {
        case .glass: return "mug.fill"
        case .bottle: return "waterbottle.fill"
        case .gole: return "drop.fill"
        case .custom: return "plus"
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

struct IntakeCardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String
    var isHighlighted: Bool = false
    var height: CGFloat? = nil

    private var titleColor: Color {
        isHighlighted ? .white : (colorScheme == .dark ? .primary : Color(red: 0.3686, green: 0.4667, blue: 0.6078))
    }

    private var subtitleColor: Color {
        isHighlighted ? Color.white.opacity(0.8) : (colorScheme == .dark ? .secondary : Color(red: 0.3686, green: 0.4667, blue: 0.6078).opacity(0.75))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(icon == "plus" ? .system(size: 30) : .title2)
                .foregroundStyle(isHighlighted ? .white : accentBlue)

            Spacer(minLength: 12)

            Text(title)
                .font(.custom("Nunito", size: 17).weight(.heavy))
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHighlighted ? accentBlue : Color(UIColor.secondarySystemBackground))
                .homeCardShadow()
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
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
