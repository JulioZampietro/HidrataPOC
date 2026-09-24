import SwiftData
import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

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
    #if DEBUG
    @State private var debugNotificationStatus: String?
    #endif

    private var todayProgress: Double {
        guard profile.metaDiariaML > 0 else { return 0 }
        let userLogs = allLogs.filter { $0.userID == profile.userID }
        let total = HydrationMath.totalML(userLogs, on: .now)
        return min(1, Double(total) / Double(profile.metaDiariaML))
    }

    private var generoDisplay: String {
        let genero = Genero(rawValue: profile.genero ?? Genero.naoInformar.rawValue) ?? .naoInformar
        if genero == .autoDeclarado, let texto = profile.generoAutoDeclarado, !texto.isEmpty {
            return texto
        }
        return genero.label
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
            GoalExplainerView(goalML: profile.metaDiariaML, adjustmentML: tempContext?.adjustmentML ?? 0)
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
                        .foregroundStyle(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(profile.metaDiariaML)")
                            .font(.custom("Nunito", size: 40).weight(.heavy))
                            .foregroundStyle(.primary)
                        Text("mL")
                            .font(.custom("Nunito", size: 18).weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let adjustment = tempContext?.adjustmentML, adjustment > 0 {
                            Text("+ \(adjustment) mL")
                                .font(.custom("Nunito", size: 13).weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                Image(AppTheme.mascotImageName(for: todayProgress))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
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
                .buttonStyle(.glassProminent)
                .tint(accentBlue)

                Button {
                    isEditingGoal = true
                } label: {
                    Text("Editar")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glass)
                .tint(accentBlue)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
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
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .tint(accentBlue)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.63))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.63))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.63))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
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
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if let debugNotificationStatus {
                Text(debugNotificationStatus)
                    .font(.custom("Nunito", size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
    #endif

    // MARK: - Personal Data Section

    private var personalDataSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DADOS PESSOAIS")
                    .font(.custom("Nunito", size: 12).weight(.bold))
                    .foregroundStyle(accentBlue)
                    .tracking(1)

                Spacer()

                Button {
                    isEditing = true
                } label: {
                    Text("Editar")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
                        .foregroundStyle(accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                dataRow(label: "Idade", value: "\(profile.idade) anos", isLast: false)
                dataRow(label: "Gênero", value: generoDisplay, isLast: false)
                dataRow(label: "Peso", value: "\(Int(profile.pesoKg)) kg", isLast: false)
                dataRow(label: "Altura", value: alturaFormatted, isLast: true)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
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
                        Color(red: 0.75, green: 0.78, blue: 0.82).opacity(0.6),
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
        profile.genero = values.genero == .naoInformar ? nil : values.genero.rawValue
        profile.generoAutoDeclarado = values.normalizedGeneroAutoDeclarado
        profile.pesoKg = values.pesoKg
        profile.alturaCm = values.alturaCm
        profile.metaDiariaML = UserProfile.suggestedGoalML(gender: values.genero.gender, idade: values.idade, pesoKg: values.pesoKg, alturaCm: values.alturaCm)
        profile.atualizadoEm = .now
        profile.syncStatus = .pending
        try? modelContext.save()
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
        InteractionTracker.log("edit_goal_save", screen: .profile, userID: profile.userID, metadata: ["newGoalML": "\(newValue)"], context: modelContext)
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }
}

// MARK: - Goal Explainer Sheet

private struct GoalExplainerView: View {
    let goalML: Int
    let adjustmentML: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(accentBlue)
                    .padding(.top, 32)

                Text("Sua meta diária")
                    .font(.custom("Nunito", size: 22).weight(.heavy))

                VStack(spacing: 6) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(goalML) mL")
                            .font(.custom("Nunito", size: 40).weight(.heavy))
                            .foregroundStyle(accentBlue)
                        if adjustmentML > 0 {
                            Text("+ \(adjustmentML) mL")
                                .font(.custom("Nunito", size: 15).weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text("calculado com base no seu perfil")
                        .font(.custom("Nunito", size: 14))
                        .foregroundStyle(.secondary)

                    if adjustmentML > 0 {
                        Text("+ \(adjustmentML) mL por conta da temperatura hoje")
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                }

                Text("A quantidade ideal de água depende do seu peso, altura, idade, gênero e temperatura no dia. Você pode ajustar seus dados no perfil para recalcular a meta.")
                    .font(.custom("Nunito", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
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
