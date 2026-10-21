import SwiftData
import SwiftUI


struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    // Estreitados por predicado (ver o comentário equivalente em HomeView): esta tela
    // só lê o consumo de hoje (`todayProgress`) e o ajuste gravado para hoje.
    @Query private var allLogs: [IntakeLog]
    @Query private var allDailyGoals: [DailyGoal]
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var isEditing = false
    @State private var isEditingGoal = false
    @State private var showGoalExplainer = false
    @State private var showReminders = false
    @State private var showLiveActivities = false
    @State private var showSiriTutorial = false
    @State private var showHealthConnect = false
    @State private var showMyData = false

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

    private var calculatedGoalML: Int {
        UserProfile.suggestedGoalML(gender: Genero(stored: profile.genero)?.gender, idade: profile.idade, pesoKg: profile.pesoKg, alturaCm: profile.alturaCm)
    }

    private var isManualGoal: Bool {
        profile.metaDiariaML != calculatedGoalML
    }

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

    /// Today's adjustment, from the live fetch if one happened this screen visit,
    /// otherwise from the locked row recorded earlier today.
    private var todaysAdjustmentML: Int {
        tempContext?.adjustmentML ?? DailyGoalResolver.recordedAdjustmentML(in: dailyGoals, on: .now) ?? 0
    }
    #if DEBUG
    @State private var debugNotificationStatus: String?
    @State private var debugCopyStatus: String?
    #endif

    private var todayProgress: Double {
        guard profile.metaDiariaML > 0 else { return 0 }
        let userLogs = allLogs.filter { $0.userID == profile.userID }
        let total = HydrationMath.totalML(userLogs, on: .now)
        return min(1, Double(total) / Double(profile.metaDiariaML))
    }

    private var sexoDisplay: String {
        Genero(stored: profile.genero)?.label ?? "Não informado"
    }

    private var alturaFormatted: String {
        let metros = profile.alturaCm / 100
        let formatted = String(format: "%.2f", metros)
        return formatted.replacingOccurrences(of: ".", with: ",") + " m"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                goalCard
                remindersCard
                liveActivitiesRow
                siriRow
                healthRow
                myDataRow
                #if DEBUG
                debugNotificationRow
                debugRandomCopyRow
                debugWeatherCard
                #endif
                personalDataSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .disableScrollBounce()
        }
        .appScreenBackground()
        .task {
            guard tempContext == nil else { return }
            #if !DEBUG
            // In release, once today's adjustment is locked, `todaysAdjustmentML`
            // already covers it — skip the redundant WeatherKit round trip. The
            // DEBUG weather card below wants a live read every visit, lock or not.
            guard !isTodaysAdjustmentLocked else { return }
            #endif
            tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ProfileFormView(
                    title: "Editar perfil",
                    confirmLabel: "Salvar",
                    initialValues: .from(profile),
                    showsCustomIntakeField: false,
                    showsCancelButton: true,
                    onSave: save
                )
            }
            .trackSheetLifecycle(.editPersonalData, screen: .profile, userID: profile.userID)
        }
        .sheet(isPresented: $showGoalExplainer) {
            GoalExplainerView(goalML: profile.metaDiariaML, adjustmentML: todaysAdjustmentML, isManual: isManualGoal)
                .trackSheetLifecycle(.goalExplainer, screen: .profile, userID: profile.userID)
        }
        .sheet(isPresented: $isEditingGoal) {
            EditGoalView(initialValueML: profile.metaDiariaML, onSave: saveGoal)
                .trackSheetLifecycle(.editGoal, screen: .profile, userID: profile.userID)
        }
        .sheet(isPresented: $showHealthConnect) {
            HealthConnectView(profile: profile)
        }
    }

    // MARK: - Goal Card

    // O cartão da meta é o único lugar da tela que carrega o gradiente — mesma
    // forma arredondada dos outros cartões da página (sem onda: isso é pro banner
    // de borda a borda das sheets, aqui o cartão é "flutuante" e fica estranho com
    // uma borda reta virando onda). O gradiente é o PRÓPRIO fundo do cartão, não um
    // painel separado atrás com altura chutada — então sempre acompanha o tamanho
    // real do cartão (Dynamic Type incluso) e nunca corta errado.
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sua meta diária é")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(profile.metaDiariaML)")
                            .font(AppFont.metric)
                            .foregroundStyle(.white)
                        Text("mL")
                            .font(AppFont.title3)
                            .foregroundStyle(.white.opacity(0.85))
                        if todaysAdjustmentML > 0 {
                            Text("+ \(todaysAdjustmentML) mL")
                                .font(AppFont.footnoteStrong)
                                .foregroundStyle(Color.appGoldHighlight)
                        }
                    }
                }

                Spacer()

                if let mascot = AppTheme.mascotImageName(for: todayProgress) {
                    Image(mascot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptic.tap.play()
                    showGoalExplainer = true
                } label: {
                    Text("Entender minha meta")
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(Color.appAccentTextOnWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background {
                            // Efeito por DENTRO do botão, não em volta: um brilho
                            // diagonal confinado à própria forma — nada de
                            // sombra/halo vazando pra fora.
                            ZStack {
                                Color.white
                                LinearGradient(
                                    colors: [.white, Color.appAccent.opacity(0.16), .white],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                RadialGradient(
                                    colors: [.white.opacity(0.7), .white.opacity(0)],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 150
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Haptic.tap.play()
                    isEditingGoal = true
                } label: {
                    Text("Editar")
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.waterHeader)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Reminders Card

    private var remindersCard: some View {
        Button {
            Haptic.primary.play()
            showReminders = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurar lembretes")
                        .font(AppFont.headline)

                    Text("O monstro te provoca quando\nvocê esquece de beber")
                        .font(AppFont.footnote)
                        .opacity(0.85)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.callout, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .buttonStyle(GradientProminentButtonStyle(cornerRadius: 20))
        .sheet(isPresented: $showReminders) {
            RemindersView()
                .trackSheetLifecycle(.reminders, screen: .profile, userID: profile.userID)
        }
    }

    // MARK: - Live Activities Row

    private var liveActivitiesRow: some View {
        Button {
            Haptic.tap.play()
            showLiveActivities = true
        } label: {
            HStack {
                Text("Como usar o botão de ação")
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appChevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLiveActivities) {
            ActionButtonTutorialView()
                .trackSheetLifecycle(.actionButtonTutorial, screen: .profile, userID: profile.userID)
        }
    }

    // MARK: - Siri Row

    private var siriRow: some View {
        Button {
            Haptic.tap.play()
            showSiriTutorial = true
        } label: {
            HStack {
                Text("Como usar a Siri")
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appChevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSiriTutorial) {
            SiriTutorialView()
                .trackSheetLifecycle(.siriTutorial, screen: .profile, userID: profile.userID)
        }
    }

    // MARK: - Health Row

    private var healthRow: some View {
        Button {
            Haptic.tap.play()
            InteractionTracker.log("health_connect_row_tap", screen: .profile, userID: profile.userID, context: modelContext)
            showHealthConnect = true
        } label: {
            HStack {
                Text("Conectar ao Saúde")
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appChevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meus dados

    /// Ver, exportar e apagar o que foi coletado — o que o `ConsentView` promete.
    private var myDataRow: some View {
        Button {
            Haptic.tap.play()
            InteractionTracker.log("my_data_row_tap", screen: .profile, userID: profile.userID, context: modelContext)
            showMyData = true
        } label: {
            HStack {
                Text("Meus dados")
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appChevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMyData) {
            MyDataView(profile: profile)
                .trackSheetLifecycle(.myData, screen: .profile, userID: profile.userID)
        }
    }

    // MARK: - Debug Row

    #if DEBUG
    private var debugNotificationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task {
                    debugNotificationStatus = "Enviando…"
                    _ = await NotificationScheduler.shared.requestAuthorization()
                    if let expected = await NotificationScheduler.shared.sendDebugNotification() {
                        debugNotificationStatus = "Chega em 5s (minimize o app pra ver na tela de bloqueio). Esperado: \(expected)"
                    } else {
                        debugNotificationStatus = "Sem perfil para gerar a notificação."
                    }
                }
            } label: {
                HStack {
                    Label("Debug: testar notificação do mascote", systemImage: "ladybug")
                        .font(AppFont.calloutStrong)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            }
            .buttonStyle(.plain)

            if let debugNotificationStatus {
                Text(debugNotificationStatus)
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    /// Sorteia uma frase de qualquer variante e a manda em 5 s, como o botão de cima faz com o mascote.
    private var debugRandomCopyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptic.tap.play()
                Task {
                    debugCopyStatus = "Enviando…"
                    _ = await NotificationScheduler.shared.requestAuthorization()
                    if let sent = await NotificationScheduler.shared.sendRandomDebugCopy() {
                        debugCopyStatus = "Chega em 5s (minimize o app pra ver na tela de bloqueio). \(sent.variant.rawValue): \(sent.copy.title)"
                    } else {
                        debugCopyStatus = "Sem perfil para gerar a notificação."
                    }
                }
            } label: {
                HStack {
                    Label("Debug: testar frase aleatória da notificação", systemImage: "text.bubble")
                        .font(AppFont.calloutStrong)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
            }
            .buttonStyle(.plain)

            if let debugCopyStatus {
                Text(debugCopyStatus)
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var debugWeatherCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Debug: ajuste climático", systemImage: "cloud.sun")
                    .font(AppFont.subheadlineStrong)
                    .foregroundStyle(Color.appSecondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 18)

            if let ctx = tempContext {
                Group {
                    debugRow(label: "Temp. máxima real",     value: String(format: "%.1f °C", ctx.todayMaxC))
                    debugRow(label: "Umidade média",         value: String(format: "%.0f %%", ctx.humidityPct))
                    debugRow(label: "Heat Index (sensação)", value: String(format: "%.1f °C", ctx.apparentMaxC))
                    debugRow(label: "Baseline",              value: String(format: "%.0f °C", ctx.baselineC))
                    debugRow(label: "Excesso sobre baseline",value: String(format: "%.1f °C", max(0, ctx.apparentMaxC - ctx.baselineC)))
                    debugRow(label: "Ajuste total",          value: "+ \(ctx.adjustmentML) mL", highlight: ctx.adjustmentML > 0)
                }
            } else {
                Text("Carregando dados do clima…")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .padding(.bottom, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
    }

    private func debugRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(AppFont.footnote)
                .foregroundStyle(Color.appSecondary)
            Spacer()
            Text(value)
                .font(AppFont.footnoteStrong)
                .foregroundStyle(highlight ? Color.appWarning : Color.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
    #endif

    // MARK: - Personal Data Section

    private var personalDataSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DADOS PESSOAIS")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.appAccentText)
                    .tracking(1)

                Spacer()

                Button {
                    Haptic.tap.play()
                    isEditing = true
                } label: {
                    Text("Editar")
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                dataRow(label: "Idade", value: "\(profile.idade) anos", isLast: false)
                dataRow(label: "Sexo", value: sexoDisplay, isLast: false)
                dataRow(label: "Peso", value: "\(Int(profile.pesoKg)) kg", isLast: false)
                dataRow(label: "Altura", value: alturaFormatted, isLast: true)
            }
            .panelBackground(cornerRadius: 18)
        }
    }

    private func dataRow(label: String, value: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(AppFont.callout)
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .font(AppFont.calloutStrong)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !isLast {
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(
                        Color.appDivider,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
                }
                .frame(height: 1)
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Save

    private func save(_ values: ProfileFormValues) {
        Haptic.success.play()
        profile.idade = values.idade
        profile.genero = values.genero?.rawValue
        profile.generoAutoDeclarado = nil
        profile.pesoKg = values.pesoKg
        profile.alturaCm = values.alturaCm
        // Mantido em dia: o pipeline usa este campo para converter os timestamps em
        // hora local (ml/python/dataset.py::to_local), e ele só era gravado no
        // onboarding — um fuso velho desloca a hora de todo o histórico de quem muda
        // de região.
        profile.fusoHorario = TimeZone.current.identifier
        if values.resetGoalToCalculated || values.storedGoalML == nil {
            profile.metaDiariaML = UserProfile.suggestedGoalML(gender: values.genero?.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm)
        }
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        modelContext.saveLogging("dados pessoais")
        recordTodayGoal()
        isEditing = false
        InteractionTracker.log("edit_personal_data_save", screen: .profile, userID: profile.userID, context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }

    private func saveGoal(_ newValue: Int) {
        Haptic.success.play()
        profile.metaDiariaML = newValue
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        modelContext.saveLogging("meta editada")
        recordTodayGoal()
        InteractionTracker.log("edit_goal_save", screen: .profile, userID: profile.userID, metadata: ["newGoalML": "\(newValue)"], context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }

    /// A goal change only applies from today on: today's `DailyGoal` row takes the new
    /// base, earlier rows keep the goal those days actually had.
    private func recordTodayGoal() {
        DailyGoal.recordToday(userID: profile.userID, baseGoalML: profile.metaDiariaML, adjustmentML: tempContext?.adjustmentML, context: modelContext)
    }
}

// MARK: - Goal Explainer Sheet

private struct GoalExplainerView: View {
    let goalML: Int
    let adjustmentML: Int
    let isManual: Bool

    var body: some View {
        TankSheet {
            VStack(spacing: 20) {
                CurrentMascotTankHeader(
                    title: "Sua meta diária",
                    subtitle: isManual ? "Definida por você manualmente." : "Calculada com base no seu perfil."
                )

                VStack(spacing: 16) {
                    goalStat

                    Text(
                        isManual
                            ? "Esta meta foi definida por você manualmente. Se editar seus dados pessoais (peso, altura, idade ou sexo), ela será recalculada automaticamente."
                            : "A quantidade ideal de água depende do seu peso, altura, idade, gênero e temperatura no dia. Você pode ajustar seus dados no perfil para recalcular a meta."
                    )
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
    }

    private var goalStat: some View {
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(goalML) mL")
                    .font(AppFont.metric)
                    .foregroundStyle(.primary)
                if adjustmentML > 0 {
                    Text("+ \(adjustmentML) mL")
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(Color.appWarning)
                }
            }
            if adjustmentML > 0 {
                Text("+ \(adjustmentML) mL por conta do clima hoje")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.appWarning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .panelBackground()
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 24, genero: "feminino", pesoKg: 62, alturaCm: 168, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2500)
    return ProfileView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
