import SwiftUI

/// Balão de fala do mascote — canto inferior esquerdo aponta para o mascote.
struct MascotSpeechBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text)
                .font(.custom("Nunito", size: 13).weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                )

            // Cauda do balão apontando para baixo-esquerda
            SpeechBubbleTail()
                .fill(.regularMaterial)
                .frame(width: 14, height: 10)
                .padding(.leading, 20)
        }
        .frame(maxWidth: 150, alignment: .trailing)
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
