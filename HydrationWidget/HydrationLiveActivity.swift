import ActivityKit
import HydrationKit
import SwiftUI
import WidgetKit

/// Quiet by default; surfaces a reminder — 💧 icon, message, and quick-log buttons —
/// only once an hour has passed since the last logged intake. No countdown/progress
/// view is shown anywhere: `isOverdue` is computed from `Date.now` each time the
/// system redraws this Live Activity, rather than advanced by a native timer glyph
/// (see `LiveActivityManager.touchIfNeeded` for how redraws get nudged while the
/// phone is locked, since removing the timer means nothing else wakes this up).
struct HydrationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HydrationAttributes.self) { context in
            HydrationLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            let overdue = context.state.isOverdue

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if overdue {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if overdue {
                        VStack(spacing: 8) {
                            OverdueMessage()
                            HStack(spacing: 12) {
                                IntakeButton(amountML: 250, label: "+250 mL")
                                IntakeButton(amountML: 500, label: "+500 mL")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                if overdue {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                }
            } compactTrailing: {
                EmptyView()
            } minimal: {
                if overdue {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

/// FR-4/D-4 (revised): the three quick-log buttons — two fixed, one from
/// `state.customAmountML` — only appear once overdue, and disappear again as soon as
/// one is tapped, since logging resets `lastIntakeDate` and `isOverdue` goes back to
/// false (no separate "already used" flag needed — same derive-don't-store
/// philosophy as the rest of `ContentState`).
private struct HydrationLockScreenView: View {
    let state: HydrationAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.isOverdue {
                OverdueMessage()
                HStack(spacing: 8) {
                    IntakeButton(amountML: 250, label: "+250 mL")
                    IntakeButton(amountML: 500, label: "+500 mL")
                    IntakeButton(amountML: state.customAmountML, label: "+\(state.customAmountML) mL")
                }
            } else {
                Text("Hidratação")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

private struct OverdueMessage: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .foregroundStyle(.blue)
            Text("Faz uma hora que você não bebe água!")
                .font(.subheadline.bold())
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
        .buttonStyle(.bordered)
        .tint(.blue)
    }
}

extension HydrationAttributes.ContentState {
    var isOverdue: Bool {
        Date.now.timeIntervalSince(lastIntakeDate) >= reminderThreshold
    }
}
