import HydrationKit
import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("hasAcceptedConsent") private var hasAcceptedConsent = false
    @AppStorage("hasSeenFeatureOnboarding") private var hasSeenFeatureOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var selectedPage: MainPage? = .home
    @State private var showProfile = false

    /// Fresh install (or a new device): before showing onboarding, look for a backup
    /// in iCloud (CloudKit) and restore it.
    @State private var hasCheckedICloud = false

    /// The widget can't read the real system appearance itself (see `LockScreenAppearance`).
    private func recordSystemAppearance() {
        LockScreenAppearance.isDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
    }

    private var profile: UserProfile? { profiles.first }

    private var currentScreen: AppScreen {
        selectedPage == .historico ? .historico : .home
    }

    var body: some View {
        Group {
            if !hasAcceptedConsent {
                ConsentView(onAccept: { hasAcceptedConsent = true })
            } else if let profile {
                mainContent(profile: profile)
                    .onAppear { startLiveActivityIfNeeded(for: profile) }
                    .onChange(of: profile.userID) { startLiveActivityIfNeeded(for: profile) }
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasSeenFeatureOnboarding },
                        set: { _ in }
                    )) {
                        FeatureOnboardingView {
                            hasSeenFeatureOnboarding = true
                            requestPermissionsAfterOnboarding(for: profile)
                        }
                    }
            } else if !hasCheckedICloud {
                ICloudRestoreView(onSkip: { hasCheckedICloud = true })
                    .task { await restoreFromICloud() }
            } else {
                OnboardingView()
            }
        }
        .onAppear(perform: recordSystemAppearance)
        .onChange(of: scenePhase) { if scenePhase == .active { recordSystemAppearance() } }
    }

    /// Sem tab bar: Home e Histórico são páginas lado a lado (Histórico à direita),
    /// trocadas arrastando para o lado, com o recipiente de água fixo por cima das
    /// duas. O Perfil é empilhado na navegação pelo botão de perfil do recipiente.
    private func mainContent(profile: UserProfile) -> some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    HomeView(profile: profile)
                        .containerRelativeFrame(.horizontal)
                        .id(MainPage.home)
                    HistoricoView(profile: profile)
                        .containerRelativeFrame(.horizontal)
                        .id(MainPage.historico)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedPage)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .overlay {
                GeometryReader { geo in
                    // Recipiente de água fixo por cima das duas páginas, no mesmo
                    // lugar do espaço que cada uma reserva para ele: ao arrastar, só o
                    // conteúdo abaixo dele troca. As partes sem toque deixam o arrasto
                    // chegar às páginas.
                    WaterHeaderView(profile: profile, screen: currentScreen, onOpenProfile: { showProfile = true })
                        .frame(height: TabScreenLayout.waterHeight(forVisibleHeight: geo.size.height, safeAreaTop: geo.safeAreaInsets.top))
                        .padding(.horizontal, 10)
                        .padding(.top, TabScreenLayout.waterTop(safeAreaTop: geo.safeAreaInsets.top))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    // Fixos por cima das duas páginas, no meio do espaço entre o fim do
                    // conteúdo (`spacing` acima da área segura) e a borda da tela.
                    PageDots(selection: $selectedPage)
                        .allowsHitTesting(false)
                        .padding(.bottom, (geo.safeAreaInsets.bottom + TabScreenLayout.spacing - PageDots.height) / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .appScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showProfile) {
                ProfileView(profile: profile)
                    .navigationTitle("Configurações")
            }
        }
        .tint(Color.appAccentText)
    }

    /// As permissões do sistema só são pedidas depois que o onboarding inteiro terminou
    /// (consentimento, perfil e tutorial de funcionalidades).
    private func requestPermissionsAfterOnboarding(for profile: UserProfile) {
        Task {
            await PermissionsCoordinator.requestAll()
            _ = await HealthKitService.shared.requestAuthorization()
            if HealthKitService.shared.isAuthorized {
                await HealthKitService.shared.syncFromHealthKit(userID: profile.userID, context: modelContext)
            }
        }
    }

    private func restoreFromICloud() async {
        let restored = await CloudKitSyncService.shared.syncFromCloud(context: modelContext)
        if restored, let profile = profiles.first {
            // Já passou pelo tour antes (em outro aparelho ou antes de reinstalar) — só
            // pede de novo as permissões do sistema, que não sobrevivem à reinstalação.
            hasSeenFeatureOnboarding = true
            requestPermissionsAfterOnboarding(for: profile)
        }
        hasCheckedICloud = true
    }

    private func startLiveActivityIfNeeded(for profile: UserProfile) {
        Task {
            await LiveActivityManager.shared.startIfNeeded(profile: profile, context: modelContext)
        }
    }
}

private enum MainPage: Hashable, CaseIterable {
    case home
    case historico

    var title: String {
        switch self {
        case .home: "Home"
        case .historico: "Histórico"
        }
    }
}

/// Bolinhas que mostram em qual página (Home ou Histórico) o usuário está. Só
/// indicam: a troca de página é pelo arrasto (ou pelo VoiceOver, ajustando).
private struct PageDots: View {
    static let height: CGFloat = dotSize + dotPadding * 2
    private static let dotSize: CGFloat = 7
    private static let dotPadding: CGFloat = 4

    @Binding var selection: MainPage?

    private var current: MainPage { selection ?? .home }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MainPage.allCases, id: \.self) { page in
                Circle()
                    .fill(page == current ? Color.appAccent : Color.appControlOutline)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .padding(Self.dotPadding)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Página \(current.title)")
        .accessibilityValue("\((MainPage.allCases.firstIndex(of: current) ?? 0) + 1) de \(MainPage.allCases.count)")
        .accessibilityAdjustableAction { direction in
            let pages = MainPage.allCases
            let index = pages.firstIndex(of: current) ?? 0
            switch direction {
            case .increment: if index + 1 < pages.count { selection = pages[index + 1] }
            case .decrement: if index > 0 { selection = pages[index - 1] }
            @unknown default: break
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
