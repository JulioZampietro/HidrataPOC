import SwiftUI

/// Minijogos que rodam no aquário da Home. Cada um é desbloqueado ao alcançar
/// `requiredStreak` dias de streak; só um fica ativo por vez (ou nenhum, com `.noGame`:
/// o aquário fica só com as pedrinhas), escolhido na aba de minijogos (`MiniGamesView`) e
/// lembrado entre aberturas do app (`@AppStorage(MiniGame.selectedStorageKey)`). O escolhido
/// entra sozinho quando a meta do dia é batida, e com pelo menos `minimumStreakToPlay` dias
/// de streak dá pra jogar a qualquer hora tocando nele na aba.
///
/// Pra criar um jogo novo: adicione o `case` aqui (com título, ícone e streak necessária)
/// e trate o `case` na Home (`HomeView`), onde o jogo é desenhado e controlado.
enum MiniGame: String, CaseIterable, Identifiable {
    case noGame
    case rings
    case jump
    case bubbles
    case flappy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noGame: "Sem jogo"
        case .rings: "Argolas"
        case .jump: "Gota Saltitante"
        case .bubbles: "Bolhas Coloridas"
        case .flappy: "Gota Voadora"
        }
    }

    var subtitle: String {
        switch self {
        case .noGame: "Só a água e as pedrinhas, sem minijogo"
        case .rings: "Use os jatos d'água prazsfs encaixar as argolas nos pinos"
        case .jump: "Pule de pedra em pedra e suba o mais alto que der"
        case .bubbles: "Mire e junte 4 bolhas da mesma cor pra estourar"
        case .flappy: "Toque pra nadar e passe entre as pilhas de pedras"
        }
    }

    var systemImage: String {
        switch self {
        case .noGame: "nosign"
        case .rings: "circle.circle"
        case .jump: "arrow.up.to.line"
        case .bubbles: "circle.hexagongrid.fill"
        case .flappy: "bird.fill"
        }
    }

    /// Dias de streak necessários pra desbloquear o jogo.
    var requiredStreak: Int {
        switch self {
        case .noGame: 0
        case .rings: 1
        case .jump: 3
        case .bubbles: 5
        case .flappy: 7
        }
    }

    /// `false` só pro `.noGame`, que é a opção de não jogar nada.
    var isPlayable: Bool { self != .noGame }

    func isUnlocked(streak: Int) -> Bool { streak >= requiredStreak }

    var tint: Color {
        switch self {
        case .noGame: Color(red: 0.55, green: 0.60, blue: 0.68)
        case .rings: Color(red: 0.93, green: 0.26, blue: 0.28)
        case .jump: Color(red: 0.25, green: 0.78, blue: 0.42)
        case .bubbles: Color(red: 0.66, green: 0.42, blue: 0.95)
        case .flappy: Color(red: 0.98, green: 0.56, blue: 0.20)
        }
    }

    /// Chave do `@AppStorage` com o `rawValue` do jogo escolhido (vazio = nunca escolheu).
    static let selectedStorageKey = "minigame.selected"
    /// Chave do `@AppStorage` com os jogos (separados por vírgula) cujo desbloqueio já foi
    /// anunciado — o aviso de "novo minijogo" aparece só uma vez por jogo.
    static let announcedStorageKey = "minigame.announced"
    /// Chave do `@AppStorage` com o recorde da Gota Saltitante.
    static let jumpBestStorageKey = "minigame.jump.best"
    /// Chave do `@AppStorage` com o recorde das Bolhas Coloridas.
    static let bubblesBestStorageKey = "minigame.bubbles.best"
    /// Chave do `@AppStorage` com o recorde da Gota Voadora.
    static let flappyBestStorageKey = "minigame.flappy.best"

    /// Streak mínima pra jogar fora da meta batida (tocando no jogo na aba de minijogos).
    static let minimumStreakToPlay = 1

    /// Jogos de verdade (sem o `.noGame`) já liberados pela streak, na ordem de desbloqueio.
    static func unlocked(streak: Int) -> [MiniGame] {
        allCases.filter { $0.isPlayable && $0.isUnlocked(streak: streak) }.sorted { $0.requiredStreak < $1.requiredStreak }
    }

    /// Opção escolhida pra quando bater a meta: a do usuário, se ainda estiver liberada;
    /// senão o último jogo liberado; `.noGame` se a streak ainda não liberou nenhum.
    static func active(selected rawValue: String, streak: Int) -> MiniGame {
        if let selected = MiniGame(rawValue: rawValue), selected.isUnlocked(streak: streak) { return selected }
        return unlocked(streak: streak).last ?? .noGame
    }
}

