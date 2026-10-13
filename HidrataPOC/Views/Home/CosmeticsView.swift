import SwiftUI

/// Itens cosméticos que enfeitam o aquário da Home. Cada um é ligado/desligado
/// pela aba de cosméticos (`CosmeticsView`) e lembrado entre aberturas do app
/// (`@AppStorage(item.storageKey)`).
/// A ordem dos casos é a ordem dos cartões na aba; a ordem de desenho no recipiente
/// é `layerOrder`. Os desenhos ficam em `AquariumDecorations.swift`.
enum Cosmetic: String, CaseIterable, Identifiable {
    case grass
    case lemon
    case ice
    case mint
    case cucumber
    case berries
    case fizz
    case straw
    case droplets
    case kidneys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grass: "Gramadinho"
        case .lemon: "Rodelas de limão"
        case .ice: "Cubos de gelo"
        case .mint: "Folhas de hortelã"
        case .cucumber: "Pepino spa"
        case .berries: "Frutas vermelhas"
        case .fizz: "Água com gás"
        case .straw: "Canudinho"
        case .droplets: "Gotinhas aliadas"
        case .kidneys: "Torcida dos rins"
        }
    }

    var subtitle: String {
        switch self {
        case .grass: "Um tapete verde no fundo do aquário"
        case .lemon: "O citrato do limão é inimigo da pedra"
        case .ice: "Pedrinhas do bem, boiando lá em cima"
        case .mint: "Água saborizada e refrescante"
        case .cucumber: "Clima de spa no seu copo"
        case .berries: "Morangos e mirtilos pra dar cor"
        case .fizz: "Bolhinhas subindo sem parar"
        case .straw: "Listradinho, mergulhado na água"
        case .droplets: "Gotas sorridentes ajudando a dissolver"
        case .kidneys: "Seus rins pulando de alegria"
        }
    }

    var systemImage: String {
        switch self {
        case .grass: "leaf.fill"
        case .lemon: "circle.circle.fill"
        case .ice: "cube.transparent.fill"
        case .mint: "leaf"
        case .cucumber: "smallcircle.filled.circle.fill"
        case .berries: "heart.fill"
        case .fizz: "bubbles.and.sparkles.fill"
        case .straw: "takeoutbag.and.cup.and.straw.fill"
        case .droplets: "drop.fill"
        case .kidneys: "hands.clap.fill"
        }
    }

    /// Dias de streak necessários pra desbloquear o item. Por enquanto todos em 1,
    /// pra dar pra testar tudo — ajustar antes de lançar.
    var requiredStreak: Int {
        switch self {
        case .grass, .lemon, .ice, .mint, .cucumber, .berries, .fizz, .straw, .droplets, .kidneys: 1
        }
    }

    func isUnlocked(streak: Int) -> Bool { streak >= requiredStreak }

    var tint: Color {
        switch self {
        case .grass: Color(red: 0.30, green: 0.69, blue: 0.31)
        case .lemon: Color(red: 0.92, green: 0.75, blue: 0.05)
        case .ice: Color(red: 0.45, green: 0.75, blue: 0.95)
        case .mint: Color(red: 0.20, green: 0.66, blue: 0.38)
        case .cucumber: Color(red: 0.35, green: 0.62, blue: 0.25)
        case .berries: Color(red: 0.90, green: 0.22, blue: 0.30)
        case .fizz: Color(red: 0.30, green: 0.68, blue: 0.95)
        case .straw: Color(red: 0.95, green: 0.30, blue: 0.40)
        case .droplets: Color(red: 0.25, green: 0.58, blue: 0.98)
        case .kidneys: Color(red: 0.88, green: 0.42, blue: 0.45)
        }
    }

    /// Ordem de desenho, de trás pra frente: o canudinho atrás de tudo, depois o que
    /// fica no chão, as bolhas, o que boia e, por cima, as gotinhas e o gelo.
    var layerOrder: Int {
        switch self {
        case .straw: 0
        case .grass: 1
        case .kidneys: 2
        case .fizz: 3
        case .mint: 4
        case .cucumber: 5
        case .berries: 6
        case .lemon: 7
        case .droplets: 8
        case .ice: 9
        }
    }

    /// Itens que ficam no chão entram subindo de baixo; o resto só aparece.
    var sitsOnFloor: Bool {
        switch self {
        case .grass, .kidneys: true
        case .lemon, .ice, .mint, .cucumber, .berries, .fizz, .straw, .droplets: false
        }
    }

    /// Chave do `@AppStorage` que guarda se o item está equipado.
    var storageKey: String { "cosmetic.equipped.\(rawValue)" }
}

