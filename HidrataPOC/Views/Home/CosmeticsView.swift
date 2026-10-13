import SwiftUI

/// Itens cosméticos que enfeitam o aquário da Home. Cada um é ligado/desligado
/// pela aba de cosméticos (`CosmeticsView`) e lembrado entre aberturas do app
/// (`@AppStorage(item.storageKey)`).
/// A ordem dos casos é a ordem dos cartões na aba; a ordem de desenho no aquário
/// é `layerOrder`. Os desenhos ficam em `AquariumDecorations.swift`.
enum Cosmetic: String, CaseIterable, Identifiable {
    case grass
    case shells
    case seaweed
    case coral
    case chest
    case bubbles
    case fish
    case jellyfish
    case sunRays
    case plankton

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grass: "Gramadinho"
        case .shells: "Conchinhas"
        case .seaweed: "Algas dançantes"
        case .coral: "Recife de coral"
        case .chest: "Baú do tesouro"
        case .bubbles: "Borbulhas"
        case .fish: "Cardume"
        case .jellyfish: "Água-viva"
        case .sunRays: "Raios de sol"
        case .plankton: "Plâncton brilhante"
        }
    }

    var subtitle: String {
        switch self {
        case .grass: "Um tapete verde no fundo do aquário"
        case .shells: "Vieira, estrela-do-mar e caramujo na areia"
        case .seaweed: "Balançam com a correnteza nas laterais"
        case .coral: "Corais coloridos no cantinho direito"
        case .chest: "Moedas de ouro e um brilho suspeito"
        case .bubbles: "Bolhinhas subindo até a superfície"
        case .fish: "Três peixinhos nadando pra lá e pra cá"
        case .jellyfish: "Flutua devagar, pulsando de leve"
        case .sunRays: "Feixes de luz entrando pela água"
        case .plankton: "Pontinhos que brilham — lindo no escuro"
        }
    }

    var systemImage: String {
        switch self {
        case .grass: "leaf.fill"
        case .shells: "star.fill"
        case .seaweed: "camera.macro"
        case .coral: "tree.fill"
        case .chest: "shippingbox.fill"
        case .bubbles: "bubbles.and.sparkles.fill"
        case .fish: "fish.fill"
        case .jellyfish: "umbrella.fill"
        case .sunRays: "sun.max.fill"
        case .plankton: "sparkles"
        }
    }

    /// Dias de streak necessários pra desbloquear o item. Por enquanto todos em 1,
    /// pra dar pra testar tudo — ajustar antes de lançar.
    var requiredStreak: Int {
        switch self {
        case .grass, .shells, .seaweed, .coral, .chest, .bubbles, .fish, .jellyfish, .sunRays, .plankton: 1
        }
    }

    func isUnlocked(streak: Int) -> Bool { streak >= requiredStreak }

    var tint: Color {
        switch self {
        case .grass: Color(red: 0.30, green: 0.69, blue: 0.31)
        case .shells: Color(red: 1.0, green: 0.55, blue: 0.25)
        case .seaweed: Color(red: 0.16, green: 0.58, blue: 0.42)
        case .coral: Color(red: 1.0, green: 0.42, blue: 0.48)
        case .chest: Color(red: 0.85, green: 0.62, blue: 0.10)
        case .bubbles: Color(red: 0.25, green: 0.65, blue: 0.95)
        case .fish: Color(red: 1.0, green: 0.50, blue: 0.15)
        case .jellyfish: Color(red: 0.88, green: 0.42, blue: 0.80)
        case .sunRays: Color(red: 0.98, green: 0.72, blue: 0.10)
        case .plankton: Color(red: 0.10, green: 0.75, blue: 0.70)
        }
    }

    /// Ordem de desenho no aquário, de trás pra frente: luz ao fundo, plantas e
    /// objetos no chão, depois o que nada por cima.
    var layerOrder: Int {
        switch self {
        case .sunRays: 0
        case .seaweed: 1
        case .coral: 2
        case .grass: 3
        case .chest: 4 // na frente da grama, senão as folhas cobrem o baú
        case .shells: 5
        case .jellyfish: 6
        case .fish: 7
        case .bubbles: 8
        case .plankton: 9
        }
    }

    /// Itens que ficam no chão entram subindo de baixo; os que nadam só aparecem.
    var sitsOnFloor: Bool {
        switch self {
        case .grass, .shells, .seaweed, .coral, .chest: true
        case .bubbles, .fish, .jellyfish, .sunRays, .plankton: false
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

/// Gerador determinístico (SplitMix64) — o gramado (e os outros desenhos) saem
/// iguais toda vez.
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