/// Estado dos minijogos dividido entre o aquário (`WaterHeaderView`, que desenha o jogo e
/// decide quando ele roda) e a Home (`HomeView`, onde ficam os botões do jogo). O `RootView`
/// cria um só e o passa pelo ambiente pros dois.
@MainActor
@Observable
final class MiniGameController {
    @ObservationIgnored let ringGame = RingGameSimulation()
    @ObservationIgnored let jumpGame = JumpGameSimulation()
    @ObservationIgnored let bubbleGame = BubbleGameSimulation()
    @ObservationIgnored let flappyGame = FlappyGameSimulation()
    /// Jogo rodando no aquário agora (meta batida e um jogo de verdade escolhido) — quem
    /// define é o `WaterHeaderView`.
    var runningGame: MiniGame?
    /// O usuário tocou num jogo na aba de minijogos pra jogar agora, mesmo sem a meta batida.
    /// Acaba ao sair do jogo pela seta do aquário ou ao escolher "Sem jogo".
    var playsOnDemand = false
    /// Alguma animação do mascote está rodando (montagem do início do dia, bolhas de troca de
    /// estágio, explosão da meta batida) — quem define é o `WaterHeaderView`. Enquanto isso os
    /// botões do aquário e da Home não respondem ao toque.
    var isMascotAnimating = false

    /// Botões do jogo no lugar dos cartões de ingestão.
    var showsGameControls: Bool { runningGame != nil }
}

/// Aba aberta pelo botão de minijogos no aquário: lista os jogos e, com um toque, escolhe
/// qual aparece quando a meta do dia for batida e já começa a jogá-lo no aquário (com pelo
/// menos `MiniGame.minimumStreakToPlay` dias de streak). Jogos ainda bloqueados (streak abaixo
/// de `MiniGame.requiredStreak`) aparecem com cadeado e não respondem ao toque.
struct MiniGamesView: View {
    let streak: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(MiniGameController.self) private var miniGames
    @AppStorage(MiniGame.selectedStorageKey) private var selectedRaw = ""

    private var canPlay: Bool { streak >= MiniGame.minimumStreakToPlay }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var activeGame: MiniGame { MiniGame.active(selected: selectedRaw, streak: streak) }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Toque num jogo pra jogar agora. Ele também entra quando você bate a meta do dia, e cada dia de streak libera jogos novos!")
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if !canPlay {
                    Label("Você precisa de pelo menos \(MiniGame.minimumStreakToPlay) dia de streak pra jogar. Bata a meta de hoje pra começar!",
                          systemImage: "lock.fill")
                        .font(.custom("Nunito", size: 14).weight(.bold))
                        .foregroundStyle(Color.appAccentText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(MiniGame.allCases) { game in
                        MiniGameItemButton(
                            game: game,
                            isUnlocked: game.isUnlocked(streak: streak),
                            isSelected: activeGame == game,
                            canPlay: canPlay
                        ) {
                            select(game)
                        }
                    }
                }
                .padding(20)
            }
            .appScreenBackground()
            .navigationTitle("Minijogos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Escolhe o jogo; com streak suficiente, fecha a aba e ele começa no aquário na hora.
    /// "Sem jogo" encerra uma partida que estivesse rolando fora da meta batida.
    private func select(_ game: MiniGame) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedRaw = game.rawValue }
        guard game.isPlayable else {
            miniGames.playsOnDemand = false
            return
        }
        guard canPlay else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { miniGames.playsOnDemand = true }
        dismiss()
    }
}

/// Cartão de um jogo: toque escolhe o jogo. Escolhido = borda e selo na cor do jogo.
/// Bloqueado = apagado, com cadeado e o requisito no lugar da descrição.
private struct MiniGameItemButton: View {
    let game: MiniGame
    let isUnlocked: Bool
    let isSelected: Bool
    let canPlay: Bool
    let onSelect: () -> Void

    private var showsSelected: Bool { isUnlocked && isSelected }

    private var lockedText: String {
        "Desbloqueie com \(game.requiredStreak) \(game.requiredStreak == 1 ? "dia" : "dias") de streak"
    }

    var body: some View {
        Button {
            if isSelected { Haptic.tap.play() } else { Haptic.primary.play() }
            onSelect()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: game.systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(isUnlocked ? game.tint : Color.appSecondary)
                    .frame(height: 56)
                    .opacity(isUnlocked ? 1 : 0.4)
                Text(game.title)
                    .font(.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundStyle(isUnlocked ? Color.primary : Color.appSecondary)
                Text(isUnlocked ? game.subtitle : lockedText)
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(showsSelected ? game.tint : .clear, lineWidth: 3)
            }
            .overlay(alignment: .topTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                        .padding(12)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, game.tint)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityLabel(game.title)
        .accessibilityValue(isUnlocked ? (isSelected ? "Escolhido" : "Não escolhido") : "Bloqueado")
        .accessibilityHint(isUnlocked ? (game.isPlayable ? (canPlay ? "Toque para jogar agora" : "Toque para jogar este quando bater a meta") : "Toque para não jogar nada quando bater a meta") : lockedText)
    }
}

/// Aviso no topo do aquário quando a streak libera um jogo novo.
struct MiniGameUnlockedBanner: View {
    let game: MiniGame

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(game.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("Novo minijogo liberado!")
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(Color.appSecondary)
                Text(game.title)
                    .font(.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MiniGamesView(streak: 0)
        .environment(MiniGameController())
}
