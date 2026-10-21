import Photos
import SwiftUI
import UniformTypeIdentifiers


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

/// Cor das letras nos layouts transparentes: branca, preta ou uma escolhida pelo
/// usuário no seletor de cores. O cartão azul sempre usa branco.
enum ShareCardInk: Hashable {
    case branca, preta, personalizada
}

extension Color {
    /// Luminância relativa (0 = preto, 1 = branco), para decidir sombra e fundo da
    /// prévia. Os componentes sRGB são linearizados antes da soma ponderada (WCAG
    /// 2.x): sem isso o valor não é luminância, e cores saturadas caíam no lado
    /// errado do limiar.
    var luminance: Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        // Falha com cores fora de um espaço RGB; aí os componentes ficam em 0 (preto),
        // que é o lado seguro para a decisão de contraste que o chamador faz.
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil) else { return 0 }
        func linear(_ component: CGFloat) -> Double {
            let c = Double(component)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// O cartão em si, em tamanho fixo de Stories (9:16). Renderizado a 3x vira
/// 1080×1920.
struct ShareProgressCard: View {
    let snapshot: ShareProgressSnapshot
    let layout: ShareCardLayout
    var ink: Color = .white

    static let size = CGSize(width: 360, height: 640)

    private static let locale = Locale(identifier: "pt_BR")

    private var inkColor: Color { layout.isTransparent ? ink : .white }

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
            // fotos claras; nas escuras ficaria borrado.
            .shadow(color: layout.isTransparent && ink.luminance > 0.6 ? .black.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
            .frame(width: Self.size.width, height: Self.size.height)
            .background {
                if layout == .cartao {
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.68, blue: 1.0), Color.appAccent, Color(red: 0.05, green: 0.27, blue: 0.66)],
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
                    .font(AppFont.fixed(17, .semibold))
                    .opacity(0.85)
                amount(size: 72)
                Text(snapshot.progress >= 1 ? "Meta batida! 🎉" : "de \(goalText) mL · \(percentText)")
                    .font(AppFont.fixed(17, .bold))
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
            Text("GOLE")
                .font(AppFont.fixed(14, .heavy))
                .tracking(4)
                .opacity(0.9)
            VStack(spacing: 0) {
                Text("bebi hoje")
                    .font(AppFont.fixed(18, .semibold))
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
                        .font(AppFont.fixed(15, .semibold))
                        .opacity(0.85)
                    amount(size: 46)
                    Text(snapshot.progress >= 1 ? "Meta batida! 🎉" : "\(percentText) da meta")
                        .font(AppFont.fixed(15, .bold))
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
                Text("GOLE")
                    .tracking(3)
            }
            .font(AppFont.fixed(14, .heavy))

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
            Text("GOLE")
                .font(AppFont.fixed(15, .heavy))
                .tracking(4)
            Text(dateText)
                .font(AppFont.fixed(15, .semibold))
                .opacity(0.85)
        }
    }

    private func amount(size: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(consumedText)
                .font(AppFont.fixed(size, .heavy))
            Text("mL")
                .font(AppFont.fixed(size * 0.36, .bold))
        }
    }

    private var streak: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
            Text(streakText)
        }
        .font(AppFont.fixed(16, .bold))
    }

    private func stat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(AppFont.fixed(12, .bold))
                .tracking(1.5)
                .opacity(0.85)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(AppFont.fixed(40, .heavy))
                if let unit {
                    Text(unit)
                        .font(AppFont.fixed(16, .bold))
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
/// as letras brancas e claro para as azuis, para o texto continuar legível.
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

/// Apresenta o `UIColorPickerViewController` imperativamente via UIKit, a partir de
/// um `UIViewController`-âncora invisível embutido na própria hierarquia do
/// `ShareProgressView` — não como uma segunda `.sheet` do SwiftUI aninhada dentro da
/// sheet que já apresenta o `ShareProgressView`.
///
/// Duas sheets do SwiftUI empilhadas (a do compartilhar + a do seletor de cor) mais a
/// apresentação interna da "caneta" (eyedropper) do seletor — que o próprio UIKit
/// dispara por fora do SwiftUI — é uma combinação em que o SwiftUI perde a referência
/// de qual controller deveria apresentar o quê e crasha com "tried to present a nil
/// modal view controller": sobreviveu a três tentativas de corrigir o *timing* da
/// nossa atualização de cor porque a causa não era timing, era profundidade de
/// apresentação. Apresentando direto por fora da cadeia de sheets do SwiftUI, o
/// eyedropper passa a abrir numa profundidade convencional (a que a Apple testa) e
/// para de crashar.
private struct ColorPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var color: Color

    /// Fração aproximada da tela que o detent `.medium()` ocupa — só uma estimativa
    /// usada por `ShareProgressView.previewHeightWhilePicking` para encolher a prévia
    /// do cartão e caber acima do seletor; o detent em si é o `.medium()` nativo do
    /// sistema, não um valor calculado a partir desta fração.
    static let heightFraction: CGFloat = 0.5

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self

        if isPresented {
            guard context.coordinator.presentedPicker == nil else { return }
            guard let presenter = Self.topmostPresenter(from: uiViewController) else { return }
            let picker = UIColorPickerViewController()
            picker.supportsAlpha = false
            picker.selectedColor = UIColor(color)
            picker.title = "Cor das letras"
            picker.delegate = context.coordinator
            if let sheet = picker.sheetPresentationController {
                // `.medium()` em vez de um detent customizado por fração: é o caminho
                // que a Apple testa para os pickers internos do sistema. Sem
                // `largestUndimmedDetentIdentifier` de propósito — deixando o fundo
                // escurecido e NÃO interativo (o padrão do sistema), a "caneta" volta a
                // ter controle exclusivo da tela para capturar o toque; era a
                // combinação de fundo sem escurecer + interativo que fazia a lupa não
                // seguir o dedo e a cor não atualizar ao vivo durante o arrasto.
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
            }
            context.coordinator.presentedPicker = picker
            presenter.present(picker, animated: true)
        } else if let presented = context.coordinator.presentedPicker {
            presented.dismiss(animated: true)
            context.coordinator.presentedPicker = nil
        }
    }

    /// Sobe até o controller no topo da janela, em vez de apresentar a partir do
    /// âncora (que fica embutido dentro da própria hierarquia aninhada do SwiftUI,
    /// dentro da sheet do `ShareProgressView`). A "caneta" (eyedropper) usa o
    /// sistema de coordenadas de quem apresenta para calcular onde a lupa nasce e
    /// para onde ela se move conforme o dedo arrasta pela tela; apresentando de um
    /// controller aninhado, esse cálculo saía errado — a lupa nascia fora do dedo e
    /// só acompanhava o movimento relativo, nunca a posição absoluta, e a cor
    /// amostrada ficava presa num ponto errado da tela (por isso parecia não
    /// atualizar ao vivo).
    private static func topmostPresenter(from anchor: UIViewController) -> UIViewController? {
        guard var top = anchor.view.window?.rootViewController else { return anchor }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: ColorPickerPresenter
        var presentedPicker: UIColorPickerViewController?

        init(parent: ColorPickerPresenter) { self.parent = parent }

        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            // Seguro de novo: antes isso rodava junto de uma SEGUNDA `.sheet` do SwiftUI
            // aninhada, que era a causa real do crash (ver o comentário no topo deste
            // struct) — não a atualização contínua em si. Com a apresentação via UIKit
            // puro, dá pra atualizar ao vivo durante o arrasto sem risco.
            DispatchQueue.main.async { [parent] in
                parent.color = Color(uiColor: color)
            }
        }

        func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
            DispatchQueue.main.async { [parent] in
                parent.isPresented = false
            }
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
    @State private var customInk: Color = Color.appAccent
    @State private var isPickingColor = false
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    private var inkColor: Color {
        switch ink {
        case .branca: return .white
        case .preta: return .black
        case .personalizada: return customInk
        }
    }

    /// Cacheado em vez de recalculado a cada `body` (ver `scheduleRender`). O seletor
    /// de cor do sistema — e, com mais intensidade ainda, a "caneta" (eyedropper) dentro
    /// dele — chama o delegate com `continuously: true` a cada frame de arraste; sem o
    /// cache, esse `ImageRenderer` (um render de bitmap a 3x, caro) rodava de novo na
    /// main thread em cada um desses frames, disputando a tela com a própria captura
    /// contínua que o eyedropper do sistema faz pra desenhar a lupa — e crashava.
    @State private var renderedImage: UIImage?
    @State private var renderTask: Task<Void, Never>?

    private static func render(snapshot: ShareProgressSnapshot, layout: ShareCardLayout, ink: Color) -> UIImage? {
        let renderer = ImageRenderer(content: ShareProgressCard(snapshot: snapshot, layout: layout, ink: ink))
        renderer.scale = 3
        renderer.isOpaque = !layout.isTransparent
        return renderer.uiImage
    }

    /// Debounça o rerender: só refaz a imagem 150 ms depois da última mudança, em vez
    /// de a cada frame de arraste do seletor de cor.
    private func scheduleRender() {
        renderTask?.cancel()
        let layout = layout
        let ink = inkColor
        renderTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            renderedImage = Self.render(snapshot: snapshot, layout: layout, ink: ink)
        }
    }

    var body: some View {
        let image = renderedImage
        NavigationStack {
            GeometryReader { container in
            VStack(spacing: 16) {
                // Arrasta para o lado (ou toca nas bolinhas) para trocar o layout.
                TabView(selection: $layout) {
                    ForEach(ShareCardLayout.allCases) { option in
                        preview(option).tag(option)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Com o seletor de cores aberto (metade de baixo da tela), o cartão
                // encolhe para caber na metade de cima e continuar visível.
                .frame(height: isPickingColor ? previewHeightWhilePicking(container) : nil)
                .frame(maxHeight: .infinity, alignment: .top)

                pageDots

                inkPicker
                    .opacity(layout.isTransparent ? 1 : 0)
                    .disabled(!layout.isTransparent)
                    .animation(.easeInOut(duration: 0.2), value: layout.isTransparent)

                if let footnote = saveFootnote {
                    Text(footnote)
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    Button {
                        Haptic.primary.play()
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
                            preview: SharePreview("Meu dia no Gole", image: Image(uiImage: image))
                        ) {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .simultaneousGesture(TapGesture().onEnded { Haptic.primary.play() })
                    }
                }
                .controlSize(.large)
                .font(AppFont.calloutStrong)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: isPickingColor)
            } // GeometryReader
            .navigationTitle("Compartilhar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { Haptic.dismiss.play(); dismiss() }
                }
            }
            .task {
                guard renderedImage == nil else { return }
                renderedImage = Self.render(snapshot: snapshot, layout: layout, ink: inkColor)
            }
            .onChange(of: layout) { _, _ in
                Haptic.selection.play() // vale para arrastar, tocar nas bolinhas e pelo VoiceOver
                resetSaveState()
                scheduleRender()
            }
            .onChange(of: ink) { _, _ in
                Haptic.selection.play()
                resetSaveState()
                scheduleRender()
            }
            .onChange(of: customInk) { _, _ in
                ink = .personalizada
                resetSaveState()
                scheduleRender()
            }
            // Âncora invisível: ver o comentário em `ColorPickerPresenter` sobre por que
            // o seletor de cor não pode ser uma segunda `.sheet` aninhada aqui.
            .background(ColorPickerPresenter(isPresented: $isPickingColor, color: $customInk))
        }
    }

    /// Espaço entre o topo da área de conteúdo e o topo do seletor de cores.
    private func previewHeightWhilePicking(_ container: GeometryProxy) -> CGFloat {
        let screenHeight = container.frame(in: .global).maxY + container.safeAreaInsets.bottom
        let pickerTop = screenHeight * (1 - ColorPickerPresenter.heightFraction)
        return max(pickerTop - container.frame(in: .global).minY - 24, 120)
    }

    /// O cartão em escala reduzida; no estilo transparente aparece sobre um
    /// quadriculado (só na prévia, não vai na imagem) para indicar o fundo vazado.
    private func preview(_ layout: ShareCardLayout) -> some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / ShareProgressCard.size.width, geo.size.height / ShareProgressCard.size.height)
            ShareProgressCard(snapshot: snapshot, layout: layout, ink: inkColor)
                // Letras escuras pedem quadriculado claro, e vice-versa.
                .background { if layout.isTransparent { TransparencyCheckerboard(isLight: inkColor.luminance < 0.5) } }
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
        HStack(spacing: 0) {
            ForEach(ShareCardLayout.allCases) { option in
                Capsule()
                    .fill(option == layout ? Color.appAccent : Color.appControlOutline)
                    .frame(width: option == layout ? 22 : 8, height: 8)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut) { layout = option } }
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(option == layout ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: layout)
    }

    /// Cor das letras nos layouts transparentes: branca, preta ou uma cor livre (a
    /// bolinha colorida), que abre o seletor de cores do sistema.
    private var inkPicker: some View {
        HStack(spacing: 2) {
            inkSwatch(.branca, color: .white, label: "Letras brancas")
            inkSwatch(.preta, color: .black, label: "Letras pretas")

            // Mesmo visual da bolinha do `ColorPicker`: a cor atual dentro de um anel
            // de arco-íris.
            Circle()
                .fill(customInk)
                .frame(width: 18, height: 18)
                .padding(4)
                .overlay(
                    Circle().strokeBorder(
                        AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                        lineWidth: 3
                    )
                )
                .padding(3)
                .overlay(Circle().stroke(ink == .personalizada ? Color.appAccent : .clear, lineWidth: 2.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptic.tap.play()
                    ink = .personalizada
                    isPickingColor = true
                }
                .accessibilityLabel("Outra cor")
                .accessibilityAddTraits(ink == .personalizada ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func inkSwatch(_ option: ShareCardInk, color: Color, label: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.appControlOutline, lineWidth: 1))
            .padding(3)
            .overlay(Circle().stroke(option == ink ? Color.appAccent : .clear, lineWidth: 2.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { ink = option } }
            .accessibilityLabel(label)
            .accessibilityAddTraits(option == ink ? [.isButton, .isSelected] : .isButton)
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
            Haptic.success.play()
            saveState = .saved
        case .denied:
            Haptic.warning.play()
            saveState = .denied
        case .failed:
            Haptic.warning.play()
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
