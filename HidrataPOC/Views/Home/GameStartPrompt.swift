import SwiftUI

/// Aviso de início comum a todos os minijogos, desenhado no `Canvas` do jogo enquanto ele espera
/// o primeiro toque: título opcional ("Fase N"), "Toque pra começar" e uma linha dizendo como
/// jogar. Todos os jogos usam este
/// mesmo desenho, então a tela de espera é igual em todos; só o texto e a altura mudam. Linhas
/// compridas (ou fonte grande no Dynamic Type) quebram dentro da largura do jogo.
enum GameStartPrompt {
    /// Texto: azul no modo claro (o branco some na água clara) e branco no escuro; o `Canvas`
    /// resolve a cor dinâmica pelo ambiente. A sombra faz o contrário: halo branco no claro, azul no escuro.
    private static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white
        : UIColor(red: 0.07, green: 0.30, blue: 0.72, alpha: 1) })
    private static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.05, green: 0.25, blue: 0.6, alpha: 0.45)
        : UIColor.white.withAlphaComponent(0.8) })
    private static let sideMargin: CGFloat = 24
    private static let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)

    /// `centerY` é o centro do aviso, em pontos do `Canvas`: cada jogo escolhe um trecho livre
    /// do próprio tabuleiro. `action` troca o "Toque pra começar" (ex.: recomeçar depois da vitória).
    static func draw(
        title: String? = nil,
        action: String = "Toque pra começar",
        hint: String,
        centerY: CGFloat,
        size: CGSize,
        in ctx: inout GraphicsContext
    ) {
        let maxWidth = size.width - sideMargin * 2
        var lines: [(resolved: GraphicsContext.ResolvedText, size: CGSize)] = []
        func add(_ string: String, fontSize: CGFloat, weight: Font.Weight, opacity: Double) {
            let font = Font.custom("Nunito", size: fontSize).weight(weight)
            for piece in wrapped(string, font: font, maxWidth: maxWidth, in: ctx) {
                let resolved = ctx.resolve(Text(piece).font(font).foregroundStyle(ink.opacity(opacity)))
                lines.append((resolved, resolved.measure(in: unbounded)))
            }
        }
        if let title { add(title, fontSize: 30, weight: .black, opacity: 1) }
        add(action, fontSize: 22, weight: .black, opacity: 1)
        add(hint, fontSize: 14, weight: .bold, opacity: 0.9)

        let spacing: CGFloat = 4
        let blockHeight = lines.reduce(0) { $0 + $1.size.height } + spacing * CGFloat(lines.count - 1)

        var textCtx = ctx
        textCtx.addFilter(.shadow(color: shadow, radius: 3, y: 1))
        var y = centerY - blockHeight / 2
        for line in lines {
            textCtx.draw(line.resolved, at: CGPoint(x: size.width / 2, y: y + line.size.height / 2), anchor: .center)
            y += line.size.height + spacing
        }
    }

    /// Quebra `string` em linhas de até `maxWidth`, por palavras (uma palavra maior que a largura
    /// fica sozinha na linha).
    private static func wrapped(_ string: String, font: Font, maxWidth: CGFloat, in ctx: GraphicsContext) -> [String] {
        func width(_ text: String) -> CGFloat {
            ctx.resolve(Text(text).font(font)).measure(in: unbounded).width
        }
        var result: [String] = []
        var current = ""
        for word in string.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if current.isEmpty || width(candidate) <= maxWidth {
                current = candidate
            } else {
                result.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
