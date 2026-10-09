import SwiftUI


struct FeatureOnboardingView: View {
    let onDismiss: () -> Void

    @State private var currentPage = 0

    private let pages: [FeaturePage] = [.actionButton, .siri]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index].view
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            footer
        }
        .appScreenBackground()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            // Dot indicator
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.appAccent : Color.appAccent.opacity(0.25))
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Profile hint (only on last page)
            if currentPage == pages.count - 1 {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.appAccentText)
                    Text("Acesse **Perfil** para ver isso novamente a qualquer momento.")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.appSecondary)
                }
                .padding(.horizontal, 32)
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Primary button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    onDismiss()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Próximo" : "Começar")
                    .font(AppFont.calloutStrong)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent)
            .animation(.easeInOut, value: currentPage)
        }
        .padding(.bottom, 36)
        .padding(.top, 12)
    }
}

// MARK: - Page definitions

private enum FeaturePage {
    case actionButton
    case siri

    var view: some View {
        Group {
            switch self {
            case .actionButton: ActionButtonPage()
            case .siri: SiriPage()
            }
        }
    }
}

// MARK: - Action Button page

private struct ActionButtonPage: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                pageHeader(
                    icon: "button.vertical.left.press.fill",
                    title: "Botão de Ação",
                    subtitle: "Registre água com um toque lateral, sem desbloquear o iPhone."
                )

                compatibilityBadge

                stepsCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
    }

    private var compatibilityBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Color.appAccentText)
            Text("iPhone 15 Pro, 16 e posteriores · iOS 18+")
                .font(AppFont.footnoteStrong)
                .foregroundStyle(Color.appAccentText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appAccent.opacity(0.1), in: Capsule())
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(number: 1, icon: "gearshape.fill",
                    title: "Abra o app Ajustes",
                    isLast: false)
            stepRow(number: 2, icon: "button.vertical.left.press.fill",
                    title: "Toque em \"Botão de Ação\"",
                    isLast: false)
            stepRow(number: 3, icon: "slider.horizontal.3",
                    title: "Selecione \"Controles\"",
                    isLast: false)
            stepRow(number: 4, icon: "plus.circle.fill",
                    title: "Adicione os controles do Hidrata",
                    isLast: true)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stepRow(number: Int, icon: String, title: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.appAccent).frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(AppFont.footnoteStrong)
                        .foregroundStyle(.white)
                }
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color.appAccentText)
                    Text(title)
                        .font(AppFont.subheadlineStrong)
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Divider().padding(.leading, 58)
            }
        }
    }
}

// MARK: - Siri page

private struct SiriPage: View {
    private let phrases: [(icon: String, text: String, result: String)] = [
        ("drop.fill",          "\"Bebi um gole de HidrataPOC\"",    "40 mL"),
        ("mug.fill","\"Bebi um copo de HidrataPOC\"",    "250 mL"),
        ("waterbottle.fill",   "\"Bebi uma garrafa de HidrataPOC\"","500 mL"),
        ("drop.fill",          "\"Bebi 3 goles de HidrataPOC\"",    "120 mL"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                pageHeader(
                    icon: "waveform.circle.fill",
                    title: "Siri",
                    subtitle: "Registre água sem tirar o celular do bolso — funciona com a tela bloqueada."
                )

                phrasesCard

                tipsRow
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
    }

    private var phrasesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Frases que funcionam")
                    .font(AppFont.subheadlineHeavy)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().padding(.horizontal, 16)

            ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: phrase.icon)
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Color.appAccentText)
                            .frame(width: 18)
                        Text(phrase.text)
                            .font(AppFont.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(phrase.result)
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.appAccentText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < phrases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    private var tipsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.appSuccess)
                .padding(.top, 1)
            Text("Funciona com a **tela bloqueada** e sem precisar de frases exatas — fale naturalmente.")
                .font(AppFont.footnote)
                .foregroundStyle(Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Shared header

private func pageHeader(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
        ZStack {
            Circle()
                .fill(Color.appAccent.opacity(0.12))
                .frame(width: 76, height: 76)
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.appAccentText)
        }

        Text(title)
            .font(AppFont.title)
            .foregroundStyle(.primary)

        Text(subtitle)
            .font(AppFont.subheadline)
            .foregroundStyle(Color.appSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
}

#Preview {
    FeatureOnboardingView(onDismiss: {})
}
