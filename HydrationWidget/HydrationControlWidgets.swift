import SwiftUI
import WidgetKit

// MARK: - Control Center controls (Botão de Ação / iOS 18+)
//
// Each ControlWidget shows up in Settings → Action Button → Control Center and
// in the Control Center customisation screen. Tapping one fires
// LogIntakeControlIntent, which writes directly to the shared SwiftData store via
// the App Group — the same path as the Live Activity quick-log buttons, just
// tagged with a different `source` ("actionButton" vs "liveActivity") so the two
// surfaces are distinguishable in the dataset.

@ViewBuilder
private func actionLabel(isActive: Bool, icon: String, name: String) -> some View {
    if isActive {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.multicolor)
    } else {
        Label(name, systemImage: icon)
            .labelStyle(.iconOnly)
    }
}

struct GlassControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.glass") {
            ControlWidgetButton(action: LogIntakeControlIntent(amountML: 250)) {
                Label("Copo", systemImage: "cup.and.saucer.fill")
                    .labelStyle(.iconOnly)
            } actionLabel: { isActive in
                actionLabel(isActive: isActive, icon: "cup.and.saucer.fill", name: "Copo")
            }
        }
        .displayName("Copo de Água")
        .description("Registra 250 mL sem abrir o app")
    }
}

struct BottleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.bottle") {
            ControlWidgetButton(action: LogIntakeControlIntent(amountML: 500)) {
                Label("Garrafa", systemImage: "waterbottle.fill")
                    .labelStyle(.iconOnly)
            } actionLabel: { isActive in
                actionLabel(isActive: isActive, icon: "waterbottle.fill", name: "Garrafa")
            }
        }
        .displayName("Garrafa de Água")
        .description("Registra 500 mL sem abrir o app")
    }
}

struct GoleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.gole") {
            ControlWidgetButton(action: LogIntakeControlIntent(amountML: 40)) {
                Label("Gole", systemImage: "drop.fill")
                    .labelStyle(.iconOnly)
            } actionLabel: { isActive in
                actionLabel(isActive: isActive, icon: "drop.fill", name: "Gole")
            }
        }
        .displayName("Gole de Água")
        .description("Registra 40 mL sem abrir o app")
    }
}

struct CustomControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.custom") {
            ControlWidgetButton(action: LogCustomControlIntent()) {
                Label("Personalizado", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            } actionLabel: { isActive in
                actionLabel(isActive: isActive, icon: "slider.horizontal.3", name: "Personalizado")
            }
        }
        .displayName("Quantidade Personalizada")
        .description("Registra sua quantidade personalizada de água sem abrir o app")
    }
}
