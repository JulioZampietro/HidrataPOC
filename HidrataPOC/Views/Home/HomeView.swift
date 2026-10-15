import AVFoundation
import SwiftData
import SwiftUI


struct HomeView: View {
    let profile: UserProfile
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    // Barra e cartões têm tamanho fixo (o do texto em 100%): só o texto dentro deles acompanha
    // o Dynamic Type, limitado a `controlTextSizeRange` para caber sem ser cortado.
    private let progressBarHeight: CGFloat = 52
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

    private var progress: Double {
        guard effectiveGoalML > 0 else { return 0 }
        return min(1, Double(consumedToday) / Double(effectiveGoalML))
    }
    
    var body: some View {
        ZStack {
            AppTheme.screenBackground(for: colorScheme)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: TabScreenLayout.spacing) {
                    // O recipiente de água (`WaterHeaderView`) é desenhado pelo
                    // `RootView`, fixo por cima das páginas; aqui fica só o espaço dele.
                    Color.clear
                        .frame(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height, safeAreaTop: geo.safeAreaInsets.top))

                    progressBarButton
                        .padding(.horizontal, 20)

                    intakeGrid(cardHeight: intakeCardHeight(forVisibleHeight: geo.size.height))
                        .padding(.horizontal, 20)
                }
                .padding(.top, TabScreenLayout.waterTop(safeAreaTop: geo.safeAreaInsets.top))
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
    
    private let intakeGridSpacing: CGFloat = 12
    private let controlTextSizeRange = ...DynamicTypeSize.xxxLarge

    /// The two rows of intake cards share what's left below the progress bar, so the
    /// grid ends `TabScreenLayout.spacing` above the bottom safe area.
    private func intakeCardHeight(forVisibleHeight height: CGFloat) -> CGFloat {
        let gridHeight = TabScreenLayout.contentHeight(forVisibleHeight: height) - progressBarHeight - TabScreenLayout.spacing
        return max((gridHeight - intakeGridSpacing) / 2, 116)
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
    
    private func progressLabel(color: Color) -> some View {
        Text("\(consumedToday) mL / \(effectiveGoalML) mL")
            .font(AppFont.subheadlineHeavy)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75) // 15 pt × 0.75 ≈ 11 pt: o menor texto do app (HIG)
            .padding(.leading, 18)
            .padding(.trailing, 52)
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
