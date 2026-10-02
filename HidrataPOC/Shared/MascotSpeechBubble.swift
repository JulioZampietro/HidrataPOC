import SwiftUI

/// Balão de fala do mascote — cauda no canto inferior-esquerdo aponta
/// para o centro da tela (onde o mascote está posicionado).
struct MascotSpeechBubble: View {
    let text: String

    private let tailHeight: CGFloat = 10
    private let tailWidth: CGFloat = 14
    private let tailX: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.custom("Nunito", size: 13).weight(.bold))
            .foregroundStyle(Color(red: 0.6314, green: 0.5333, blue: 0.3922))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.bottom, tailHeight)
            .frame(maxWidth: 150)
            .background(
                SpeechBubbleShape(
                    cornerRadius: 14,
                    tailHeight: tailHeight,
                    tailWidth: tailWidth,
                    tailX: tailX
                )
                .fill(Color(red: 0.9725, green: 0.9294, blue: 0.8667))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
            )
    }
}

/// Rounded rectangle com cauda triangular na base, deslocada para a esquerda.
/// A cauda aponta para baixo-esquerda, em direção ao centro da tela.
private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat
    var tailHeight: CGFloat
    var tailWidth: CGFloat
    var tailX: CGFloat

    func path(in rect: CGRect) -> Path {
        let bubbleBottom = rect.maxY - tailHeight
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: bubbleBottom - rect.minY)

        var path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .path(in: bubbleRect)

        path.move(to: CGPoint(x: tailX, y: bubbleBottom))
        path.addLine(to: CGPoint(x: tailX + tailWidth, y: bubbleBottom))
        path.addLine(to: CGPoint(x: tailX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
