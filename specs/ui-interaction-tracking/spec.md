# HYDRATE-IX-01 — Rastreamento de Interações de UI (Cliques)

## 1. Contexto

O HidrataPOC já roda um pipeline de dados de pesquisa: cada `@Model` do SwiftData
(`UserProfile`, `DailyCheckin`, `IntakeLog`, `NotificationEvent`) é empurrado para o
banco **público** do CloudKit via `CloudKitSyncService.push(_:)`, com `syncStatus`
(`pending`/`synced`/`failed`) e retry em `flushPending(context:)` a cada
`scenePhase == .active`.

Esse mesmo pipeline já resolve boa parte do que foi pedido, sem código novo:

- **Os 4 botões de log de água** (Gole, Copo, Garrafa, Personalizado): já vêm como
  `IntakeLog.tipoEntrada` + `IntakeLog.source == "app"`, gravados em
  `HomeView.logIntake(_:)` → `NotificationScheduler.recordManualIntake` →
  `IntakeLogService.record(source: "app", ...)`.
- **Botão de Ação**: `HydrationWidget/LogIntakeControlIntent.swift` já grava
  `IntakeLog.source == "actionButton"` com o volume exato.
- **Siri**: `HidrataPOC/Intents/SiriIntents.swift` (`LogGoleIntent`, `LogGlassIntent`,
  `LogBottleIntent`) já grava `IntakeLog.source == "siri"`, com `tipoEntrada` e
  `volumeML` corretos por preset. Não dá pra capturar a frase falada (a API do
  AppIntents não expõe isso), só o intent/parâmetro resolvido — que é o dado que
  importa.

**O que falta** é tudo que não é "logar água": abrir/fechar sheets de tutorial,
navegar no calendário do histórico, editar meta, editar volume personalizado, e
botões que hoje não fazem nada (ex.: o "?" da Home e do Histórico) mas cujo toque em
si já é sinal.

## 2. Não-objetivos

- Não trocar ou complementar isso com uma ferramenta de analytics de terceiro
  (TelemetryDeck/PostHog/Firebase). O pipeline CloudKit já existe e já é privado por
  design (`_icloud`: create-only, sem read).
- Não instrumentar *todo* toque do app indiscriminadamente — só a lista abaixo, mas
  com uma API genérica reaproveitável para o que vier depois.
- Não mexer no schema de `IntakeLog`/`NotificationEvent` — eles já capturam o que
  precisam.
- Não construir a UI da sheet "Conectar ao Saúde" (ver seção 6, pendência aberta).

## 3. Modelo de dados novo

Um único `@Model` genérico, no mesmo molde de `NotificationEvent`/`IntakeLog`:

```swift
// HidrataPOC/Models/UIInteractionEvent.swift
import Foundation
import SwiftData

/// Um registro por interação de UI que não é log de água (essas já vivem em
/// `IntakeLog.source`/`tipoEntrada`) — abertura/fechamento de sheets, navegação no
/// calendário do histórico, toques em botões sem ação. Mesmo padrão de sync que
/// `NotificationEvent`/`IntakeLog`: local-first, push best-effort pro CloudKit
/// público, retry em `CloudKitSyncService.flushPending`.
@Model
final class UIInteractionEvent {
    @Attribute(.unique) var id: UUID
    var userID: String
    var timestamp: Date

    /// Raw value de `TrackedEvent` — ex. "goal_explainer_open", "historico_day_tap".
    var eventName: String

    /// Raw value de `AppScreen` — em qual tela a interação aconteceu.
    var screen: String

    /// Contexto extra pequeno, serializado como JSON (`{"date":"2026-09-14",...}`).
    /// String em vez de dicionário porque SwiftData/CKRecord não guardam dict
    /// arbitrário direto — mesma razão de `IntakeLog` guardar campos achatados.
    var metadataJSON: String?

    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var ckSystemFields: Data?

    init(userID: String, eventName: String, screen: String, metadataJSON: String? = nil) {
        self.id = UUID()
        self.userID = userID
        self.timestamp = .now
        self.eventName = eventName
        self.screen = screen
        self.metadataJSON = metadataJSON
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }
}
```

