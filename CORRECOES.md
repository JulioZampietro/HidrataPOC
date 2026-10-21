# Correções da auditoria

Branch: `fix/auditoria` (a partir de `69cf825` em `liquidBolha`) · 41 commits · 2026-10-21
Relatório de origem: [AUDITORIA.md](AUDITORIA.md)

## Linha de base vs. final

| | Antes (69cf825) | Depois |
|---|---|---|
| Build Debug (`clean build`) | **SUCCEEDED** | **SUCCEEDED** |
| Build Release (`clean build`) | não medido na base | **SUCCEEDED** |
| Warnings de código distintos | 10 | **1** |
| Testes | **59** em 7 suítes, TEST SUCCEEDED | **73** em 10 suítes, TEST SUCCEEDED |
| Execuções consecutivas sem flake | — | 3 |

14 testes novos em 3 suítes: `CloudKitPseudonymizationTests` (4), `HydrationMathTests` (4), `IntakeOriginTests` (6).

O único warning restante é `NotificationScheduler.swift:983: consider using asynchronous alternative function` (o `center.add(_:completionHandler:)`), que não é um achado da auditoria.

> Nota sobre a linha de base: o AUDITORIA.md afirmava "apenas 2 warnings", número que vinha de um build **incremental**. Um `clean build` revela 10 warnings de código distintos. Os 2 que o relatório listou (B-8, B-9) foram corrigidos; os outros 8 eram pré-existentes e não constavam como achados — ver "Fora de escopo" no fim.

## Tabela de status

