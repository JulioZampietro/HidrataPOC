import SwiftData
import SwiftUI

struct DailyCheckinView: View {
    let userID: String
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var horasSono: Double = 7
    @State private var horarioAcordou: Date = {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }()
    var body: some View {
        NavigationStack {
            Form {
                Section("Sono") {
                    Stepper("Horas dormidas: \(horasSono.formatted(.number.precision(.fractionLength(1))))", value: $horasSono, in: 0...14, step: 0.5)
                    DatePicker("Horário que acordou", selection: $horarioAcordou, displayedComponents: .hourAndMinute)
                }

                Section {
                    Button("Salvar check-in") { save() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Check-in diário")
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        let checkin = DailyCheckin(
            userID: userID,
            dataReferencia: .now,
            horasSono: horasSono,
            horarioAcordou: horarioAcordou
        )
        modelContext.insert(checkin)
        try? modelContext.save()
        Task {
            await CloudKitSyncService.shared.push(checkin)
            try? modelContext.save()
        }
        onDone()
    }
}

#Preview {
    DailyCheckinView(userID: "preview-user", onDone: {})
        .modelContainer(for: DailyCheckin.self, inMemory: true)
}