## 4. Decisões de design

- **D-1 — Reaproveitar o pipeline CloudKit existente.** Sem SDK novo, sem
  entitlement novo. `UIInteractionEvent` entra no `Schema` do
  `PersistenceController`, ganha um `push(_:)` em `CloudKitSyncService` idêntico ao
  de `NotificationEvent`, e entra no laço de `flushPending`.
- **D-2 — Abrir/fechar sheet via `onAppear`/`onDisappear`, não via botão "Fechar".**
  Toda sheet aqui pode ser fechada por swipe-down, não só pelo botão. Um
  `ViewModifier` aplicado no conteúdo da sheet cobre os dois casos com uma linha por
  sheet, em vez de instrumentar cada botão de fechar manualmente (e ainda perder o
  swipe).
- **D-3 — Toques pontuais (não-sheet) são registrados no call site.** Navegação de
  mês, toggle de página, tap no dia do calendário: chamada direta de
  `InteractionTracker.log(...)` dentro da função/closure que já existe — não precisa
  de wrapper.
- **D-4 — "Salvar" é um evento à parte de "fechar".** Fechar a sheet de meta não diz
  se o usuário mudou algo. `editGoalSave`/`editPersonalDataSave`/
  `customAmountEditorSave` são disparados dentro das funções que já existem
  (`saveGoal`, `save(_:)`, `saveCustomAmount`) — só nesses pontos é que a mudança
  realmente foi commitada.
- **D-5 — Instrumentar toques mesmo em botões sem ação hoje.** O "?" da Home e do
  Histórico são placeholders (`// TODO: ajuda / info`). Rastrear o toque mesmo assim
  é grátis e é justamente o tipo de sinal ("usuário queria ajuda e não achou") que
  seu objetivo de "controle máximo dos toques" pede.

## 5. Taxonomia de eventos

| Tela | Evento (`eventName`) | Disparado em | Metadata |
|---|---|---|---|
| home | `custom_amount_editor_open` / `_close` | sheet lifecycle (lápis do card "Outro") | — |
| home | `custom_amount_editor_save` | `HomeView.saveCustomAmount(_:)` | `amountML` |
| home | `home_help_tap` | botão "?" (headerRow) | — |
| profile | `goal_explainer_open` / `_close` | sheet lifecycle ("Entender minha meta") | — |
| profile | `edit_goal_open` / `_close` | sheet lifecycle (botão "Editar" do goalCard) | — |
| profile | `edit_goal_save` | `ProfileView.saveGoal(_:)` | `newGoalML` |
| profile | `action_button_tutorial_open` / `_close` | sheet lifecycle ("Como usar o botão de ação") | — |
| profile | `siri_tutorial_open` / `_close` | sheet lifecycle ("Como usar a Siri") | — |
| profile | `health_connect_row_tap` | toque em "Conectar ao Saúde" (ver §6) | — |
| profile | `edit_personal_data_open` / `_close` | sheet lifecycle (ProfileFormView) | — |
| profile | `edit_personal_data_save` | `ProfileView.save(_:)` | — |
| historico | `historico_day_tap` | `onTapGesture` de cada `DayCell` | `date`, `metGoal`, `isToday` |
| historico | `historico_day_detail_open` / `_close` | sheet lifecycle (`DayDetailSheet`) | `date` |
| historico | `historico_month_nav` | `HistoricoView.changeMonth(by:)` | `direction: prev\|next` |
| historico | `historico_page_toggle` | `pageToggleButton` **e** `cardSwipeGesture` | `method: tap\|swipe`, `toPage` |
| historico | `historico_help_tap` | botão "?" (topBar) | — |

