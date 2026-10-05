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

/// Estilo do cartão, no estilo do Strava: um cartão com fundo pronto para postar, ou
/// um "adesivo" transparente para colar por cima de uma foto nos Stories.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case cartao, transparente

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cartao: return "Cartão"
        case .transparente: return "Transparente"
        }
    }
}

/// O cartão em si, em tamanho fixo de Stories (9:16). Renderizado a 3x vira
/// 1080×1920.
struct ShareProgressCard: View {
    let snapshot: ShareProgressSnapshot
    let style: ShareCardStyle

    static let size = CGSize(width: 360, height: 640)

    private var dateText: String {
        snapshot.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pt_BR")))
    }

    private var percentText: String {
        "\(Int((snapshot.progress * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("HIDRATA")
                    .font(.custom("Nunito", size: 15).weight(.heavy))
                    .tracking(4)
                Text(dateText)
                    .font(.custom("Nunito", size: 15).weight(.semibold))
                    .opacity(0.85)
            }
            .padding(.top, 48)

            Spacer(minLength: 0)

            // Na meta batida o mascote some do app, mas no cartão ele comemora.
            Image(AppTheme.mascotImageName(for: snapshot.progress) ?? "mascote1")
                .resizable()
                .scaledToFit()
                .frame(height: 170)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("bebi hoje")
                    .font(.custom("Nunito", size: 17).weight(.semibold))
                    .opacity(0.85)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(snapshot.consumedML.formatted(.number.locale(Locale(identifier: "pt_BR"))))
                        .font(.custom("Nunito", size: 72).weight(.heavy))
                    Text("mL")
                        .font(.custom("Nunito", size: 26).weight(.bold))
                }
                Text(snapshot.progress >= 1 ? "Meta batida! 🎉" : "de \(snapshot.goalML.formatted(.number.locale(Locale(identifier: "pt_BR")))) mL · \(percentText)")
                    .font(.custom("Nunito", size: 17).weight(.bold))
            }

            progressBar
                .padding(.top, 20)
                .padding(.horizontal, 40)

            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                Text(snapshot.streakDias == 1 ? "1 dia seguido" : "\(snapshot.streakDias) dias seguidos")
            }
            .font(.custom("Nunito", size: 16).weight(.bold))
            .padding(.top, 28)
            .padding(.bottom, 56)
        }
        .foregroundStyle(.white)
        .shadow(color: style == .transparente ? .black.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if style == .cartao {
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.68, blue: 1.0), accentBlue, Color(red: 0.05, green: 0.27, blue: 0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white)
                    .frame(width: max(geo.size.width * snapshot.progress, 12))
            }
        }
        .frame(height: 12)
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
    @State private var style: ShareCardStyle = .cartao
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    private var renderedImage: UIImage? {
        let renderer = ImageRenderer(content: ShareProgressCard(snapshot: snapshot, style: style))
        renderer.scale = 3
        renderer.isOpaque = style == .cartao
        return renderer.uiImage
    }

    var body: some View {
        let image = renderedImage
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Estilo", selection: $style) {
                    ForEach(ShareCardStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                preview
                    .frame(maxHeight: .infinity)

                if let footnote = saveFootnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 12) {
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
            .onChange(of: style) { _, _ in
                if saveState != .saving { saveState = .idle }
            }
        }
    }

    /// O cartão em escala reduzida; no estilo transparente aparece sobre um fundo
    /// escuro para dar para ver o texto branco.
    private var preview: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / ShareProgressCard.size.width, geo.size.height / ShareProgressCard.size.height)
            ShareProgressCard(snapshot: snapshot, style: style)
                .background(style == .transparente ? Color(white: 0.18) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
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

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveState = .denied
            return
        }

        do {
            // Salva o PNG original para não perder a transparência do estilo "adesivo".
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }
}

#Preview {
    ShareProgressView(snapshot: ShareProgressSnapshot(consumedML: 1850, goalML: 2450, streakDias: 12))
}
