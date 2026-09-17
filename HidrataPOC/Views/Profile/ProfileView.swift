import SwiftData
import SwiftUI

private let accentBlue = Color(red: 0.286, green: 0.498, blue: 0.714)

struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var showGoalExplainer = false
    @State private var showReminders = false
    @State private var showLiveActivities = false
    @State private var showSiriTutorial = false
    @State private var showHealthConnect = false

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
                personalDataSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .appScreenBackground()
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
        }
        .sheet(isPresented: $showGoalExplainer) {
            GoalExplainerView(goalML: profile.metaDiariaML)
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
                    }
                }

                Spacer()

                // Monster mascot placeholder
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Text("🪨")
                        .font(.system(size: 40))
                }
            }

            HStack(spacing: 10) {
                Button {
                    showGoalExplainer = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.18, green: 0.35, blue: 0.56))
                            .offset(y: 4)
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accentBlue)
                        Text("Entender minha meta")
                            .font(.custom("Nunito", size: 15).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 13)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)

                Button {
                    isEditing = true
                } label: {
                    Text("Editar")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
                        .foregroundStyle(accentBlue)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        .background(accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Reminders Card

    private var remindersCard: some View {
        Button {
            showReminders = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.18, green: 0.35, blue: 0.56))
                    .offset(y: 4)
                RoundedRectangle(cornerRadius: 20)
                    .fill(accentBlue)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configurar lembretes")
                            .font(.custom("Nunito", size: 17).weight(.heavy))
                            .foregroundStyle(.white)

                        Text("O monstro te provoca quando\nvocê esquece de beber")
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(18)
            }
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLiveActivities) {
            ActionButtonTutorialView()
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSiriTutorial) {
            SiriTutorialView()
        }
    }

    // MARK: - Health Row

    private var healthRow: some View {
        Button {
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
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
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 10000, y: 0))
                }
                .stroke(
                    Color(red: 0.75, green: 0.78, blue: 0.82).opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
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
        Task {
            await CloudKitSyncService.shared.push(profile)
            try? modelContext.save()
        }
    }
}

// MARK: - Goal Explainer Sheet

private struct GoalExplainerView: View {
    let goalML: Int
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
                    Text("\(goalML) mL")
                        .font(.custom("Nunito", size: 40).weight(.heavy))
                        .foregroundStyle(accentBlue)

                    Text("calculado com base no seu perfil")
                        .font(.custom("Nunito", size: 14))
                        .foregroundStyle(.secondary)
                }

                Text("A quantidade ideal de água depende do seu peso, altura, idade e gênero. Você pode ajustar seus dados no perfil para recalcular a meta.")
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