Água (já pronto, sem trabalho novo): `IntakeLog.source ∈ {app, siri, actionButton}` +
`IntakeLog.tipoEntrada`.

## 6. Pendência aberta — sheet "Conectar ao Saúde"

`ProfileView.healthRow` seta `showHealthConnect = true`, mas **não existe
`.sheet(isPresented: $showHealthConnect)`** em lugar nenhum — a view de destino nunca
foi criada. Duas opções, e a spec não decide isso por você:

1. Rastrear só o toque na row (`health_connect_row_tap`) por enquanto, e adicionar o
   `.trackSheetLifecycle(.healthConnect, ...)` quando a sheet existir — é um
   `.sheet(...)` a mais, uma linha.
2. Fazer o Claude Code criar uma `HealthConnectView` mínima (placeholder de
   explicação + botão "Conectar") como parte desta spec.

Recomendo (1): não é escopo desta spec inventar o conteúdo/copy dessa tela. A Fase 4
abaixo já vem com essa divisão.

## 7. Plano de implementação (fases, em ordem)

### Fase 1 — Camada de dados (zero UI, risco baixo)
1.1. Criar `HidrataPOC/Models/UIInteractionEvent.swift` (código da seção 3).
1.2. Adicionar `UIInteractionEvent.self` ao `Schema([...])` em
     `HidrataPOC/Services/PersistenceController.swift`.
1.3. Em `HidrataPOC/Services/CloudKitSyncService.swift`: adicionar
     `func push(_ event: UIInteractionEvent) async`, copiando o método de
     `NotificationEvent` (campos: `userID`, `eventName`, `screen`, `metadataJSON`,
     `timestamp`). Adicionar o laço correspondente em `flushPending(context:)`.
1.4. Rodar `xcodegen generate` (o projeto usa XcodeGen — novo arquivo `.swift` em
     pasta já mapeada no `project.yml` deve entrar sozinho, mas confirme).
1.5. **Critério de aceite:** projeto compila; `UIInteractionEvent` aparece como novo
     record type no CloudKit Dashboard (ambiente Development) na primeira gravação.

### Fase 2 — Taxonomia + serviço de tracking
2.1. Criar `HidrataPOC/Support/TrackedEvent.swift` com os enums `AppScreen`
     (`home`, `profile`, `historico`) e `TrackedSheet` (um case por sheet da tabela
     da seção 5, raw value = prefixo do nome do evento, ex. `goalExplainer =
     "goal_explainer"`).
2.2. Criar `HidrataPOC/Services/InteractionTracker.swift`:

```swift
import Foundation
import SwiftData

@MainActor
enum InteractionTracker {
    static func logOpen(_ sheet: TrackedSheet, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        log("\(sheet.rawValue)_open", screen: screen, userID: userID, metadata: metadata, context: context)
    }

    static func logClose(_ sheet: TrackedSheet, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        log("\(sheet.rawValue)_close", screen: screen, userID: userID, metadata: metadata, context: context)
    }

    static func log(_ eventName: String, screen: AppScreen, userID: String, metadata: [String: String]? = nil, context: ModelContext) {
        let json = metadata.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let event = UIInteractionEvent(userID: userID, eventName: eventName, screen: screen.rawValue, metadataJSON: json)
        context.insert(event)
        try? context.save()
        Task {
            await CloudKitSyncService.shared.push(event)
            try? context.save()
        }
    }
}
```

2.3. Criar `HidrataPOC/Support/SheetLifecycleTracking.swift` — `ViewModifier` +
     `View.trackSheetLifecycle(_:screen:userID:metadata:)` que chama `logOpen` em
     `.onAppear` e `logClose` em `.onDisappear` do conteúdo da sheet (não da row que
     abre — do conteúdo, para não disparar quando a sheet nem está visível).
2.4. **Critério de aceite:** compila isolado; sem call sites ainda.

