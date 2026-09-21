import Foundation

/// Tela onde uma interação de UI ocorreu — usado por `InteractionTracker` para
/// popular `UIInteractionEvent.screen`.
enum AppScreen: String {
    case home
    case profile
    case historico
}

/// Uma sheet rastreada por `SheetLifecycleTracking`. O raw value é o prefixo do
/// nome do evento — `logOpen`/`logClose` sufixam com `_open`/`_close`.
enum TrackedSheet: String {
    case customAmountEditor = "custom_amount_editor"
    case goalExplainer = "goal_explainer"
    case editGoal = "edit_goal"
    case actionButtonTutorial = "action_button_tutorial"
    case siriTutorial = "siri_tutorial"
    case editPersonalData = "edit_personal_data"
    case historicoDayDetail = "historico_day_detail"
}
