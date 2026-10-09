import Charts
import SwiftUI

struct HydrationChartView: View {
    /// `goalML` is that day's own goal (see `DailyGoalResolver`), so the goal line steps
    /// where the goal changed instead of re-drawing the past at today's value.
    let dailyTotals: [(day: Date, totalML: Int, goalML: Int)]

    private var todayGoalML: Int { dailyTotals.last?.goalML ?? 0 }

    var body: some View {
        Chart {
            ForEach(dailyTotals, id: \.day) { entry in
                BarMark(
                    x: .value("Dia", entry.day, unit: .day),
                    y: .value("Consumo", entry.totalML)
                )
                .foregroundStyle(.blue)
                .cornerRadius(4)
            }

            ForEach(dailyTotals, id: \.day) { entry in
                LineMark(
                    x: .value("Dia", entry.day, unit: .day),
                    y: .value("Meta", entry.goalML),
                    series: .value("Série", "Meta")
                )
                .interpolationMethod(.stepCenter)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Gráfico de consumo diário de água nos últimos \(dailyTotals.count) dias, meta de hoje de \(todayGoalML) mililitros")
    }
}

#Preview {
    let days = HydrationMath.dailyTotals([], days: 7)
        .map { (day: $0.day, totalML: Int.random(in: 800...2600), goalML: 2450) }
    return HydrationChartView(dailyTotals: days)
        .padding()
}
