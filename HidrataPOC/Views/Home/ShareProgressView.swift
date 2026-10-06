import Photos
import SwiftUI
import UniformTypeIdentifiers

private let accentBlue = Color(red: 0.1098, green: 0.4627, blue: 0.9922)

/// O que vai no cartão de compartilhamento — tirado de Home/Histórico no momento
/// em que o botão é tocado.
struct ShareProgressSnapshot {
    let consumedML: Int
    let goalML: Int
    let streakDias: Int
    var date: Date = .now

    var progress: Double {
        guard goalML > 0 else { return 0 }
        return min(1, Double(consumedML) / Double(goalML))
    }
}

/// Layout do cartão. O primeiro tem fundo azul pronto para postar; os outros são
/// "adesivos" de fundo transparente para colar por cima de uma foto nos Stories,
/// como no Strava.
enum ShareCardLayout: String, CaseIterable, Identifiable {
    case cartao, completo, minimalista, anel, estatisticas

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cartao: return "Cartão azul"
        case .completo: return "Transparente completo"
        case .minimalista: return "Transparente minimalista"
        case .anel: return "Transparente com anel de progresso"
        case .estatisticas: return "Transparente com estatísticas"
        }
    }

    var isTransparent: Bool { self != .cartao }
}

/// Cor das letras nos layouts transparentes: brancas para fotos escuras, pretas para
/// fotos claras. O cartão azul sempre usa branco.
enum ShareCardInk: String, CaseIterable, Identifiable {
    case branca, preta

    var id: String { rawValue }

    var color: Color { self == .preta ? .black : .white }
}

/// O cartão em si, em tamanho fixo de Stories (9:16). Renderizado a 3x vira
/// 1080×1920.
struct ShareProgressCard: View {
    let snapshot: ShareProgressSnapshot
    let layout: ShareCardLayout
    var ink: ShareCardInk = .branca

    static let size = CGSize(width: 360, height: 640)

    private static let locale = Locale(identifier: "pt_BR")

    private var inkColor: Color { layout.isTransparent ? ink.color : .white }

    private var dateText: String {
        snapshot.date.formatted(.dateTime.day().month(.wide).locale(Self.locale))
    }

    private var percentText: String {
        "\(Int((snapshot.progress * 100).rounded()))%"
    }

    private var consumedText: String { snapshot.consumedML.formatted(.number.locale(Self.locale)) }
    private var goalText: String { snapshot.goalML.formatted(.number.locale(Self.locale)) }

    private var streakText: String {
        snapshot.streakDias == 1 ? "1 dia seguido" : "\(snapshot.streakDias) dias seguidos"
    }

    private var mascotName: String {
        // Na meta batida o mascote some do app, mas no cartão ele comemora.
        AppTheme.mascotImageName(for: snapshot.progress) ?? "mascote1"
    }

    var body: some View {
        content
            .foregroundStyle(inkColor)
            // Sombra só nas letras brancas sobre fundo transparente, para destacar sobre
            // fotos claras; nas pretas ficaria borrado.
            .shadow(color: layout.isTransparent && ink == .branca ? .black.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
            .frame(width: Self.size.width, height: Self.size.height)
            .background {
                if layout == .cartao {
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.68, blue: 1.0), accentBlue, Color(red: 0.05, green: 0.27, blue: 0.66)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .cartao, .completo: completoLayout
        case .minimalista: minimalistaLayout
        case .anel: anelLayout
        case .estatisticas: estatisticasLayout
        }
    }

    // MARK: - Layouts

    private var completoLayout: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 48)

            Spacer(minLength: 0)

