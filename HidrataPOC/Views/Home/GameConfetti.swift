import SwiftUI

/// Pedacinho de confete da comemoração de fim de jogo, já em pontos do `Canvas`.
struct Confetto: Sendable {
    let position: CGPoint
    let size: CGSize
    let angle: CGFloat
    /// 0…1: achata o pedacinho enquanto ele gira de lado.
    let flip: CGFloat
    let colorIndex: Int
    let alpha: CGFloat
}

/// Chuva de confete dos minijogos (Pedras Coloridas, Argolas, Rim Comilão, Campo Minado): sai dos
/// dois cantos de baixo e cai do alto da tela. Cada simulação guarda uma e chama `update` por
/// frame; o `Canvas` desenha o `snapshot()` com `GameConfetti.draw`.
struct ConfettiShower {
    private struct Piece {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var angle: Float
        var spin: Float
        var flipPhase: Float
        let size: SIMD2<Float>
        let colorIndex: Int
        var life: Float
    }

    static let pieceCount = 150

    private var pieces: [Piece] = []

    /// Solta o confete junto com o háptico de comemoração (os dois sempre andam juntos).
    @MainActor
    mutating func burst(in size: CGSize, colorCount: Int) {
        Haptic.celebrate.play()
        let width = Float(size.width), height = Float(size.height)
        for i in 0..<Self.pieceCount {
            let fromCorner = i % 3 != 0
            let position: SIMD2<Float>
            let velocity: SIMD2<Float>
            if fromCorner {
                let left = i % 2 == 0
                position = SIMD2(left ? 0 : width, height * 0.85)
                velocity = SIMD2((left ? 1 : -1) * Float.random(in: 120...420), -Float.random(in: 450...950))
            } else {
                position = SIMD2(Float.random(in: 0...width), -Float.random(in: 10...height * 0.3))
                velocity = SIMD2(Float.random(in: -60...60), Float.random(in: 40...200))
            }
            pieces.append(Piece(
                position: position, velocity: velocity,
                angle: Float.random(in: 0...(2 * .pi)), spin: Float.random(in: -8...8),
                flipPhase: Float.random(in: 0...(2 * .pi)),
                size: SIMD2(Float.random(in: 6...10), Float.random(in: 10...16)),
                colorIndex: Int.random(in: 0..<max(1, colorCount)),
                life: Float.random(in: 2.6...4)
            ))
        }
    }

    mutating func update(dt: Float) {
        for i in pieces.indices {
            pieces[i].life -= dt
            pieces[i].velocity.y += 520 * dt
            pieces[i].velocity *= exp(-0.9 * dt) // o ar segura o confete, que cai balançando
            pieces[i].position += pieces[i].velocity * dt
            pieces[i].angle += pieces[i].spin * dt
            pieces[i].flipPhase += 6 * dt
        }
        pieces.removeAll { $0.life <= 0 }
    }

    mutating func clear() {
        pieces.removeAll()
    }

    func snapshot() -> [Confetto] {
        pieces.map {
            Confetto(position: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)),
                     size: CGSize(width: CGFloat($0.size.x), height: CGFloat($0.size.y)),
                     angle: CGFloat($0.angle), flip: CGFloat(abs(cos($0.flipPhase))),
                     colorIndex: $0.colorIndex, alpha: CGFloat(min(1, $0.life / 0.8)))
        }
    }
}

enum GameConfetti {
    /// Retângulos coloridos que giram e achatam; `colors` é indexada por `colorIndex`.
    static func draw(_ confetti: [Confetto], colors: [Color], in ctx: inout GraphicsContext) {
        for piece in confetti {
            var pieceCtx = ctx
            pieceCtx.opacity = piece.alpha
            pieceCtx.translateBy(x: piece.position.x, y: piece.position.y)
            pieceCtx.rotate(by: .radians(piece.angle))
            let height = piece.size.height * max(0.15, piece.flip)
            let rect = CGRect(x: -piece.size.width / 2, y: -height / 2, width: piece.size.width, height: height)
            pieceCtx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[piece.colorIndex % colors.count]))
        }
    }
}
