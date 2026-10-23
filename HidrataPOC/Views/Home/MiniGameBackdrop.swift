import SwiftUI

/// Fundo comum dos minijogos, desenhado no `Canvas` do jogo antes de tudo, pra água não
/// parecer vazia: manchas grandes e desfocadas nas cores das pedrinhas, quase transparentes,
/// flutuando devagar. Só depende do relógio, não da simulação. O Rim Comilão e o Campo
/// Minado não usam: o labirinto e o tabuleiro já ocupam a tela toda.
enum MiniGameBackdrop {
    /// Abaixo disso as manchas somem no fundo claro; acima, começam a sujar a água.
    private static let strength = 0.22

    /// Manchas: ponto de partida (fração da largura/altura), raio (fração da largura),
    /// cor (índice em `PebbleGameTuning.colors`) e velocidade (rad/s).
    private static let glows: [(anchor: CGPoint, radius: CGFloat, colorIndex: Int, speed: Double)] = [
        (CGPoint(x: 0.18, y: 0.22), 0.55, 3, 0.11),
        (CGPoint(x: 0.85, y: 0.30), 0.50, 1, 0.09),
        (CGPoint(x: 0.30, y: 0.62), 0.50, 2, 0.13),
        (CGPoint(x: 0.80, y: 0.72), 0.55, 0, 0.10),
        (CGPoint(x: 0.55, y: 0.45), 0.40, 1, 0.08),
    ]

    static func draw(time: Double, size: CGSize, in ctx: inout GraphicsContext) {
        for (i, glow) in glows.enumerated() {
            // Cada mancha percorre uma curva lenta e fechada em volta do seu ponto de partida.
            let x = glow.anchor.x + CGFloat(sin(time * glow.speed + Double(i) * 1.9)) * 0.10
            let y = glow.anchor.y + CGFloat(cos(time * glow.speed * 0.8 + Double(i) * 2.7)) * 0.06
            let center = CGPoint(x: x * size.width, y: y * size.height)
            let radius = glow.radius * size.width
            let breathing = 0.85 + 0.15 * sin(time * 0.4 + Double(i))
            let color = PebbleGameTuning.colors[glow.colorIndex % PebbleGameTuning.colors.count]
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(strength * breathing), color.opacity(0)]),
                    center: center, startRadius: 0, endRadius: radius
                )
            )
        }
    }
}
