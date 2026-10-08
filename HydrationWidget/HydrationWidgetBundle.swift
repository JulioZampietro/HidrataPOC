import SwiftUI
import WidgetKit

@main
struct HydrationWidgetBundle: WidgetBundle {
    var body: some Widget {
        WaterTankWidget()
        HydrationLiveActivity()
        GlassControl()
        BottleControl()
        GoleControl()
        CustomControl()
    }
}