| ID | Status | Commit | Observação |
|---|---|---|---|
| **C-1** | Corrigido | `63ea4dc` | Pseudonimizado conforme sua escolha: envia `bmi` e `faixaIdade` (banda de 5 anos, 80+ colapsado) em vez de peso, altura e idade exatos; `generoAutoDeclarado` não é mais enviado. `dataset.py` aceita as duas formas. **Efeito colateral:** o restore perde peso/altura/idade exatos — ver "Riscos a testar". |
| **C-2** | Corrigido | `a58d68e` | Texto reescrito: o que é coletado, para onde vai, que peso e altura não saem do aparelho, que a localização só serve para o clima, e o caminho para revogar. **A cópia merece sua revisão.** |
| **C-3** | Corrigido | `09bcac1` | Tela "Meus dados" em Configurações: contagem, exportação JSON via ShareLink e exclusão total (local + CloudKit + HealthKit + `UserDefaults`). A exclusão avisa quando a parte remota falhou, em vez de alegar sucesso. |
| **A-1** | Corrigido | `55a9b87` | `idealPlan` vira `@State` preenchido no `.task`. Era ~25 execuções de Monte Carlo por avaliação do `body`. |
| **A-2** | Corrigido (parcial) | `d2bfa45`, `69cb74e` | 5 views com predicado completo; `HistoricoView` só por `userID`. O recorte por mês exibido exigiria extrair o calendário para uma subview (`displayedMonth` é `@State`, e `@Query` só é montado no init) — deixado de fora por escopo. |
| **A-3** | Corrigido | `e971d97` | `HydrationMath.totalsByDay` + `streak` em `@State`. Inclui normalização por `startOfDay` no laço, com teste de virada de horário de verão. |
| **A-4** | Corrigido | `0d77034` | Uma consulta por lote de 500 em vez de uma por registro. Chamador também passa a filtrar por usuário. |
| **A-5** | Corrigido | `6bb68b3` | Predicado `syncStatusRaw != "synced"` nas 6 tabelas. |
| **A-6** | Corrigido | `9acde8a` | Cartão abre `RemindersView`. **Não inventei controles** — a tela mostra o estado da permissão (com atalho para os Ajustes) e explica como o horário é decidido, porque quem decide é a política. |
| **A-7** | Corrigido | `f3f07ec` | `logIntake(.gole, …)`. Ver "Ações que dependem de você" sobre os registros já gravados errado. |
| **A-8** | Corrigido | `08b51a3` | `adjustmentLocked` no push e no restore; o merge nunca destrava. |
| **A-9** | Corrigido | `f527a64` | Idade 10–120, peso 20–300 kg, altura 80–250 cm; botão desabilitado e mensagem no rodapé fora da faixa. |
| **A-10** | Corrigido | `4a2c5b8` | Timeout de 10 s, com a limpeza da continuation serializada na main actor. |
| **A-11** | Corrigido | `6bb68b3` | Conjuntos de ids/UUIDs carregados uma vez. |
| **A-12** | Corrigido | `38ae3ad` | `currentHydrationState` só busca hoje; `captureContext` usa janela de 366 dias + fetch limitado a 1. **As features do dataset foram preservadas exatamente**, inclusive o clamp em 0. |
| **A-13** | Corrigido | `0dc9e3a` | `resumeWatching()` no launch e no `.active`. |
| **M-1** | Corrigido | `5f7310a` | 12 `print()` → `Logger`. Zero `print()` restante no app. |
| **M-2** | Corrigido (parcial) | `ec44e2a` | `ModelContext.saveLogging(_:)` nos 11 pontos onde perder a escrita é invisível. **Avisar o usuário na tela quando o registro de água falha ficou de fora**: é mudança de UX e precisa de decisão sua. |
| **M-3** | Corrigido | `7f973e5` | `canAttemptRead` separa leitura de escrita; em `HidrataPOCApp` o backfill é condicionado separadamente da importação. |
| **M-4** | Corrigido | `0406a83` | `lastSyncKey` só avança em query bem-sucedida, e usa o limite superior fixo da consulta. |
| **M-5** | Corrigido | `a63dd8f` | `lastRefreshKey` gravado após o fetch; falha agora é logada. |
| **M-6** | Corrigido | `5bba597` | `remote-notification` e `processing` removidos (confirmado: nenhum uso de push remoto nem `BGProcessingTaskRequest`). |
| **M-7** | Corrigido | `e482f2b` | `TimelineView(.animation(paused:))` na água e nos rins; CoreMotion não inicia. Minijogos ficam de fora (interativos, opt-in). |
| **M-8** | Corrigido | `69cb74e` | `Calendar`, `Locale` e 4 `DateFormatter` viram `static let`. |
| **M-9** | Corrigido | `38ae3ad` | Filtra por `userID`, salva local antes dos pushes. |
| **M-10** | Corrigido | `3e05821` | `expirationHandler` instalado antes do trabalho + `setTaskCompleted(success: false)`, com guard de conclusão única. |
| **M-11** | Corrigido | `1fe68b0` | Fallback para store em memória nos dois casos; `fatalError` só sobra para schema inválido (erro de programação). |
| **M-12** | Corrigido | `6bb68b3` | `withCloudKitRetry` respeitando `retryAfterSeconds`, só nos códigos temporários. |
| **M-13** | Corrigido | `0369adc` | Só o último registro espera o ActivityKit; pushes adiados e feitos de uma vez no fim. |
| **M-14** | Corrigido | `535cadd` | Pasta `notification/` removida + referência órfã no pbxproj. |
| **M-15** | Corrigido | `535cadd` | `BubblePOC.swift` removido. |
| **M-16** | **Precisa de você** | — | Remover `busy`/`event_density` muda o vetor de features de 14 para 12, o que invalida o `policy_params.json` embarcado (`priorMean`/`priorVar` têm 30 elementos). Exige refit do prior e publicação — não é mudança que eu possa fazer sozinho. |
| **M-17** | **Precisa de você** | — | Gerar lockfile exige instalar o ambiente (`ml/.venv` não existe aqui) e é operação de dependência. Comando em "Ações que dependem de você". |
| **M-18** | Corrigido | `3adafdb` | Patch do PyTensor agora em Python, portátil e idempotente. |
| **M-19** | **Precisa de você** | — | Localização é decisão de produto (o app é 100% pt-BR literal, ~17k linhas). Nenhuma mudança feita. |
| **M-20** | Corrigido (parcial) | `840b5f4` | `IntakeOriginTests` cobre a lógica de `origem` (a inferência central do dataset). `CloudKitSyncService.applyProfile/applyIntakeLog/applyDailyGoal` seguem sem teste — exigiriam fabricar `CKRecord`, trabalho maior que o escopo. |
| **B-1** | Corrigido | `e11b70b` | `appAccentLight`, `appOnTrack`, `appCardBackground`. |
| **B-2** | Corrigido | `ae0a393` | `resetSyncDate()`. |
| **B-3** | Corrigido | `7350c7d` | Diálogo de exclusão inalcançável da Home. |
| **B-4** | Corrigido | `7350c7d` | `weather`/`isLoadingWeather` + o `.task` que gastava GPS/WeatherKit sem consumidor. |
| **B-5** | **Precisa de você** | — | Remover `generoAutoDeclarado` é mudança de schema do SwiftData. O campo já não é mais enviado ao CloudKit (C-1) e o comentário foi atualizado (`358ff85`) dizendo por que ele continua lá. |
| **B-6** | Corrigido | `842746d` | Em vez de remover: `fusoHorario` passa a ser atualizado ao salvar o perfil. O pipeline usa o campo (`dataset.py::to_local`), então removê-lo quebraria o treino — um fuso velho desloca a hora de todo o histórico de quem muda de região. |
| **B-7** | Corrigido | `358ff85` | Comentários sobre `Genero` em `WaterIntakeCalculator` e `UserProfile`. |
| **B-8** | Corrigido | `7bf929a` | `fbm` removida (warning do compilador zerado). |
| **B-9** | Corrigido | `a7fe965` | `import SwiftData` (warning zerado). |
| **B-10** | **Não aplicável** | — | `gulun.m4a` é a fonte original do som, e já está documentada como tal em `NotificationScheduler.swift:899` ("the .m4a (AAC) source"). Apagá-la perderia o original sem ganho. |
| **B-11** | Corrigido | `e820898` | Linearização de gama + retorno do `getRed` verificado. |
| **B-12** | Corrigido | `3e05821` | `as!` → cast condicional. |
| **B-13** | Corrigido | `358ff85` | 4 force unwraps → switches exaustivos. **Valores da tabela do spec inalterados**; cobertos pelos `WaterIntakeCalculatorTests` existentes. |
| **B-14** | Corrigido | `e820898` | `randomElement()!` → `?? .middayNeutral`. |
| **B-15** | Corrigido | `e820898` | `nonisolated(unsafe) var` → `let`. |
| **B-16** | Corrigido | `e820898` | `watchedIDs` limpa o id ao fim da observação. |
| **B-17** | Corrigido | `9c05954` | `Bubble.metal` → `Water.metal` (lookups do ShaderLibrary são por função, não por arquivo). |
| **B-18** | Corrigido | `6b3a7e8` | `recordType` morto removido; entradas já persistidas seguem decodificando. |
| **B-19** | Corrigido | `e820898` | Comentário do `SLOT_HOURS`. |
| **B-20** | Corrigido | `c5a36de` | Trio de debug sob `#if DEBUG`; verificado com build Release. |
| **B-21** | Corrigido | `e820898` | Filtro redundante no widget. |
| **B-22** | **Precisa de você** | — | `resultouEmConsumo` vs. `intakeInWindow` como rótulo nas duas fontes de treino: é decisão de modelagem, não defeito. Não mexi. |
| **B-23** | **Não aplicável** | — | Confirmado em build limpo: o aviso vem só do target `HydrationKit` (framework sem intents). `HidrataPOC` e `HydrationWidget` escrevem `Metadata.appintents` normalmente — as frases da Siri estão registradas. |
| **B-24** | **Precisa de você** | — | `aps-environment: development` só se confirma num archive de distribuição, que depende de assinatura. |

