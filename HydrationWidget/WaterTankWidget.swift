import SwiftData
import SwiftUI
import WidgetKit

/// Small square widget: a miniature of the Home screen's water container — the
/// widget itself is the tank, filled to today's progress, with the current mascot
/// inside. Tapping it opens the app.
struct WaterTankWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSync.waterTankKind, provider: WaterTankProvider()) { entry in
            WaterTankWidgetView(entry: entry)
        }
        .configurationDisplayName("Tanque de água")
        .description("Seu nível de água de hoje e o bichinho atual.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct WaterTankEntry: TimelineEntry {
    let date: Date
    let consumedML: Int
    let goalML: Int

    var progress: Double {
        guard goalML > 0 else { return 0 }
        return min(1, Double(consumedML) / Double(goalML))
    }
}

struct WaterTankProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterTankEntry {
        WaterTankEntry(date: .now, consumedML: 900, goalML: 2000)
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterTankEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        // WidgetKit's completion isn't `Sendable`, but it's safe to call from any
        // thread; the hop is only for the main-actor SwiftData context.
        nonisolated(unsafe) let completion = completion
        Task { @MainActor in
            completion(Self.currentEntry(at: .now))
        }
    }

    /// Two entries: now, and an empty tank at midnight (the intake total resets with
    /// the day). The app reloads the timeline whenever an intake is logged or deleted.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterTankEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { @MainActor in
            let now = Date.now
            let current = Self.currentEntry(at: now)
            let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
            let nextDay = WaterTankEntry(date: midnight, consumedML: 0, goalML: current.goalML)
            completion(Timeline(entries: [current, nextDay], policy: .atEnd))
        }
    }

    @MainActor
    private static func currentEntry(at now: Date) -> WaterTankEntry {
        let context = PersistenceController.context
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else {
            return WaterTankEntry(date: now, consumedML: 0, goalML: 0)
        }
        let userID = profile.userID
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = #Predicate<IntakeLog> { $0.userID == userID && $0.timestamp >= startOfDay }
        let logs = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        let consumed = logs
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }
            .reduce(0) { $0 + $1.volumeML }
        let goal = WidgetSync.effectiveGoal(on: now) ?? profile.metaDiariaML
        return WaterTankEntry(date: now, consumedML: consumed, goalML: goal)
    }
}

/// Mesmo azul de marca do app (`Color.appAccent`): o widget tinha o próprio tom, que já tinha divergido.
private let accentBlue = Color.appAccent

struct WaterTankWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: WaterTankEntry

    var body: some View {
        GeometryReader { geo in
            let mascotHeight = geo.size.height * 0.62
            ZStack {
                if let mascot = AppTheme.mascotImageName(for: entry.progress) {
                    Image(mascot)
                        .resizable()
                        .scaledToFit()
                        .frame(height: mascotHeight)
                        // Same per-image correction as Home, so every stage shows at
                        // the same apparent size.
                        .frame(width: mascotHeight * 1.55, height: mascotHeight)
                        .scaleEffect(AppTheme.mascotSizeCorrection(for: mascot))
                } else {
                    // Meta batida: na Home o mascote também some.
                    // Branco sumia no tema claro (≈1,5:1 sobre a água a 100%); o azul de
                    // texto da paleta passa de 3:1 nos dois temas (ícone grande).
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.appAccentText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Over the mascot, like the app's water, which tints whatever is below its surface.
        .overlay { WaterLevelFill(level: entry.progress) }
        .containerBackground(for: .widget) {
            AppTheme.screenBackground(for: colorScheme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Água de hoje: \(entry.consumedML) de \(entry.goalML) mililitros")
    }
}

/// Static stand-in for the app's animated water (`water` in Bubble.metal): the
/// accent blue tinting what's below the surface — lighter right under it, stronger
/// at the bottom — with a bright line on the surface. Gentle wave, flat when full.
private struct WaterLevelFill: View {
    let level: Double

    var body: some View {
        let surface = WaterSurfaceShape(level: level, waveHeight: level < 1 ? 2 : 0)
        ZStack {
            surface.fill(
                LinearGradient(
                    colors: [accentBlue.opacity(0.14), accentBlue.opacity(0.32)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            if level < 1 {
                WaterSurfaceShape(level: level, waveHeight: 2, surfaceOnly: true)
                    .stroke(.white.opacity(0.8), lineWidth: 1.5)
            }
        }
    }
}

private struct WaterSurfaceShape: Shape {
    let level: Double
    let waveHeight: CGFloat
    /// Just the surface line (for the highlight stroke), not the filled body.
    var surfaceOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        let surfaceY = rect.maxY - rect.height * level
        if surfaceOnly {
            path.move(to: CGPoint(x: rect.minX, y: surfaceY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: surfaceY))
        }
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: surfaceY),
            control1: CGPoint(x: rect.minX + rect.width * 0.35, y: surfaceY - waveHeight * 2),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: surfaceY + waveHeight * 2)
        )
        if surfaceOnly { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview(as: .systemSmall) {
    WaterTankWidget()
} timeline: {
    WaterTankEntry(date: .now, consumedML: 250, goalML: 2851)
    WaterTankEntry(date: .now, consumedML: 1400, goalML: 2851)
    WaterTankEntry(date: .now, consumedML: 2600, goalML: 2851)
    WaterTankEntry(date: .now, consumedML: 2851, goalML: 2851)
}