### Fase 3 — HomeView
3.1. `customIntakeCard`: no botão do lápis, antes de `isEditingCustomAmount = true`,
     nada a fazer aqui além do open via lifecycle no `.sheet` (3.2).
3.2. `.sheet(isPresented: $isEditingCustomAmount) { CustomIntakeEditorView(...).trackSheetLifecycle(.customAmountEditor, screen: .home, userID: profile.userID) }`.
3.3. Em `saveCustomAmount(_:)`, adicionar
     `InteractionTracker.log("custom_amount_editor_save", screen: .home, userID: profile.userID, metadata: ["amountML": "\(newValue)"], context: modelContext)`.
3.4. `headerRow`: no botão "?" (hoje `// TODO: ajuda / info`), adicionar
     `InteractionTracker.log("home_help_tap", screen: .home, userID: profile.userID, context: modelContext)`.
3.5. **Não mexer** em `logIntake(_:)` — os 4 botões já são capturados via `IntakeLog`.
3.6. **Critério de aceite:** abrir/editar/salvar o volume personalizado gera 3 linhas
     (`open`, depois `save`, depois `close` ao fechar) em `UIInteractionEvent`.

### Fase 4 — ProfileView (maior parte do pedido)
4.1. `.sheet(isPresented: $showGoalExplainer) { GoalExplainerView(...).trackSheetLifecycle(.goalExplainer, screen: .profile, userID: profile.userID) }`.
4.2. `.sheet(isPresented: $isEditingGoal) { EditGoalView(...).trackSheetLifecycle(.editGoal, screen: .profile, userID: profile.userID) }`; em `saveGoal(_:)`, adicionar
     `InteractionTracker.log("edit_goal_save", screen: .profile, userID: profile.userID, metadata: ["newGoalML": "\(newValue)"], context: modelContext)`.
4.3. `liveActivitiesRow`'s `.sheet` → `.trackSheetLifecycle(.actionButtonTutorial, screen: .profile, userID: profile.userID)`.
4.4. `siriRow`'s `.sheet` → `.trackSheetLifecycle(.siriTutorial, screen: .profile, userID: profile.userID)`.
4.5. `healthRow`: no botão, adicionar
     `InteractionTracker.log("health_connect_row_tap", screen: .profile, userID: profile.userID, context: modelContext)` — sem lifecycle de sheet ainda (ver §6).
4.6. `.sheet(isPresented: $isEditing) { ProfileFormView(...).trackSheetLifecycle(.editPersonalData, screen: .profile, userID: profile.userID) }`; em `save(_:)`, adicionar
     `InteractionTracker.log("edit_personal_data_save", screen: .profile, userID: profile.userID, context: modelContext)`.
4.7. **Critério de aceite:** cada uma das 4 sheets do perfil gera `_open`/`_close`;
     meta e dados pessoais também geram `_save` quando de fato salvos (e **não**
     geram `_save` se o usuário só abriu e cancelou).

### Fase 5 — HistoricoView (calendário)
5.1. No `onTapGesture` de cada `DayCell` (dentro do `ForEach` de `gridCells`), antes/depois de `selectedDay = cell`:
     `InteractionTracker.log("historico_day_tap", screen: .historico, userID: profile.userID, metadata: ["date": isoDate(cell.date), "metGoal": "\(cell.bateuMeta)", "isToday": "\(calendar.isDateInToday(cell.date))"], context: modelContext)`.
5.2. `.sheet(item: $selectedDay) { dia in DayDetailSheet(...).trackSheetLifecycle(.historicoDayDetail, screen: .historico, userID: profile.userID, metadata: ["date": isoDate(dia.date)]) }`.
5.3. Em `changeMonth(by:)`:
     `InteractionTracker.log("historico_month_nav", screen: .historico, userID: profile.userID, metadata: ["direction": value < 0 ? "prev" : "next"], context: modelContext)`.
