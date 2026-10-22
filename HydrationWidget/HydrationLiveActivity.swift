import ActivityKit
import HydrationKit
import SwiftUI
import WidgetKit

/// The activity only ever exists while `state.isOverdue` is true — `LiveActivityManager`
/// (app target) refuses to request one otherwise, and `IntakeLogService.endLiveActivity`
/// (both targets) ends it the moment an intake is logged rather than updating it to a
/// "not overdue" state. That means every view below can assume it's always in the
/// "reminder + quick-log buttons" state; there is no separate quiet/idle presentation
/// to render, so a Live Activity is never visible as a bare card with nothing to act on.
struct HydrationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HydrationAttributes.self) { context in
            HydrationLockScreenView(phrase: context.attributes.phrase, state: context.state)
                .background(LockScreenPalette.gradient)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Só os botões, sobre o mesmo gradiente e com o mesmo raio de canto do cartão.
                DynamicIslandExpandedRegion(.bottom) {
                    IntakeButtonRow(customAmountML: context.state.customAmountML)
                        .padding(LockScreenPalette.padding)
                        .background(LockScreenPalette.gradient, in: RoundedRectangle(cornerRadius: LockScreenPalette.cornerRadius, style: .continuous))
                }
            } compactLeading: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.appAccent)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.appAccent)
            }
            .contentMargins(.all, 0, for: .expanded)
        }
    }
}

private struct HydrationLockScreenView: View {
    let phrase: String
    let state: HydrationAttributes.ContentState

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Some com a meta batida (o mascote some da Home nesse ponto também).
                if let stage = AppTheme.mascotStage(for: state.progress) {
                    Image("mascote\(stage)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 54)
                }
                VStack(alignment: .leading, spacing: 3) {
                    // `phrase` já foi escolhida pra caber em uma linha (ver `LiveActivityManager`);
                    // o limite abaixo só cobre texto grande do Dynamic Type.
                    Text(phrase)
                        .font(AppFont.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Faz mais de uma hora que você não bebe.")
                        .font(AppFont.footnoteStrong)
                        .opacity(0.85)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)

            IntakeButtonRow(customAmountML: state.customAmountML)
        }
        .foregroundStyle(.white)
        .padding(LockScreenPalette.padding)
    }
}

/// `LockScreenAppearance` (not the environment's color scheme — see its doc comment) decides
/// between the app's light and dark `waterHeader` stops, which are the same values as
/// `LinearGradient.waterHeader`'s adaptive colors.
private enum LockScreenPalette {
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 26

    static var gradient: LinearGradient {
        let colors: [Color] = LockScreenAppearance.isDark
            ? [Color(red: 0.05, green: 0.15, blue: 0.34), Color(red: 0.12, green: 0.38, blue: 0.86), Color(red: 0.32, green: 0.56, blue: 0.90)]
            : [Color(red: 0.06, green: 0.22, blue: 0.55), Color(red: 0.08, green: 0.40, blue: 0.93), Color(red: 0.40, green: 0.70, blue: 0.99)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Botões mais escuros que o cartão.
    static var buttonFill: Color {
        LockScreenAppearance.isDark
            ? Color(red: 0.016, green: 0.055, blue: 0.157).opacity(0.6)
            : Color(red: 0.024, green: 0.094, blue: 0.275).opacity(0.5)
    }
}

private struct IntakeButtonRow: View {
    let customAmountML: Int

    var body: some View {
        HStack(spacing: 8) {
            IntakeButton(amountML: 250)
            IntakeButton(amountML: 500)
            IntakeButton(amountML: customAmountML)
        }
    }
}

private struct IntakeButton: View {
    let amountML: Int

    var body: some View {
        Button(intent: LogIntakeIntent(amountML: amountML)) {
            VStack(spacing: 2) {
                Text("\(amountML)")
                    .font(AppFont.title3)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("mL")
                    .font(AppFont.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(LockScreenPalette.buttonFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Registrar \(amountML) mililitros")
    }
}
