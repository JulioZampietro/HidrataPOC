import SwiftUI

/// Registra abertura/fechamento de uma sheet via `onAppear`/`onDisappear` do seu
/// próprio conteúdo — cobre tanto o botão "Fechar" quanto o swipe-down, sem
/// precisar instrumentar cada botão de fechar manualmente.
private struct SheetLifecycleTrackingModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let sheet: TrackedSheet
    let screen: AppScreen
    let userID: String
    let metadata: [String: String]?

    func body(content: Content) -> some View {
        content
            .onAppear {
                InteractionTracker.logOpen(sheet, screen: screen, userID: userID, metadata: metadata, context: modelContext)
            }
            .onDisappear {
                InteractionTracker.logClose(sheet, screen: screen, userID: userID, metadata: metadata, context: modelContext)
            }
    }
}

extension View {
    func trackSheetLifecycle(_ sheet: TrackedSheet, screen: AppScreen, userID: String, metadata: [String: String]? = nil) -> some View {
        modifier(SheetLifecycleTrackingModifier(sheet: sheet, screen: screen, userID: userID, metadata: metadata))
    }
}