5.4. `pageToggleButton`'s action e `cardSwipeGesture`'s `onEnded`: mesmo evento
     `"historico_page_toggle"` nos dois, com `metadata: ["method": "tap"|"swipe", "toPage": cardPage == .calendario ? "semana" : "calendario"]` (calculado **antes** de trocar `cardPage`, refletindo o destino).
5.5. `topBar`'s botão "?": `InteractionTracker.log("historico_help_tap", screen: .historico, userID: profile.userID, context: modelContext)`.
5.6. **Critério de aceite:** trocar de mês, alternar calendário↔semana por botão e
     por swipe, e tocar em 3 dias diferentes geram 1+1+2+3 linhas coerentes com
     metadata correta.

### Fase 6 — Confirmação (sem código)
6.1. Confirmar manualmente que um log via Siri ("Bebi 2 copos de HidrataPOC") gera 2
     linhas em `IntakeLog` com `source == "siri"`, `tipoEntrada == "copo"`.
6.2. Confirmar que um toque no Botão de Ação gera 1 linha com
     `source == "actionButton"`.
6.3. Nenhuma mudança de código nesta fase — só validação do que já existe.

### Fase 7 — Verificação end-to-end
7.1. Rodar no simulador, percorrer todas as sheets/telas da tabela da seção 5.
7.2. Abrir o CloudKit Dashboard (ambiente Development) e confirmar o record type
     `UIInteractionEvent` recebendo linhas com `eventName`/`screen`/`metadataJSON`
     corretos.
7.3. Testar offline→online: ativar modo avião, gerar alguns eventos (ficam
     `pending`), desativar, voltar o app ao foreground, confirmar que
     `flushPending` os sincroniza.
7.4. (Opcional) Estender `HidrataPOCTests/WaterIntakeCalculatorTests.swift` com um
     teste simples para `InteractionTracker.log` inserir a linha esperada em um
     `ModelContext` em memória.

## 8. Ordem recomendada para o Claude Code

Rode as fases 1 → 2 → 3 → 4 → 5 em sessões separadas (cada uma compila e roda
sozinha), pedindo revisão do diff antes de seguir para a próxima — a Fase 1 é a
única que precisa estar 100% certa antes das outras, porque todo o resto depende do
`UIInteractionEvent` e do `InteractionTracker` existirem. As Fases 3, 4 e 5 são
independentes entre si depois que a 1 e a 2 estão prontas.

## 9. Nota — acesso à conta do CloudKit Dashboard

A conta que administra o container `iCloud.com.hidratapoc` não é do Gabriel; acesso
ao Dashboard só a partir de quarta-feira. Isso **não bloqueia as Fases 1–5**:

- O record type `UIInteractionEvent` é criado automaticamente no ambiente
  Development na primeira gravação (mesmo comportamento de `IntakeLog`/
  `NotificationEvent`/`UserProfile`, descrito no README) — não precisa de acesso ao
  Dashboard.
- A permissão padrão do banco público, antes de qualquer Security Role configurada,
  já permite `Create` — o push funciona normalmente.
- O pipeline já é best-effort: se um push falhar antes da role/índices existirem,
  `syncStatus` fica `pending`/`failed` localmente e `flushPending(context:)` reenvia
  sozinho no próximo `scenePhase == .active`. Nada se perde.

O que **depende** de acesso à conta (fazer quando o acesso chegar, quarta-feira):
- Security Role de `UIInteractionEvent` → Create only, sem Read (mesmo texto do
  README para os outros tipos), nos ambientes Development e Production.
- Índices **Queryable** em `userID`/`eventName`/`screen` e **Sortable** em
  `timestamp` — sem isso dá pra gravar mas não dá pra consultar/filtrar pelo
  Dashboard.

Na Fase 7 (§7.2), a verificação "abrir o Dashboard e confirmar os records" fica
adiada para depois de quarta — o resto da Fase 7 (7.1, 7.3, 7.4) não depende disso.
