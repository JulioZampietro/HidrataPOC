import SwiftUI
import WidgetKit

// MARK: - Control Center controls (Botão de Ação / iOS 18+)
//
// Each ControlWidget shows up in Settings → Action Button → Control Center and
// in the Control Center customisation screen. Tapping one fires LogIntakeIntent,
// which writes directly to the shared SwiftData store via the App Group — exactly
// the same path as the Live Activity quick-log buttons.

struct GlassControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.glass") {
            ControlWidgetButton(action: LogIntakeIntent(amountML: 250)) {
                Label("Copo", systemImage: "cup.and.saucer.fill")
            }
        }
        .displayName("Copo de Água")
        .description("Registra 250 mL sem abrir o app")
    }
}

struct BottleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.bottle") {
            ControlWidgetButton(action: LogIntakeIntent(amountML: 500)) {
                Label("Garrafa", systemImage: "waterbottle.fill")
            }
        }
        .displayName("Garrafa de Água")
        .description("Registra 500 mL sem abrir o app")
    }
}

struct GallonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hidratapoc.control.gallon") {
            ControlWidgetButton(action: LogIntakeIntent(amountML: 1000)) {
                Label("Galão", systemImage: "cylinder.fill")
            }
        }
        .displayName("Galão de Água")
        .description("Registra 1000 mL sem abrir o app")
    }
}
