import SwiftData
import SwiftUI
import UIKit

/// Altura real da área segura do topo (status bar / notch / Dynamic Island) desta
/// cena — lida direto da janela-chave, já que o SwiftUI (antes do iOS 17) não expõe
/// isso como um `Environment` público. Usada pra empurrar o título do `TankHeader`
/// pra baixo da toolbar por uma distância que se adapta ao aparelho, em vez de um
/// número fixo que erraria em telas com/sem notch ou Dynamic Island.
private var currentTopSafeAreaInset: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?
        .windows
        .first { $0.isKeyWindow }?
        .safeAreaInsets.top ?? 47
}

/// Cabeçalho de marca para telas de ensino/configuração (tutoriais do Botão de Ação
/// e da Siri, conexão com o Saúde) — a mesma linguagem visual do tanque da Home
/// (onda, gradiente de água, o mascote) chegando às telas que hoje eram puramente
/// utilitárias. É pra ser a coisa que a pessoa lembra de ter visto no Gole, não só
/// mais uma tela de "como configurar".
struct TankHeader: View {
    let title: String
    let subtitle: String
    /// Fala do mascote no balão — `nil` esconde o balão e mostra só o mascote
    /// (usado nas sheets standalone; o onboarding de primeiro uso continua com a fala).
    var mascotLine: String? = nil
    var mascotName: String = "mascote2"

    var body: some View {
        // Texto e mascote na MESMA linha (não um overlay solto por cima): assim os
        // dois ficam alinhados ao centro um do outro de verdade, e o mascote nunca
        // escapa do padding do header — fica sempre dentro do gradiente, nunca
        // espiando por baixo da onda.
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppFont.displayHero)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if let mascotLine {
                    MascotSpeechBubble(text: mascotLine)
                }
                Image(mascotName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        // O header inteiro (fundo E texto) ignora a área segura pra o gradiente
        // sangrar até o topo real do sheet — então o texto precisa do próprio
        // respiro, calculado (status bar/notch + a altura fixa da toolbar em modo
        // inline, 44pt), pra não ficar embaixo do "X" nativo que mora na toolbar.
        .padding(.top, currentTopSafeAreaInset + 44 - 6)
        .padding(.bottom, 44)
        .background(LinearGradient.waterHeader)
        .clipShape(WaveShape())
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .combine)
    }
}

/// `TankHeader` com o mascote que reflete o progresso REAL do usuário hoje — o
/// mesmo bicho que aparece no tanque da Home — em vez de um mascote fixo. Consulta
/// perfil e registros direto (é um POC de perfil único, mesma suposição que
/// `NotificationScheduler` já faz), então funciona em qualquer sheet sem precisar
/// receber o perfil por parâmetro.
struct CurrentMascotTankHeader: View {
    let title: String
    let subtitle: String
    var mascotLine: String? = nil

    @Query private var profiles: [UserProfile]
    // Só o consumo de hoje interessa aqui (o mascote do cabeçalho), então o predicado
    // evita materializar a tabela toda a cada sheet aberta. O filtro em Swift abaixo
    // continua sendo o que decide o dia — ver o comentário equivalente em HomeView.
    @Query private var allLogs: [IntakeLog]

    init(title: String, subtitle: String, mascotLine: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.mascotLine = mascotLine
        let dayStart = Calendar.current.startOfDay(for: .now)
        _allLogs = Query(filter: #Predicate<IntakeLog> { $0.timestamp >= dayStart },
                         sort: \IntakeLog.timestamp)
    }

    private var mascotName: String {
        guard let profile = profiles.first, profile.metaDiariaML > 0 else { return "mascote5" }
        let todayLogs = allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
        let consumed = HydrationMath.totalML(todayLogs, on: .now)
        let progress = min(1, Double(consumed) / Double(profile.metaDiariaML))
        return AppTheme.mascotImageName(for: progress) ?? "mascote1"
    }

    var body: some View {
        TankHeader(title: title, subtitle: subtitle, mascotLine: mascotLine, mascotName: mascotName)
    }
}

/// Casca comum das sheets de marca forte: o `TankHeader` sangra até o topo do
/// sheet, por baixo da status bar/notch — a barra de navegação continua lá (com o
/// "X" nativo), só o fundo dela fica transparente, então o gradiente aparece por
/// trás sem nenhuma faixa separando os dois.
struct TankSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                content()
            }
            .ignoresSafeArea(edges: .top)
            .appScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // No claro, o "X" ficava na cor do tint herdado (escura — pensada
                    // pra texto sobre fundo claro), quase sumindo em cima do canto
                    // escuro do gradiente. Força branco só no claro; no escuro o tint
                    // herdado já é claro o suficiente, então fica como está.
                    if colorScheme == .light {
                        Button("Fechar", systemImage: "xmark") { dismiss() }
                            .foregroundStyle(.white)
                    } else {
                        Button("Fechar", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

/// Borda inferior ondulada — o mesmo motivo de "superfície da água" do tanque da
/// Home, só que estático (sem física), pra não competir com o conteúdo abaixo.
struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let waveHeight: CGFloat = 16

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height - waveHeight))
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: height),
            control1: CGPoint(x: width * 0.22, y: height - waveHeight * 2.1),
            control2: CGPoint(x: width * 0.28, y: height)
        )
        path.addCurve(
            to: CGPoint(x: width, y: height - waveHeight),
            control1: CGPoint(x: width * 0.72, y: height),
            control2: CGPoint(x: width * 0.78, y: height - waveHeight * 2.1)
        )
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }
}

/// Selo de gota — substitui o crachá numerado genérico nos passos dos tutoriais.
/// "Gole" é literalmente sobre gotas; um círculo colorido não dizia nada sobre o
/// produto, uma gota diz.
struct DropBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let number: Int

    var body: some View {
        ZStack {
            DropShape()
                .fill(LinearGradient.waterHeader)
                .frame(width: 26, height: 32)
            Text("\(number)")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .offset(y: 3)
        }
        .accessibilityHidden(true)
    }
}

private struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let bulbCenter = CGPoint(x: width / 2, y: height * 0.62)
        let bulbRadius = width / 2

        var path = Path()
        path.move(to: CGPoint(x: width / 2, y: 0))
        path.addCurve(
            to: CGPoint(x: width, y: bulbCenter.y),
            control1: CGPoint(x: width * 0.85, y: height * 0.18),
            control2: CGPoint(x: width, y: height * 0.42)
        )
        path.addArc(
            center: bulbCenter,
            radius: bulbRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addCurve(
            to: CGPoint(x: width / 2, y: 0),
            control1: CGPoint(x: 0, y: height * 0.42),
            control2: CGPoint(x: width * 0.15, y: height * 0.18)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    TankSheet {
        VStack(spacing: 20) {
            TankHeader(
                title: "Botão de Ação",
                subtitle: "Registre água com um toque lateral — sem desbloquear o iPhone.",
                mascotLine: nil
            )
            HStack(spacing: 12) {
                DropBadge(number: 1)
                DropBadge(number: 2)
                DropBadge(number: 3)
            }
        }
        .padding(.bottom, 40)
    }
}
