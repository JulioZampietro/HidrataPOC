import SwiftData
import SwiftUI


struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [IntakeLog]
    @State private var tempContext: TemperatureAdjustmentContext?
    @State private var isEditing = false
    @State private var isEditingGoal = false
    @State private var showGoalExplainer = false
    @State private var showReminders = false
    @State private var showLiveActivities = false
    @State private var showSiriTutorial = false
    @State private var showHealthConnect = false

    private var calculatedGoalML: Int {
        UserProfile.suggestedGoalML(gender: Genero(stored: profile.genero)?.gender, idade: profile.idade, pesoKg: profile.pesoKg, alturaCm: profile.alturaCm)
    }

    private var isManualGoal: Bool {
        profile.metaDiariaML != calculatedGoalML
    }
    #if DEBUG
    @State private var debugNotificationStatus: String?
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
                #if DEBUG
                debugNotificationRow
                debugWeatherCard
                #endif
                personalDataSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .appScreenBackground()
        .task {
            guard tempContext == nil else { return }
            tempContext = await WeatherContextService.shared.temperatureAdjustmentContext()
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ProfileFormView(
                    title: "Editar perfil",
                    confirmLabel: "Salvar",
                    initialValues: .from(profile),
                    showsCustomIntakeField: false,
                    onSave: save
                )
            }
            .trackSheetLifecycle(.editPersonalData, screen: .profile, userID: profile.userID)
        }
        .sheet(isPresented: $showGoalExplainer) {
            GoalExplainerView(goalML: profile.metaDiariaML, adjustmentML: tempContext?.adjustmentML ?? 0, isManual: isManualGoal)
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

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sua meta diária é")
                        .font(.custom("Nunito", size: 14))
                        .foregroundStyle(Color.appSecondary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(profile.metaDiariaML)")
                            .font(.custom("Nunito", size: 40).weight(.heavy))
                            .foregroundStyle(.primary)
                        Text("mL")
                            .font(.custom("Nunito", size: 18).weight(.semibold))
                            .foregroundStyle(Color.appSecondary)
                        if let adjustment = tempContext?.adjustmentML, adjustment > 0 {
                            Text("+ \(adjustment) mL")
                                .font(.custom("Nunito", size: 13).weight(.semibold))
                                .foregroundStyle(Color.appWarning)
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
                    showGoalExplainer = true
                } label: {
                    Text("Entender minha meta")
                        .font(.custom("Nunito", size: 15).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)

                Button {
                    isEditingGoal = true
                } label: {
                    Text("Editar")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccentText)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
    }

    // MARK: - Reminders Card

    private var remindersCard: some View {
        Button {
            showReminders = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurar lembretes")
                        .font(.custom("Nunito", size: 17).weight(.heavy))

                    Text("O monstro te provoca quando\nvocê esquece de beber")
                        .font(.custom("Nunito", size: 13))
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
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .tint(Color.appAccent)
    }

    // MARK: - Live Activities Row

    private var liveActivitiesRow: some View {
        Button {
            showLiveActivities = true
        } label: {
            HStack {
                Text("Como usar o botão de ação")
                    .font(.custom("Nunito", size: 16).weight(.semibold))
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
            showSiriTutorial = true
        } label: {
            HStack {
                Text("Como usar a Siri")
                    .font(.custom("Nunito", size: 16).weight(.semibold))
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
            InteractionTracker.log("health_connect_row_tap", screen: .profile, userID: profile.userID, context: modelContext)
            showHealthConnect = true
        } label: {
            HStack {
                Text("Conectar ao Saúde")
                    .font(.custom("Nunito", size: 16).weight(.semibold))
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
                        .font(.custom("Nunito", size: 16).weight(.semibold))
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
                    .font(.custom("Nunito", size: 13))
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var debugWeatherCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Debug: ajuste climático", systemImage: "cloud.sun")
                    .font(.custom("Nunito", size: 14).weight(.bold))
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
                    .font(.custom("Nunito", size: 13))
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
                .font(.custom("Nunito", size: 13))
                .foregroundStyle(Color.appSecondary)
            Spacer()
            Text(value)
                .font(.custom("Nunito", size: 13).weight(.bold))
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
                    .font(.custom("Nunito", size: 12).weight(.bold))
                    .foregroundStyle(Color.appAccentText)
                    .tracking(1)

                Spacer()

                Button {
                    isEditing = true
                } label: {
                    Text("Editar")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
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
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4))
        }
    }

    private func dataRow(label: String, value: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.custom("Nunito", size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .font(.custom("Nunito", size: 16).weight(.bold))
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
        profile.idade = values.idade
        profile.genero = values.genero?.rawValue
        profile.generoAutoDeclarado = nil
        profile.pesoKg = values.pesoKg
        profile.alturaCm = values.alturaCm
        if values.resetGoalToCalculated || values.storedGoalML == nil {
            profile.metaDiariaML = UserProfile.suggestedGoalML(gender: values.genero?.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm)
        }
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
        recordTodayGoal()
        isEditing = false
        InteractionTracker.log("edit_personal_data_save", screen: .profile, userID: profile.userID, context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }

    private func saveGoal(_ newValue: Int) {
        profile.metaDiariaML = newValue
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.appAccentText)
                    .padding(.top, 32)

                Text("Sua meta diária")
                    .font(.custom("Nunito", size: 22).weight(.heavy))

                VStack(spacing: 6) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(goalML) mL")
                            .font(.custom("Nunito", size: 40).weight(.heavy))
                            .foregroundStyle(Color.appAccentText)
                        if adjustmentML > 0 {
                            Text("+ \(adjustmentML) mL")
                                .font(.custom("Nunito", size: 15).weight(.semibold))
                                .foregroundStyle(Color.appWarning)
                        }
                    }

                    Text(isManual ? "definida por você manualmente" : "calculada com base no seu perfil")
                        .font(.custom("Nunito", size: 14))
                        .foregroundStyle(Color.appSecondary)

                    if adjustmentML > 0 {
                        Text("+ \(adjustmentML) mL por conta do clima hoje")
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(Color.appWarning)
                    }
                }

                Text(
                    isManual
                        ? "Esta meta foi definida por você manualmente. Se editar seus dados pessoais (peso, altura, idade ou sexo), ela será recalculada automaticamente."
                        : "A quantidade ideal de água depende do seu peso, altura, idade, gênero e temperatura no dia. Você pode ajustar seus dados no perfil para recalcular a meta."
                )
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                }
            }
        }
    }
}

#Preview {
    let profile = UserProfile(userID: "preview", idade: 24, genero: "feminino", pesoKg: 62, alturaCm: 168, fusoHorario: "America/Sao_Paulo", metaDiariaML: 2500)
    return ProfileView(profile: profile)
        .modelContainer(for: IntakeLog.self, inMemory: true)
}
