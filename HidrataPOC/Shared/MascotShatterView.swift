import SwiftUI

/// Efeito de "quebra" do mascote ao bater a meta: racha a imagem numa malha
/// irregular (não um grid certinho — as linhas internas saem tortas, como uma
/// rachadura de pedra de verdade) e, assim que aparece, anima cada caco voando pra
/// fora do centro, puxado um pouco pra baixo (gravidade), girando e sumindo — sem
/// nunca voltar: é uma animação só, de ida. Cada instância é efêmera (nasce quando
/// o mascote explode e morre logo depois) e não se repete.
struct MascotShatterView: View {
    let imageName: String
    let width: CGFloat
    let height: CGFloat

    private static let columns = 4
    private static let rows = 4

    @State private var pieces: [ShatterPiece]
    @State private var animate = false

    init(imageName: String, width: CGFloat, height: CGFloat) {
        self.imageName = imageName
        self.width = width
        self.height = height
        _pieces = State(initialValue: Self.makePieces(width: width, height: height))
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Image(imageName)
                    .resizable()
                    // `.scaledToFit()`, igual ao mascote parado — `.scaledToFill()` cortava
                    // o topo/base da imagem (preenchendo a caixa toda em vez de mostrar a
                    // imagem inteira) e, por cobrir mais área sem a sobra do letterbox,
                    // também fazia o mascote parecer um pouco maior bem antes de quebrar.
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .clipShape(ShardShape(points: piece.corners))
                    .rotationEffect(.degrees(animate ? piece.spin : 0), anchor: piece.anchor)
                    .offset(
                        x: animate ? piece.direction.width * piece.distance : 0,
                        y: animate ? piece.direction.height * piece.distance : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(.easeIn(duration: 0.6).delay(piece.delay), value: animate)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        // Sem transição própria: entra e sai exatamente como está, sem o SwiftUI
        // tentar animar a troca de branch do pai (era isso que dava a impressão de
        // "voltar pro lugar" num fade por cima do resultado já quebrado).
        .transition(.identity)
        .onAppear { animate = true }
    }

    private struct ShatterPiece: Identifiable {
        let id: Int
        let corners: [CGPoint]   // coordenadas absolutas, no espaço width×height
        let anchor: UnitPoint    // centroide do caco, pra girar/escalar em volta do lugar certo
        let direction: CGSize    // direção de saída (não normalizada, já com viés pra baixo)
        let spin: Double         // graus ao final
        let delay: Double        // s — dessincroniza os cacos entre si
        let distance: CGFloat    // pt percorridos (proporcional ao tamanho da imagem)
    }

    /// Contorno de um caco: um polígono qualquer (aqui, sempre um quadrilátero),
    /// em coordenadas absolutas já calculadas — ignora o `rect` que o SwiftUI passa.
    private struct ShardShape: Shape {
        let points: [CGPoint]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            return path
        }
    }

    /// Malha de pontos (rows+1 × columns+1) com as linhas internas "tremidas" — as
    /// bordas externas ficam retas (no contorno da imagem), mas cada ponto interno
    /// sai deslocado até 40% do tamanho da célula, pra cada caco ter um contorno
    /// torto e diferente dos vizinhos, como uma pedra rachando de verdade, em vez de
    /// um grid perfeito de retângulos iguais.
    private static func makePieces(width: CGFloat, height: CGFloat) -> [ShatterPiece] {
        guard width > 0, height > 0 else { return [] }
        let cellW = width / CGFloat(columns)
        let cellH = height / CGFloat(rows)

        var grid: [[CGPoint]] = []
        for row in 0...rows {
            var rowPoints: [CGPoint] = []
            for col in 0...columns {
                var x = CGFloat(col) * cellW
                var y = CGFloat(row) * cellH
                if col > 0, col < columns {
                    x += CGFloat.random(in: -0.4...0.4) * cellW
                }
                if row > 0, row < rows {
                    y += CGFloat.random(in: -0.4...0.4) * cellH
                }
                rowPoints.append(CGPoint(x: x, y: y))
            }
            grid.append(rowPoints)
        }

        let center = CGPoint(x: width / 2, y: height / 2)
        var pieces: [ShatterPiece] = []
        pieces.reserveCapacity(columns * rows)
        var id = 0
        for row in 0..<rows {
            for col in 0..<columns {
                let corners = [
                    grid[row][col], grid[row][col + 1],
                    grid[row + 1][col + 1], grid[row + 1][col],
                ]
                let centroid = CGPoint(
                    x: corners.reduce(0) { $0 + $1.x } / 4,
                    y: corners.reduce(0) { $0 + $1.y } / 4
                )
                let anchor = UnitPoint(x: centroid.x / width, y: centroid.y / height)

                // Direção de saída: pra fora do centro da imagem, com um puxão extra
                // pra baixo (gravidade) e um tremor aleatório — cacos não voam reto.
                let cx = Double((centroid.x - center.x) / width)
                let cy = Double((centroid.y - center.y) / height)
                let outwardLen = max(0.15, (cx * cx + cy * cy).squareRoot())
                let dx = cx / outwardLen * 0.75 + Double.random(in: -0.35...0.35)
                let dy = cy / outwardLen * 0.55 + Double.random(in: 0.45...1.0)

                pieces.append(ShatterPiece(
                    id: id,
                    corners: corners,
                    anchor: anchor,
                    direction: CGSize(width: dx, height: dy),
                    spin: Double.random(in: -260...260),
                    delay: Double.random(in: 0...0.07),
                    // Proporcional ao tamanho da imagem: pra uma imagem grande, um
                    // deslocamento fixo em pontos passava quase despercebido e parecia
                    // só encolher/sumir no lugar, em vez de voar pra longe de verdade.
                    distance: CGFloat.random(in: 0.55...0.95) * max(width, height)
                ))
                id += 1
            }
        }
        return pieces
    }
}