            Image(mascotName)
                .resizable()
                .scaledToFit()
                .frame(height: 170)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("bebi hoje")
                    .font(.custom("Nunito", size: 17).weight(.semibold))
                    .opacity(0.85)
                amount(size: 72)
                Text(snapshot.progress >= 1 ? "Meta batida! 🎉" : "de \(goalText) mL · \(percentText)")
                    .font(.custom("Nunito", size: 17).weight(.bold))
            }

            progressBar
                .padding(.top, 20)
                .padding(.horizontal, 40)

            streak
                .padding(.top, 28)
                .padding(.bottom, 56)
        }
    }

    /// Só o essencial: nome do app, "bebi hoje", a quantidade e a sequência.
    private var minimalistaLayout: some View {
        VStack(spacing: 10) {
            Text("HIDRATA")
                .font(.custom("Nunito", size: 14).weight(.heavy))
                .tracking(4)
                .opacity(0.9)
            VStack(spacing: 0) {
                Text("bebi hoje")
                    .font(.custom("Nunito", size: 18).weight(.semibold))
                    .opacity(0.85)
                amount(size: 64)
            }
            streak
        }
    }

    private var anelLayout: some View {
        VStack(spacing: 24) {
            header

            ZStack {
                Circle()
                    .stroke(inkColor.opacity(0.25), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(snapshot.progress, 0.01))
                    .stroke(inkColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("bebi hoje")
                        .font(.custom("Nunito", size: 15).weight(.semibold))
                        .opacity(0.85)
                    amount(size: 46)
                    Text(snapshot.progress >= 1 ? "Meta batida! 🎉" : "\(percentText) da meta")
                        .font(.custom("Nunito", size: 15).weight(.bold))
                }
            }
            .frame(width: 230, height: 230)

            streak
        }
    }

    /// Estilo "resumo de treino" do Strava: rótulos pequenos e números grandes,
    /// alinhados à esquerda na parte de baixo da foto.
    private var estatisticasLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                Text("HIDRATA")
                    .tracking(3)
            }
            .font(.custom("Nunito", size: 14).weight(.heavy))

            stat(label: "Bebi hoje", value: consumedText, unit: "mL")
            HStack(alignment: .top, spacing: 32) {
                stat(label: "Meta", value: percentText, unit: nil)
                stat(label: "Sequência", value: "\(snapshot.streakDias)", unit: snapshot.streakDias == 1 ? "dia" : "dias")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.bottom, 64)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text("HIDRATA")
                .font(.custom("Nunito", size: 15).weight(.heavy))
                .tracking(4)
            Text(dateText)
                .font(.custom("Nunito", size: 15).weight(.semibold))
                .opacity(0.85)
        }
    }

    private func amount(size: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(consumedText)
                .font(.custom("Nunito", size: size).weight(.heavy))
            Text("mL")
                .font(.custom("Nunito", size: size * 0.36).weight(.bold))
        }
    }

    private var streak: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
            Text(streakText)
        }
        .font(.custom("Nunito", size: 16).weight(.bold))
    }

    private func stat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.custom("Nunito", size: 12).weight(.bold))
                .tracking(1.5)
                .opacity(0.85)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.custom("Nunito", size: 40).weight(.heavy))
                if let unit {
                    Text(unit)
                        .font(.custom("Nunito", size: 16).weight(.bold))
                }
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(inkColor.opacity(0.25))
                Capsule().fill(inkColor)
                    .frame(width: max(geo.size.width * snapshot.progress, 12))
            }
        }
        .frame(height: 12)
    }
}

/// Quadriculado clássico de "fundo transparente" dos editores de imagem. Escuro para
/// as letras brancas e claro para as pretas, para o texto continuar legível.
private struct TransparencyCheckerboard: View {
    var isLight = false
    var squareSize: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: isLight ? 1 : 0.32)))
            let columns = Int((size.width / squareSize).rounded(.up))
            let rows = Int((size.height / squareSize).rounded(.up))
            var squares = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    squares.addRect(CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize))
                }
            }
            context.fill(squares, with: .color(Color(white: isLight ? 0.84 : 0.44)))
        }
    }
}

/// PNG pronto para o `ShareLink` — mantém a transparência do estilo "adesivo".
private struct SharePNG: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }
}

/// Sheet aberta pelo botão de compartilhar: pré-visualiza o cartão e oferece salvar
/// em Fotos ou mandar para as redes pelo menu de compartilhamento do sistema.
struct ShareProgressView: View {
    let snapshot: ShareProgressSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var layout: ShareCardLayout = .cartao
    @State private var ink: ShareCardInk = .branca
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    private var renderedImage: UIImage? {
        let renderer = ImageRenderer(content: ShareProgressCard(snapshot: snapshot, layout: layout, ink: ink))
        renderer.scale = 3
        renderer.isOpaque = !layout.isTransparent
        return renderer.uiImage
    }