/// Aba aberta pelo botão de cosméticos no aquário: lista os itens e liga/desliga
/// cada um com um toque. Itens ainda bloqueados (streak abaixo de
/// `Cosmetic.requiredStreak`) aparecem com cadeado e não respondem ao toque.
struct CosmeticsView: View {
    let streak: Int

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Cosmetic.allCases) { item in
                        CosmeticItemButton(item: item, isUnlocked: item.isUnlocked(streak: streak))
                    }
                }
                .padding(20)
            }
            .appScreenBackground()
            .navigationTitle("Cosméticos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Cartão de um item: toque liga/desliga. Equipado = borda e selo na cor do item.
/// Bloqueado = apagado, com cadeado e o requisito no lugar da descrição.
private struct CosmeticItemButton: View {
    let item: Cosmetic
    let isUnlocked: Bool

    @AppStorage private var isEquipped: Bool

    init(item: Cosmetic, isUnlocked: Bool) {
        self.item = item
        self.isUnlocked = isUnlocked
        _isEquipped = AppStorage(wrappedValue: false, item.storageKey)
    }

    private var showsEquipped: Bool { isUnlocked && isEquipped }

    private var lockedText: String {
        "Desbloqueie com \(item.requiredStreak) \(item.requiredStreak == 1 ? "dia" : "dias") de streak"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isEquipped.toggle() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(isUnlocked ? item.tint : Color.appSecondary)
                    .frame(height: 56)
                    .opacity(isUnlocked ? 1 : 0.4)
                Text(item.title)
                    .font(.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundStyle(isUnlocked ? Color.primary : Color.appSecondary)
                Text(isUnlocked ? item.subtitle : lockedText)
                    .font(.custom("Nunito", size: 12))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(showsEquipped ? item.tint : .clear, lineWidth: 3)
            }
            .overlay(alignment: .topTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                        .padding(12)
                } else if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, item.tint)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityLabel(item.title)
        .accessibilityValue(isUnlocked ? (isEquipped ? "Equipado" : "Não equipado") : "Bloqueado")
        .accessibilityHint(isUnlocked ? "Toque para \(isEquipped ? "remover do" : "colocar no") aquário" : lockedText)
    }
}

/// Gramadinho no fundo do aquário: um morrinho verde com folhas de grama de
/// alturas e inclinações variadas (fixas — geradas com semente, pra não mudarem
/// a cada redesenho).
struct GrassView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let base = h * 0.45

            // Folhas atrás (mais escuras), depois o morro, depois folhas na frente.
            drawBlades(in: &context, width: w, height: h, base: base, seed: 7, count: Int(w / 6),
                       color: Color(red: 0.18, green: 0.52, blue: 0.22), heightScale: 1.0)

            var mound = Path()
            mound.move(to: CGPoint(x: 0, y: h))
            mound.addLine(to: CGPoint(x: 0, y: h - base * 0.8))
            mound.addCurve(
                to: CGPoint(x: w, y: h - base * 0.7),
                control1: CGPoint(x: w * 0.3, y: h - base * 1.25),
                control2: CGPoint(x: w * 0.7, y: h - base * 1.15)
            )
            mound.addLine(to: CGPoint(x: w, y: h))
            mound.closeSubpath()
            context.fill(mound, with: .linearGradient(
                Gradient(colors: [Color(red: 0.36, green: 0.74, blue: 0.33), Color(red: 0.22, green: 0.55, blue: 0.24)]),
                startPoint: CGPoint(x: 0, y: h - base * 1.2),
                endPoint: CGPoint(x: 0, y: h)
            ))

            drawBlades(in: &context, width: w, height: h, base: base * 0.75, seed: 19, count: Int(w / 9),
                       color: Color(red: 0.42, green: 0.80, blue: 0.36), heightScale: 0.7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBlades(in context: inout GraphicsContext, width: CGFloat, height: CGFloat, base: CGFloat,
                            seed: UInt64, count: Int, color: Color, heightScale: CGFloat) {
        var rng = SeededGenerator(seed: seed)
        guard count > 0 else { return }
        for i in 0..<count {
            let x = (CGFloat(i) + CGFloat.random(in: 0...1, using: &rng)) * width / CGFloat(count)
            let bladeH = (height - base * 0.6) * CGFloat.random(in: 0.45...1.0, using: &rng) * heightScale
            let lean = CGFloat.random(in: -8...8, using: &rng)
            let halfW = CGFloat.random(in: 2...3.5, using: &rng)
            let rootY = height - base * 0.6

            var blade = Path()
            blade.move(to: CGPoint(x: x - halfW, y: rootY))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: rootY - bladeH), control: CGPoint(x: x - halfW + lean * 0.3, y: rootY - bladeH * 0.6))
            blade.addQuadCurve(to: CGPoint(x: x + halfW, y: rootY), control: CGPoint(x: x + halfW + lean * 0.3, y: rootY - bladeH * 0.6))
            blade.closeSubpath()
            context.fill(blade, with: .color(color))
        }
    }
}

/// Gerador determinístico (SplitMix64) — o gramado (e as bolhinhas) saem iguais
/// toda vez.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#Preview {
    CosmeticsView(streak: 0)
}
