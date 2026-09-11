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
            HydrationLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        OverdueMessage()
                        HStack(spacing: 12) {
                            IntakeButton(amountML: 250, label: "+250 mL")
                            IntakeButton(amountML: 500, label: "+500 mL")
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct HydrationLockScreenView: View {
    let state: HydrationAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverdueMessage()
            HStack(spacing: 8) {
                IntakeButton(amountML: 250, label: "+250 mL")
                IntakeButton(amountML: 500, label: "+500 mL")
                IntakeButton(amountML: state.customAmountML, label: "+\(state.customAmountML) mL")
            }
        }
        .padding(16)
    }
}

private struct OverdueMessage: View {
    /// Live Activity text doesn't reliably track `.primary`/`.secondary` against
    /// `activityBackgroundTint` the way it does in the main app, so the color is
    /// resolved explicitly from `colorScheme` instead of relying on the semantic
    /// default — otherwise this reads fine in dark mode but goes low-contrast (near
    /// white-on-light) once the system is in light mode.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .foregroundStyle(.blue)
            Text("Faz uma hora que você não bebe água!")
                .font(.subheadline.bold())
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        }
    }
}

private struct IntakeButton: View {
    let amountML: Int
    let label: String

    var body: some View {
        Button(intent: LogIntakeIntent(amountML: amountML)) {
            Text(label)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }
}