    var body: some View {
        let image = renderedImage
        NavigationStack {
            VStack(spacing: 16) {
                // Arrasta para o lado (ou toca nas bolinhas) para trocar o layout.
                TabView(selection: $layout) {
                    ForEach(ShareCardLayout.allCases) { option in
                        preview(option).tag(option)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                pageDots

                inkPicker
                    .opacity(layout.isTransparent ? 1 : 0)
                    .disabled(!layout.isTransparent)
                    .animation(.easeInOut(duration: 0.2), value: layout.isTransparent)

                if let footnote = saveFootnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await save(image) }
                    } label: {
                        Label(saveState == .saved ? "Salva" : "Salvar", systemImage: saveState == .saved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(image == nil || saveState == .saving)

                    if let image, let data = image.pngData() {
                        ShareLink(
                            item: SharePNG(data: data),
                            preview: SharePreview("Meu dia no Hidrata", image: Image(uiImage: image))
                        ) {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .navigationTitle("Compartilhar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .onChange(of: layout) { _, _ in resetSaveState() }
            .onChange(of: ink) { _, _ in resetSaveState() }
        }
    }

    /// O cartão em escala reduzida; no estilo transparente aparece sobre um
    /// quadriculado (só na prévia, não vai na imagem) para indicar o fundo vazado.
    private func preview(_ layout: ShareCardLayout) -> some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / ShareProgressCard.size.width, geo.size.height / ShareProgressCard.size.height)
            ShareProgressCard(snapshot: snapshot, layout: layout, ink: ink)
                .background { if layout.isTransparent { TransparencyCheckerboard(isLight: ink == .preta) } }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
        .accessibilityLabel(layout.label)
    }

    /// Indicador de página: uma bolinha por layout, a atual alongada e em azul.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(ShareCardLayout.allCases) { option in
                Capsule()
                    .fill(option == layout ? accentBlue : Color.secondary.opacity(0.3))
                    .frame(width: option == layout ? 22 : 8, height: 8)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { withAnimation(.easeInOut) { layout = option } }
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(option == layout ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: layout)
    }

    /// Cor das letras nos layouts transparentes: duas bolinhas, branca e preta.
    private var inkPicker: some View {
        HStack(spacing: 14) {
            ForEach(ShareCardInk.allCases) { option in
                Circle()
                    .fill(option.color)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .padding(3)
                    .overlay(Circle().stroke(option == ink ? accentBlue : .clear, lineWidth: 2.5))
                    .contentShape(Circle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { ink = option } }
                    .accessibilityLabel(option == .branca ? "Letras brancas" : "Letras pretas")
                    .accessibilityAddTraits(option == ink ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func resetSaveState() {
        if saveState != .saving { saveState = .idle }
    }

    private var saveFootnote: String? {
        switch saveState {
        case .denied: return "Sem acesso às Fotos. Libere o acesso nos Ajustes do iPhone."
        case .failed: return "Não deu para salvar a imagem. Tente de novo."
        default: return nil
        }
    }

    private func save(_ image: UIImage?) async {
        guard let data = image?.pngData() else { return }
        saveState = .saving

        switch await Self.saveToPhotos(data) {
        case .saved:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            saveState = .saved
        case .denied:
            saveState = .denied
        case .failed:
            saveState = .failed
        }
    }

    private enum SaveResult: Sendable {
        case saved, denied, failed
    }

    /// Fora do MainActor de propósito: o Photos chama o bloco de `performChanges` (e
    /// o retorno da autorização) numa fila em segundo plano. Se esse código herdasse o
    /// isolamento da View, o Swift 6 derrubaria o app ao detectar a fila errada.
    private nonisolated static func saveToPhotos(_ data: Data) async -> SaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }

        do {
            // Salva o PNG original para não perder a transparência do estilo "adesivo".
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

#Preview {
    ShareProgressView(snapshot: ShareProgressSnapshot(consumedML: 1850, goalML: 2450, streakDias: 12))
}
