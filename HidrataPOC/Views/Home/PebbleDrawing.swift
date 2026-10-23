import SwiftUI

/// Pedrinha facetada no estilo das pedrinhas do rim (e dos cacos do mascote), desenhada num
/// `Canvas`: contorno irregular, uma face de cima clara puxada pra luz e faces laterais em volta,
/// cada uma mais clara ou mais escura conforme está virada pra luz, com borda escura e um brilho
/// pequeno. Usada nas Pedras Coloridas (pedrinhas redondas) e nas plataformas da Gota Saltitante
/// (lajes achatadas). A semente fixa o formato, então a mesma pedra não muda de cara entre frames.
enum PebbleDrawing {
    /// Marrom das pedrinhas do rim: misturado às cores vivas pra puxá-las pro tom de pedra.
    static let stoneBrown = Color(red: 0.55, green: 0.44, blue: 0.33)
    /// Direção de onde vem a luz (cima-esquerda), a mesma das pedrinhas do aquário.
    private static let lightDirection = CGVector(dx: -0.55, dy: -0.83)

    /// Desenha a pedra com centro `center` e semieixos `radiusX` × `radiusY` (iguais = redonda).
    /// - Parameters:
    ///   - sides: quantos lados o contorno pode ter (sorteado pela semente).
    ///   - castsShadow: sombra suave logo abaixo, pra pedra parecer apoiada.
    ///   - cracked: trinca na face de cima (pedra que quebra ao pisar).
    static func draw(
        center c: CGPoint,
        radiusX rx: CGFloat,
        radiusY ry: CGFloat,
        tint: Color,
        seed: Int,
        sides: ClosedRange<Int> = 7...9,
        castsShadow: Bool = false,
        cracked: Bool = false,
        in context: inout GraphicsContext
    ) {
        var random = SeededRandom(seed: UInt64(seed))

        let count = sides.lowerBound + min(Int(random.next() * CGFloat(sides.count)), sides.count - 1)
        let start = random.next() * 2 * .pi
        let vertices: [CGPoint] = (0..<count).map { i in
            let angle = start + (CGFloat(i) + (random.next() - 0.5) * 0.5) / CGFloat(count) * 2 * .pi
            let distance = 0.84 + 0.16 * random.next()
            return CGPoint(x: c.x + cos(angle) * rx * distance, y: c.y + sin(angle) * ry * distance)
        }
        // Face de cima: o mesmo contorno, menor e deslocado pra luz (cima-esquerda).
        let topCenter = CGPoint(x: c.x - rx * (0.1 + 0.08 * random.next()), y: c.y - ry * (0.14 + 0.08 * random.next()))
        let topScale = 0.5 + 0.1 * random.next()
        let top = vertices.map { CGPoint(x: topCenter.x + ($0.x - c.x) * topScale, y: topCenter.y + ($0.y - c.y) * topScale) }

        var outline = Path()
        outline.addLines(vertices)
        outline.closeSubpath()
        if castsShadow {
            context.fill(outline.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.18)))
        }

        let edge = tint.mix(with: .black, by: 0.5)
        for i in vertices.indices {
            let j = (i + 1) % vertices.count
            var face = Path()
            face.addLines([vertices[i], vertices[j], top[j], top[i]])
            face.closeSubpath()
            // Direção da face no espaço "redondo" (dividindo pelos semieixos), pra uma laje
            // achatada ter o mesmo sombreado que uma pedra redonda.
            let mid = CGPoint(x: ((vertices[i].x + vertices[j].x) / 2 - c.x) / rx, y: ((vertices[i].y + vertices[j].y) / 2 - c.y) / ry)
            let length = max(hypot(mid.x, mid.y), 0.001)
            let light = (mid.x * lightDirection.dx + mid.y * lightDirection.dy) / length
            let shade = light > 0 ? tint.mix(with: .white, by: 0.12 * light) : tint.mix(with: .black, by: 0.32 * -light)
            context.fill(face, with: .color(shade))
            context.stroke(face, with: .color(edge.opacity(0.3)), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        }
        var topFace = Path()
        topFace.addLines(top)
        topFace.closeSubpath()
        context.fill(topFace, with: .color(tint.mix(with: .white, by: 0.2)))

        if cracked {
            // Trinca em zigue-zague atravessando a face de cima.
            var crack = Path()
            let steps = 4
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let x = topCenter.x + (t - 0.5) * rx * topScale * 1.6
                let y = topCenter.y + (step.isMultiple(of: 2) ? -1 : 1) * ry * topScale * 0.35
                if step == 0 { crack.move(to: CGPoint(x: x, y: y)) } else { crack.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(crack, with: .color(edge.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }

        context.stroke(outline, with: .color(edge), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        // Brilho: manchinha clara na face de cima, como nas pedrinhas do mascote.
        context.fill(Path(ellipseIn: CGRect(x: topCenter.x - rx * 0.3, y: topCenter.y - ry * 0.24, width: rx * 0.3, height: ry * 0.18)),
                     with: .color(.white.opacity(0.5)))
    }
}

/// Gerador pseudoaleatório com semente (SplitMix64): a mesma semente dá sempre o mesmo
/// formato de pedra, frame após frame.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// Próximo número entre 0 e 1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
