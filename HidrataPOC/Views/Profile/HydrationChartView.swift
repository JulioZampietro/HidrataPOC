import Charts
import SwiftUI

struct HydrationChartView: View {
    let dailyTotals: [(day: Date, totalML: Int)]
    let metaDiariaML: Int

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

            RuleMark(y: .value("Meta", metaDiariaML))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Gráfico de consumo diário de água nos últimos \(dailyTotals.count) dias, meta de \(metaDiariaML) mililitros")
    }
}

#Preview {
    let days = HydrationMath.dailyTotals([], days: 7)
        .map { (day: $0.day, totalML: Int.random(in: 800...2600)) }
    return HydrationChartView(dailyTotals: days, metaDiariaML: 2450)
        .padding()
}