**Resumo:** 47 corrigidos (3 parciais) · 2 não aplicáveis · 6 precisam de você.

## Achado extra, encontrado durante o trabalho

Não estava no relatório, e foi exposto pelos testes novos:

**`InteractionTracker.log` disparava um `Task` solto que capturava um `@Model` e o `ModelContext`** e sobrevivia ao chamador. O processo caía com *"This model instance was destroyed by calling ModelContext.reset"* quando a linha era apagada antes de o push terminar — o que a tela "Meus dados" do C-3 passou a permitir em produção. O push foi removido (`flushPending` já cobre `UIInteractionEvent` por `syncStatus`, em todo launch e foreground, e a linha já está salva como `.pending`). Commit `840b5f4`.

Também observado, **não corrigido** (fora de escopo, não era achado): `LiquidBubbleView` (118 linhas, `HidrataPOC/Shared/`) não tem nenhuma referência no projeto além da própria declaração e do `#Preview`. Candidato a remoção numa próxima passada.

## Fora de escopo: warnings pré-existentes não listados na auditoria

Oito warnings que o `clean build` revelou e que o relatório não registrou. Não são achados, então não mexi:

- `RootView.swift:23` — `UIScreen.main` deprecado no iOS 26.
- `NotificationScheduler.swift:983` — `center.add(_:completionHandler:)` tem alternativa assíncrona.
- `TankHeader.swift:11-16` (5 warnings) — acesso a `UIApplication.shared`/`connectedScenes`/`windows`/`isKeyWindow`/`safeAreaInsets` de contexto não isolado. **Este grupo merece atenção**: é exatamente a classe de problema de concorrência que vira crash com o Swift 6 strict concurrency ligado.
