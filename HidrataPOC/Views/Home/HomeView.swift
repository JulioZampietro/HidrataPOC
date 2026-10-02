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
    @State private var showHelp = false
    @State private var showSiriTutorial = false
    @State private var showActionButtonTutorial = false
    @State private var showTodayLogs = false
    @State private var weather: WeatherContext?
    @State private var isLoadingWeather = true
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var phraseIndex: Int = 0
    @State private var pokeCount: Int = 0
    @State private var isPoking: Bool = false
    @State private var overridePhrase: String? = nil

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
                        headerRow
                            .padding(.horizontal, 20)

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
        .sheet(isPresented: $showHelp) { HomeHelpView() }
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
    
    private var headerRow: some View {
        HStack {
            Button {
                InteractionTracker.log("home_help_tap", screen: .home, userID: profile.userID, context: modelContext)
                showHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            
            Spacer()
            
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
            .glassEffect(.regular, in: Capsule())
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            mascotPlaceholder(height: TabScreenLayout.mascotHeight(forWaterHeight: height))
        }
        .padding(.bottom, TabScreenLayout.mascotBottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            containerShape
                .fill(AppTheme.screenBackground(for: colorScheme))
        }
        .waterContainer(
            level: progress,
            in: containerShape,
            bleedsIntoTopSafeArea: true
        )
    }
    
    private func mascotPlaceholder(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let mascot = AppTheme.mascotImageName(for: progress) {
                Image(mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .scaleEffect(
                        x: isPoking ? 1.18 : 1.0,
                        y: isPoking ? 0.82 : 1.0,
                        anchor: .bottom
                    )
                    .onTapGesture { pokeMascot() }

                MascotSpeechBubble(text: overridePhrase ?? Self.mascotPhrases[phraseIndex])
                    .offset(x: 8, y: -8)
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            } else {
                // Meta batida: o mascote some, mas o espaço fica para o layout não pular.
                Color.clear.frame(height: height)
            }
        }
        .onAppear { phraseIndex = Int.random(in: 0..<Self.mascotPhrases.count) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard overridePhrase == nil else { continue }
                withAnimation(.easeInOut(duration: 0.35)) {
                    phraseIndex = (phraseIndex + 1) % Self.mascotPhrases.count
                }
            }
        }
    }

    private func pokeMascot() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.interpolatingSpring(stiffness: 500, damping: 8)) { isPoking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 14)) { isPoking = false }
        }

        pokeCount += 1

        if pokeCount >= 3 {
            pokeCount = 0
            withAnimation(.easeInOut(duration: 0.25)) {
                overridePhrase = "Para de me cutucar zé mané"
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeInOut(duration: 0.35)) { overridePhrase = nil }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                phraseIndex = (phraseIndex + 1) % Self.mascotPhrases.count
            }
        }
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
