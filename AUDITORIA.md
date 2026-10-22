# Auditoria de código — HidrataPOC

Data: 2026-10-21 · Branch: `liquidBolha` (69cf825) · Escopo: todo o código-fonte (88 arquivos Swift ≈ 17.2k linhas, 11 arquivos Python, configs, specs, testes).
Nenhum arquivo do projeto foi alterado nesta auditoria — este relatório é o único arquivo criado.

---

## 1. Resumo executivo

App iOS 26 de hidratação (SwiftUI + SwiftData) com quatro alvos (app, `HydrationWidget`, `HydrationKit`, testes), sincronização manual para o **banco público** do CloudKit, HealthKit, WeatherKit, Live Activities, App Intents/Siri, Control Center e uma política de bandit contextual (Thompson sampling) que decide os horários dos lembretes, com prior treinado offline num pipeline Python.

O código é incomumente bem documentado — praticamente toda decisão não óbvia tem um comentário explicando o porquê, e as partes matemáticas (`ThompsonPolicy`, `WaterIntakeCalculator`, `DailyGoalResolver`) têm testes de paridade com a referência Python. A arquitetura de camadas (modelos → serviços puros → views) está coerente. O build compila com apenas 2 warnings reais.

**Os três maiores riscos:**

1. **Privacidade (Crítica).** Idade, peso, altura, sexo biológico e todo o histórico de consumo com timestamp vão para o banco **público** do CloudKit. A única proteção é um papel de segurança configurado à mão no CloudKit Dashboard — não está no código, não está versionado e não há teste que o verifique. Agravantes: a tela de consentimento afirma que "nenhum dado de saúde sensível é coletado" (peso/altura/idade são dados de saúde), não há como o usuário exportar ou apagar seus dados, e o consentimento é um booleano em `UserDefaults` sem data nem versão.
2. **Performance da UI (Alta).** Sete `@Query` sem predicado carregam tabelas inteiras a cada render; `DayDetailSheet` roda ~25 simulações de Monte Carlo (200 amostras × 30 dimensões × 7 slots cada) por avaliação do `body`, na main actor; `WaterHeaderView.streak` é O(365 × N) por render; o `backfill` do HealthKit faz uma query por registro, em série, a cada volta do app ao primeiro plano.
3. **Integridade do dataset de pesquisa (Alta).** O botão "Gole" grava `tipoEntrada: "personalizado"` em vez de `"gole"`, divergindo das outras quatro superfícies que registram os mesmos 40 mL; `adjustmentLocked` não é sincronizado, então um restore reabre a meta do dia que o lock existia para fechar; duas features do modelo (`busy`, `event_density`) são constantes fixas desde que o contexto de calendário foi removido.

Há também dois casos de funcionalidade visivelmente quebrada para o usuário: o cartão "Configurar lembretes" (o mais proeminente da tela de Configurações) não abre nada, e o diálogo de exclusão de registro da Home é inalcançável.

---

## 2. Tabela de achados

| ID | Sev. | Categoria | Arquivo:linha | Problema | Correção sugerida | Esf. |
|---|---|---|---|---|---|---|
| C-1 | **Crítica** | Segurança | `Services/CloudKitSyncService.swift:27-45`, `74-241` | PII de saúde (idade, peso, altura, sexo, cada gole com timestamp, clima) gravada no banco **público**; proteção só por papel do Dashboard, não versionada | Mover para o banco privado + zona compartilhada, ou pseudonimizar (dropar peso/altura/idade do push e enviar só faixas); documentar o papel como IaC/checklist de release | G |
| C-2 | **Crítica** | Segurança | `Views/Consent/ConsentView.swift:32` | Texto afirma "Nenhum dado de saúde sensível é coletado" — peso, altura, idade e ingestão são dados de saúde; não menciona banco público, HealthKit nem localização | Reescrever o consentimento: listar tudo, dizer onde fica, por quanto tempo, e como revogar | P |
| C-3 | **Crítica** | Segurança | `Views/Consent/ConsentView.swift`, `App/RootView.swift:6` | Sem revogação de consentimento, sem exportar dados, sem apagar conta/dados (GDPR/LGPD art. 18) | Tela "Meus dados": exportar JSON + apagar tudo (local, CloudKit, HealthKit); gravar consentimento com data e versão do texto | M |
| A-1 | Alta | Performance | `Views/Historico/HistoricoView.swift:505-513`, `556-568`, `586-591`, `628`, `659`, `674`, `699`, `713` | `idealPlan` é *computed property* que roda Monte Carlo (200×30×7) + decode JSON do `PolicyStore`; é alcançada ~25× por render do `body` | Calcular uma vez em `@State`, num `.task`, e guardar o resultado | P |
| A-2 | Alta | Performance | `HomeView.swift:14-15`, `WaterHeaderView.swift:22-23`, `TankHeader.swift:85-86`, `HistoricoView.swift:63-64`, `ProfileView.swift:10-11`, `HealthConnectView.swift:9` | `@Query` sem predicado: carrega **toda** a tabela `IntakeLog`/`DailyGoal` na memória e filtra em Swift a cada render | Usar `#Predicate` por `userID` (+ faixa de data onde cabe), como já faz `DayDetailSheet.init` | M |
| A-3 | Alta | Performance | `Shared/WaterHeaderView.swift:154-156` + `Services/HydrationMath.swift:89-101`, `6-10` | `streak` é O(maxDays × N): até 365 iterações, cada uma filtrando todos os logs com `Calendar.isDate(inSameDayAs:)`; reavaliado a cada `body` (inclusive por frame durante o arrasto entre páginas) | Pré-agregar totais por dia num `[Date: Int]` uma vez e passar para `currentStreak`; cachear o streak em `@State` | M |
| A-4 | Alta | Performance | `Services/HealthKitService.swift:160-166` + `App/HidrataPOCApp.swift:82-84` | `backfill` faz um `HKSampleQuery` por log, em série, sobre **todos** os logs, a cada `scenePhase == .active` | Uma query só com `predicateForObjects(withMetadataKey:allowedValues:)` para todos os UUIDs, ou marcar no `IntakeLog` que já foi escrito no Health | M |
| A-5 | Alta | Performance | `Services/CloudKitSyncService.swift:297-336` | `flushPending` faz `fetch` sem predicado nas 6 tabelas e `await push` em série, a cada launch e a cada foreground | Predicado `syncStatusRaw != "synced"` + `modifyRecords` em lote (já usado para `DailyGoal`) | M |
| A-6 | Alta | Bug | `Views/Profile/ProfileView.swift:223-251`, `16` | "Configurar lembretes" seta `showReminders = true`, mas não existe nenhum `.sheet`/`navigationDestination` ligado a ele — o cartão principal da tela não faz nada | Implementar a tela, ou remover o cartão | M |
| A-7 | Alta | Bug / dados | `Views/Home/HomeView.swift:391` | Cartão "Gole" chama `logIntake(.custom(volumeML: 40))` → grava `tipoEntrada: "personalizado"`; a notificação, a Siri e o Control Center gravam `"gole"` para os mesmos 40 mL | Usar `.gole` | P |
| A-8 | Alta | Bug / dados | `Services/CloudKitSyncService.swift:180-208`, `491-511` | `adjustmentLocked` não é enviado nem restaurado: depois de um restore toda linha volta destravada e `DailyGoal.recordToday` reescreve o ajuste do dia que o lock protegia | Incluir o campo no `push`/`applyDailyGoal` | P |
| A-9 | Alta | Bug / validação | `Views/Profile/ProfileFormView.swift:167-184`, `238-241` | Peso e altura aceitam qualquer `Double`: `0` kg → meta 0 mL → progresso sempre 0 e app inútil; `500` kg → meta no teto de 11 L. Só `idade` é limitada | Validar faixas (peso 20–300 kg, altura 80–250 cm), desabilitar o botão de salvar com valor fora da faixa e mostrar o erro | P |
| A-10 | Alta | Bug / borda | `Services/WeatherContextService.swift:148-158`, `126-142` | `fetchOneTimeLocation` não tem timeout: se `requestLocation()` nunca retornar (GPS indisponível), a continuation e `inflightLocationTask` nunca são limpos e **toda** chamada de clima fica pendurada para sempre | `withTimeout` (ex. 10 s) que resume a continuation com erro e limpa `inflightLocationTask` | P |
| A-11 | Alta | Performance | `Services/CloudKitSyncService.swift:458-488` | `applyIntakeLog` faz 2 `fetchCount` por registro → N+1 no restore completo (milhares de queries) | Carregar os `id`/`healthKitUUID` existentes em dois `Set` antes do laço | P |
| A-12 | Alta | Performance | `Services/NotificationScheduler.swift:468-483` + `App/HidrataPOCApp.swift:93-100` | `tick()` roda a cada 60 s na main actor e faz: scan completo de `NotificationEvent`, scan completo de `IntakeLog` (2×, via `refreshPendingMascotIfNeeded` e `currentHydrationState`), possível round trip WeatherKit, e até 8 decodes JSON de `pendingNotificationSlots` | Predicados nos fetches, memoizar os slots em memória, e separar a cadência (clima/mascote não precisam de 60 s) | M |
| A-13 | Alta | Bug | `Services/LiveActivityManager.swift:135-137` | `resumeWatching()` está implementado e documentado, mas **nunca é chamado** — uma Live Activity que sobrevive ao relaunch nunca volta a ser observada, então a variante island-only não é recriada ao usuário descartar o cartão | Chamar em `HidrataPOCApp.setUpOnLaunch()`/`.active`, ou remover | P |
| M-1 | Média | Observabilidade | `Services/NotificationScheduler.swift:306,866,942,944,956,969`; `Services/HealthKitService.swift:30,117,184,197,214,241` | 12 `print()` em código de produção, incluindo um `✅` por notificação armada e contagens de amostras de saúde no console | Trocar por `Logger` (já usado em `CloudKitSyncService`/`WeatherContextService`), com `privacy:` adequado | P |
| M-2 | Média | Tratamento de erro | ~100 `try?` em 20 arquivos; concentração em `NotificationScheduler.swift` (32), `CloudKitSyncService.swift` (19), `WaterHeaderView.swift` (14) | Todo `context.save()` e `context.fetch()` engole o erro: uma falha de persistência é indistinguível de "nada a fazer" e o usuário nunca sabe que o registro não foi salvo | Centralizar um `save()` que loga o erro (e, no caminho de registrar água, avisa o usuário) | M |
| M-3 | Média | Bug | `Services/HealthKitService.swift:20-22`, `182-186` | `isAuthorized` usa `authorizationStatus(for:)`, que reflete só permissão de **escrita**. `syncFromHealthKit` (leitura) é bloqueado por ele: quem libera ler mas não escrever nunca importa nada | Separar os dois: tentar a query de leitura e tratar resultado vazio/erro, sem usar o status de escrita como gate | P |
| M-4 | Média | Bug / dados | `Services/HealthKitService.swift:200-243` | `lastSyncKey` avança para `.now` mesmo quando a `HKSampleQuery` falha (o erro é descartado em `{ _, results, _ in }`) → amostras daquela janela são perdidas permanentemente | Só gravar `lastSyncKey` quando a query retornar sem erro | P |
| M-5 | Média | Bug | `Policy/PolicyStore.swift:31-44` | `lastRefreshKey` é gravado **antes** do fetch: uma falha (offline no launch) queima a janela de 6 h e o device fica sem o prior novo | Gravar o timestamp só no sucesso (ou um backoff curto na falha) + logar o erro, que hoje é silencioso | P |
| M-6 | Média | Segurança | `Support/Info.plist:38-43` | `UIBackgroundModes` declara `remote-notification` e `processing`, mas o app não trata push remoto nem agenda `BGProcessingTaskRequest` (só `BGAppRefreshTaskRequest`) | Deixar apenas `fetch` — permissões a mais são motivo de rejeição na App Review | P |
| M-7 | Média | Acessibilidade | Nenhuma ocorrência de `reduceMotion`/`reduceTransparency` no projeto; `Shared/WaterFillView.swift:190,241`, `Views/Home/*GameView.swift`, `KidneyCheerView.swift:7` | Dois `TimelineView(.animation)` com shaders Metal rodam a cada frame enquanto Home/Histórico estão visíveis (o recipiente está sempre na tela), mais CoreMotion a 60 Hz; `Reduzir Movimento` é ignorado em todo o app | Honrar `@Environment(\.accessibilityReduceMotion)`: congelar o campo de água e as partículas, e pausar o `TimelineView` | M |
| M-8 | Média | Performance | `Views/Historico/HistoricoView.swift:69-74` (40 usos), `134-140`, `602-608`, `345-350`; `IntakeRow:802-806` | `calendar` é *computed property* que constrói `Calendar` + `Locale` a cada acesso (40 no arquivo, vários por célula do mês); `monthTitle`, `dateTitle`, `isoDate` e `timeLabel` criam `DateFormatter` por render | Tornar `static let` (Calendar, Locale e DateFormatter são caros e reutilizáveis) | P |
| M-9 | Média | Confiabilidade | `Services/NotificationScheduler.swift:824-835` | `resolveTimedOutEvents` não filtra por `userID` e dá `await push` em série dentro do laço | Adicionar o predicado de usuário e agrupar os pushes | P |
| M-10 | Média | Confiabilidade | `Services/BackgroundRefreshService.swift:31-43` | `task.expirationHandler` é atribuído **depois** de a `Task` começar (janela de corrida) e, no cancelamento, `setTaskCompleted` nunca é chamado — o iOS passa a dar menos tempo de background ao app | Registrar o `expirationHandler` antes de iniciar o trabalho e chamar `setTaskCompleted(success: false)` nele | P |
| M-11 | Média | Confiabilidade | `Services/PersistenceController.swift:23`, `34` | Dois `fatalError` no caminho de launch: App Group ausente ou store corrompido = crash no boot, sem telemetria nem recuperação | Fallback para store em memória + tela de erro; logar antes de desistir | M |
| M-12 | Média | Confiabilidade | `Services/CloudKitSyncService.swift:119,234,251,274,413,529` | Nenhum `catch` honra `CKError.retryAfterSeconds`, e não há backoff: sob throttling do CloudKit tudo vira `.failed` e o próximo `flushPending` repete imediatamente | Backoff exponencial respeitando `retryAfterSeconds`, com limite de tentativas | M |
| M-13 | Média | Performance | `Intents/SiriIntents.swift:192-204`, `206-214` | `logIntakes` chama `IntakeLogService.record` N vezes; cada chamada faz fetch, save, `await` de um push CloudKit e até 1 s de retry do `endLiveActivity`. "Bebi 5 copos" = 5 round trips de rede num intent com orçamento curto. `totalConsumedToday` ainda carrega todos os logs do usuário | Inserir os N logs numa transação, um push só, `deferCloudSync: true`; predicado de data no total | M |
| M-14 | Média | Código morto | `notification/NotificationService.swift` (todo o arquivo), `notification/Info.plist` | Pasta `notification/` é um `PBXFileSystemSynchronizedRootGroup` **sem alvo**: boilerplate do Xcode que acrescenta `" [modified]"` ao título de qualquer notificação. Não compila hoje; se for ligada a um alvo, quebra todas as cópias de persona | Apagar a pasta | P |
| M-15 | Média | Código morto | `BubblePOC.swift` (raiz, 43 linhas) | Não está no `project.pbxproj`; chama `ShaderLibrary.bubble`, função que não existe mais em `Shaders/Bubble.metal` — não compilaria | Apagar | P |
| M-16 | Média | Modelagem/ML | `Policy/AppPolicyContextProvider.swift:45-46`, `Policy/PolicyParams.swift:103-105`, `Models/NotificationEvent.swift:62`, `ml/python/config.py:31` | `busy` e `event_density` são sempre `false`/`0` desde que o contexto de calendário foi removido, mas continuam no vetor de 14 features: duas colunas de variância zero padronizadas e treinadas | Remover das features e do prior, ou reintroduzir o EventKit | M |
| M-17 | Média | Reprodutibilidade | `ml/python/requirements.txt` | 12 dependências com `>=` e sem upper bound nem lockfile; o prior que vai dentro do app não é reproduzível a partir do repo | `pip-compile`/`uv lock` com hashes | P |
| M-18 | Média | Manutenibilidade | `ml/run_pipeline.sh:27-28` | `sed -i ''` (sintaxe BSD, quebra em Linux/CI) aplicado a um arquivo dentro de `site-packages` do PyTensor; o glob `python3*` pode expandir para vários caminhos | Pinar a versão do PyTensor que não precisa do patch, ou aplicar via variável de ambiente `PYTENSOR_FLAGS` | P |
| M-19 | Média | i18n | Todo o projeto (ex. `Support/MascotPhrases.swift`, `Support/NotificationVariant.swift`, todas as views) | 100% das strings de UI em pt-BR literais no código; nenhum `Localizable.strings`, nenhum `CFBundleLocalizations` | Extrair para catálogo de strings se houver intenção de outro idioma; caso contrário, documentar a decisão | G |
| M-20 | Média | Qualidade/testes | `HidrataPOCTests/` (59 testes em 7 suítes) | Sem cobertura nos pontos mais arriscados: `CloudKitSyncService` (conflito, restore, merge de perfil), `IntakeLogService.record` (a lógica de `origem` que define o dataset), dedup do HealthKit, `PolicyCoordinator.resolveOutcomes/rebuild/adopt`, `WidgetSync` | Testes de unidade para `applyProfile`/`applyIntakeLog`/`applyDailyGoal` e para o casamento notificação↔ingestão | G |
| B-1 | Baixa | Código morto | `Support/AppTheme.swift:239`, `269`, `377` | `Color.appAccentLight`, `Color.appOnTrack` e `View.appCardBackground(cornerRadius:)` sem nenhuma referência | Remover | P |
| B-2 | Baixa | Código morto | `Services/HealthKitService.swift:248-250` | `resetSyncDate()` nunca chamado | Remover | P |
| B-3 | Baixa | Código morto | `Views/Home/HomeView.swift:19`, `128-137`, `447-449`, `492-495` | `pendingDeleteLog` só é lido e zerado, nunca recebe valor: o `confirmationDialog` "Excluir este registro?" e `deleteLog(_:)` são inalcançáveis na Home (a exclusão real está em `DayDetailSheet`) | Remover o diálogo e o estado | P |
| B-4 | Baixa | Código morto | `Views/Home/HomeView.swift:24-25`, `115`, `460-463` | `weather` e `isLoadingWeather` são escritos e nunca lidos; o `.task { await loadWeather() }` dispara um fetch de localização + WeatherKit por aparição da Home sem nenhum consumidor | Remover os dois `@State` e o `.task` | P |
| B-5 | Baixa | Código morto | `Models/UserProfile.swift:14`, `Views/Profile/ProfileView.swift:549` | `generoAutoDeclarado` só é atribuído (`= nil`); nenhuma tela escreve valor — `Genero` só tem `masculino`/`feminino` | Remover o campo (ou reintroduzir a opção) | P |
| B-6 | Baixa | Código morto | `Models/UserProfile.swift:18` | `fusoHorario` é gravado no onboarding e enviado ao CloudKit, mas nenhum cálculo de data no app o usa (tudo usa `Calendar.current`); também nunca é atualizado numa edição de perfil | Decidir: usar de verdade (fronteira de dia por fuso, como o Python já faz) ou remover | M |
| B-7 | Baixa | Docs desatualizadas | `Services/WaterIntakeCalculator.swift:3-7`, `Models/UserProfile.swift:13`, `69-72` | Três comentários descrevem `Genero` com cinco casos (não-binário, autodeclarado, prefiro não dizer) que não existem mais; o ramo `case nil` de `suggestedGoalML` só é alcançável por dado legado | Atualizar os comentários | P |
| B-8 | Baixa | Código morto | `Shaders/Bubble.metal:65` (warning do compilador) | `static float fbm(float2 p)` não é usada (`-Wunused-function`) | Remover | P |
| B-9 | Baixa | Build | `Support/SheetLifecycleTracking.swift:7` (warning do compilador) | `cannot use class 'ModelContext' ... 'SwiftData' was not imported by this file` | Adicionar `import SwiftData` | P |
| B-10 | Baixa | Assets | `gulun.m4a` (raiz) | O app usa `HidrataPOC/Support/Sounds/gulun.caf`; o `.m4a` na raiz é a fonte não convertida, não referenciada | Mover para fora do repo ou documentar como fonte | P |
| B-11 | Baixa | Correção | `Views/Home/ShareProgressView.swift:49-53` | `Color.luminance` soma componentes sRGB sem linearizar (falta a correção de gama), então não é luminância relativa; `getRed(...)` tem retorno descartado e falha silenciosa em cores não-RGB | Linearizar antes de ponderar; checar o `Bool` de retorno | P |
| B-12 | Baixa | Robustez | `Services/BackgroundRefreshService.swift:21` | `task as! BGAppRefreshTask` — force cast | `guard let ... else { return }` | P |
| B-13 | Baixa | Robustez | `Services/WaterIntakeCalculator.swift:100`, `103`, `107` | Quatro force unwraps em lookups de dicionário (`iomBaselineL[gender]!`, `environmentIncrementL[heatCategory]![activityLevel]!`): seguros hoje, crash se um caso de enum for adicionado | Trocar os dicionários por `switch` exaustivo | P |
| B-14 | Baixa | Robustez | `Services/NotificationScheduler.swift:664` | `midday.randomElement()!` sobre um array literal | `?? .middayNeutral` | P |
| B-15 | Baixa | Concorrência | `Intents/SiriIntents.swift:11` | `static nonisolated(unsafe) var caseDisplayRepresentations` — `var` mutável global sem proteção | `let` | P |
| B-16 | Baixa | Memória | `Services/LiveActivityManager.swift:116-132` | `watchedIDs` cresce indefinidamente (nunca remove ids de atividades já encerradas) | Remover o id ao fim do `for await` | P |
| B-17 | Baixa | Nomenclatura | `Shaders/Bubble.metal` | Arquivo chamado `Bubble.metal` contém os shaders `water`/`waterRefraction` e a física de pedrinhas; o shader `bubble` que dava o nome não existe mais | Renomear para `Water.metal` | P |
| B-18 | Baixa | Dead param | `Services/CloudKitSyncService.swift:249`, `261-265`, `267-282` | `recordType` em `delete(recordType:id:)` e em `PendingDeletion` só é usado em log — `flushPendingDeletions` ignora o tipo | Remover, ou usar no retry | P |
| B-19 | Baixa | Drift de config | `ml/python/config.py:4` vs `Support/Constants.swift:43` | Comentário diz "the app's fixed grid" mas a lista tem 22 h, que o app não tem; só coincidem porque `ACTIVE_SLOT_HOURS` filtra depois | Corrigir o comentário (e idealmente derivar um do outro) | P |
| B-20 | Baixa | Debug em release | `Services/NotificationScheduler.swift:1098-1134` | `sendDebugNotification` (×2) e `sendRandomDebugCopy` não estão sob `#if DEBUG` (só as chamadas em `ProfileView` estão) — código de debug compilado no binário de produção | Envolver em `#if DEBUG` | P |
| B-21 | Baixa | Redundância | `HydrationWidget/WaterTankWidget.swift:70-74` | Predicado já filtra `timestamp >= startOfDay` e depois há um `filter { isDate(inSameDayAs:) }` em Swift | Remover o filtro redundante | P |
| B-22 | Baixa | Observação ("a confirmar") | `ml/python/dataset.py:108` vs `:115` | A label é `resultouEmConsumo` para `NotificationEvent` e `intakeInWindow` para `SlotDecision` — definições próximas mas não idênticas de "bebeu depois do lembrete". **A confirmar** se isso é intencional | Documentar a equivalência ou unificar | P |
| B-23 | Baixa | Observação ("a confirmar") | build log | `appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` — provavelmente do alvo `HydrationKit`, mas se afetar o app principal as frases da Siri não são registradas. **A confirmar** rodando um `clean build` e testando uma frase no dispositivo | Verificar; se necessário, linkar AppIntents | P |
| B-24 | Baixa | Observação ("a confirmar") | `Support/HidrataPOC.entitlements:4` | `aps-environment: development`. O Xcode normalmente reescreve isso na distribuição. **A confirmar** antes de uma build de TestFlight | Verificar no archive | P |

---

## 3. Detalhamento dos achados Críticos e Altos

### C-1 · Dados pessoais de saúde no banco público do CloudKit

`HidrataPOC/Services/CloudKitSyncService.swift:74-101`:

```swift
func push(_ profile: UserProfile) async {
    let record = existingOrNewRecord(type: "UserProfile", id: profile.id, systemFields: profile.ckSystemFields)
    record["idade"] = profile.idade
    record["pesoKg"] = profile.pesoKg
    record["alturaCm"] = profile.alturaCm
    record["genero"] = profile.genero
    ...
    let saved = try await saveResolvingConflict(record)   // → container.publicCloudDatabase
```

O comentário de topo do arquivo é explícito sobre a escolha e sobre a mitigação:

> Uses the public database (not private) because the goal is a dataset the developer can read across every TestFlight tester […] see the CloudKit Dashboard Security Roles setup in the project README for the corresponding "Authenticated: Create only, no Read" role, **which must be configured manually in the dashboard**.

O problema não é a escolha (é defensável para coletar um dataset de pesquisa) — é que **a única barreira entre os dados de saúde de um participante e qualquer dispositivo autenticado no container é uma caixa de seleção fora do controle de versão**. O default do CloudKit para um novo record type é `World: Read`; se alguém criar o tipo pelo app antes de ajustar o papel, ou recriar o schema no ambiente de produção, os dados ficam legíveis. Não há teste, script ou checklist no repo que verifique isso.

Além do perfil, vão para o banco público: cada `IntakeLog` com timestamp ao segundo e temperatura/umidade local (proxy de localização e de rotina diária), cada `NotificationEvent` com o comportamento de resposta, e cada `UIInteractionEvent` com navegação na UI. Juntos, são um perfil comportamental de 24 h/dia associado a um `userID` estável do iCloud.

**Correção sugerida**, em ordem de preferência:

1. **Banco privado + CloudKit Sharing** para os dados do participante, com o pesquisador adicionado como participante da zona. Mantém o acesso agregado sem expor nada publicamente.
2. Se o público for mantido: **pseudonimizar no push** — não enviar `pesoKg`/`alturaCm`/`idade` brutos (o modelo usa `bmi`, `age` e `goal_l`; dá para enviar faixas ou só os derivados), e versionar o papel de segurança como um script `ml/` que valida o schema antes de cada release.
3. Em qualquer caso, adicionar ao `README.md` um checklist de release que inclua "verificar Security Roles em ambos os ambientes" e um teste manual de leitura cruzada entre duas contas iCloud.

### A-1 · Monte Carlo recalculado ~25× por render do gráfico

`HidrataPOC/Views/Historico/HistoricoView.swift:505-513`:

```swift
private var idealPlan: [HydrationPlanPoint]? {
    HydrationPlanner.idealDayCurve(profile: profile, effectiveGoalML: metaDiariaML,
                                   weather: dayWeather, day: dia.date, calendar: calendar)
}
```

Cada chamada faz um `PolicyStore.shared.loadParams()` (decode JSON de `UserDefaults`) e, para cada um dos 7 slots, um `ThompsonPolicy.probabilitySend` — que com `policy_params.json` atual (`mcSamples: 200`, vetor de 30 dimensões) são **200 × 30 = 6.000 amostras gaussianas** (cada uma com `log`, `sqrt`, `cos`) mais 200 produtos escalares de 60 elementos. Por chamada: ~42.000 transcendentais.

O problema é a cadeia de *computed properties*: `domainStart` e `domainEnd` (`:561-568`) chamam `planHourBounds` → `idealPlan`; `idealSeries` (`:517-525`) chama `idealPlan` **mais** `domainStart` **mais** `domainEnd` (3 execuções por acesso); `cumulativeSeries` chama as duas de domínio (2); `hourlyAxisMarks` idem. E o `body` acessa `idealSeries` em quatro lugares (`:628`, `:659`, `:589`, `:713`), `cumulativeSeries` em três (`:634`, `:644`, `:589`), `chartXScale` em um (`:674`).

Somando, cada avaliação do `body` do `DayDetailSheet` executa `idealDayCurve` cerca de 25 vezes — da ordem de **1 milhão de operações transcendentais na main actor**, antes de o Charts desenhar qualquer coisa. E o `body` reavalia a cada `@Query` que muda, a cada `currentWeather` que chega e a cada mudança de layout.

**Correção:**

```swift
@State private var idealPlan: [HydrationPlanPoint]?

// no .task, depois de currentWeather:
.task {
    if isToday, currentWeather == nil {
        currentWeather = await WeatherContextService.shared.currentContext()
    }
    idealPlan = HydrationPlanner.idealDayCurve(
        profile: profile, effectiveGoalML: metaDiariaML,
        weather: dayWeather, day: dia.date, calendar: calendar
    )
}
```

e derivar `idealSeries`/`planHourBounds`/`domainStart`/`domainEnd` desse `@State`. Vale também cachear o `PolicyParams` decodificado em `PolicyStore` (hoje `loadParams()` decodifica JSON em toda chamada, inclusive dentro de `armNextSlotIfClear`).

### A-2 · `@Query` sem predicado em sete views

`HidrataPOC/Views/Home/HomeView.swift:14-15`, `40-48`:

```swift
@Query private var allLogs: [IntakeLog]
@Query private var allDailyGoals: [DailyGoal]

private var todayLogs: [IntakeLog] {
    allLogs.filter { $0.userID == profile.userID && Calendar.current.isDateInToday($0.timestamp) }
}
```

Isso materializa **toda** a tabela `IntakeLog` (que cresce com cada gole, cada importação do HealthKit e cada restore do CloudKit) a cada invalidação de `body`, e só então filtra em Swift. O mesmo padrão aparece em `WaterHeaderView:22-23`, `TankHeader:85-86`, `HistoricoView:63-64`, `ProfileView:10-11` e `HealthConnectView:9` — ou seja, três dessas views estão na tela ao mesmo tempo (Home, Histórico e o header), cada uma com sua própria cópia.

O próprio projeto já tem o padrão certo, em `DayDetailSheet.init` (`HistoricoView.swift:473-483`):

```swift
let predicate = #Predicate<IntakeLog> { $0.userID == userID && $0.timestamp >= dayStart && $0.timestamp < dayEnd }
_logs = Query(filter: predicate, sort: \IntakeLog.timestamp)
```

**Correção:** dar a cada view um `init` que monte o `Query` com predicado. Para `HomeView`/`WaterHeaderView`/`TankHeader`, basta `userID` + `timestamp >= startOfDay`; para `HistoricoView`, `userID` + o intervalo do mês exibido (e refazer o query ao trocar de mês), já que o calendário só precisa do mês, e o gráfico semanal dos últimos 7 dias.

### A-3 · Streak O(365 × N) por avaliação de `body`

`HidrataPOC/Shared/WaterHeaderView.swift:154-156`:

```swift
private var streak: Int {
    HydrationMath.currentStreak(allLogs.filter { $0.userID == profile.userID }, goalML: goalResolver.goalML(on:))
}
```

`currentStreak` (`HydrationMath.swift:89-101`) caminha até `maxDays: 365` dias, e para cada dia chama `metGoal` → `totalML`, que é:

```swift
logs.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.reduce(0) { $0 + $1.volumeML }
```

Um `filter` completo com uma comparação de calendário por log. Com um ano de uso a ~8 registros/dia (≈3.000 logs), um streak longo custa até **~1,1 milhão de comparações de `Calendar`** — a operação mais cara do app por uma margem larga.

E `streak` é lido do `body` em quatro lugares (`:195` no `.onChange`, `:247` no texto do header, `:167`/`:170` nas sheets) e indiretamente por `activeGame`/`runningGame` (`:275`, `:281`), que o `topSection` consulta. O `topSection` está dentro de um `GeometryReader` que, como os próprios comentários de `HomeView:71-73` e `HistoricoView:97-99` registram, **refaz o conteúdo a cada frame durante o arrasto entre páginas** — foi exatamente o problema que levou a extrair `TodayIntake` e `MonthSummary`. O `streak` não recebeu o mesmo tratamento.

**Correção:** pré-agregar uma vez e passar a agregação para a matemática pura:

```swift
// em HydrationMath
static func totalsByDay(_ logs: [IntakeLog], calendar: Calendar = .current) -> [Date: Int] {
    var totals: [Date: Int] = [:]
    for log in logs { totals[calendar.startOfDay(for: log.timestamp), default: 0] += log.volumeML }
    return totals
}
static func currentStreak(totalsByDay: [Date: Int], goalML: (Date) -> Int, ...) -> Int
```

(`HistoricoData.generateMonth:34-51` já usa exatamente essa técnica, com o comentário explicando por quê.) Além disso, guardar o streak num `@State` recalculado em `.onChange(of: consumedToday)`, não por render.

### A-4 · `backfill` do HealthKit: uma query por registro, a cada foreground

`HidrataPOC/App/HidrataPOCApp.swift:77-85`:

```swift
private func syncHealthKitIfAuthorized() async {
    guard HealthKitService.shared.isAuthorized, let profile = ... else { return }
    let allLogs = (try? ctx.fetch(FetchDescriptor<IntakeLog>())) ?? []   // tabela inteira
    await HealthKitService.shared.backfill(logs: allLogs)
    ...
}
```

`HealthKitService.swift:160-180`:

```swift
func backfill(logs: [IntakeLog]) async {
    for log in logs where log.source != "healthkit" {
        guard await !existsInHealthKit(logID: log.id) else { continue }   // 1 HKSampleQuery por log
        await save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
    }
}
```

Isso roda em `handleScenePhaseChange(.active)`, isto é, **a cada vez que o app volta ao primeiro plano**. Com 3.000 logs são 3.000 `HKSampleQuery` sequenciais (cada uma com IPC para o `healthd`) mais os `save` que faltarem. Na prática o app fica gastando bateria e tempo de IPC indefinidamente num trabalho que, depois da primeira passada, não tem nada a fazer.

**Correção:** uma query só, com todos os UUIDs, e um short-circuit persistido:

```swift
func backfill(logs: [IntakeLog]) async {
    guard isAuthorized else { return }
    let candidates = logs.filter { $0.source != "healthkit" }
    guard !candidates.isEmpty else { return }
    let existing = await existingExternalUUIDs(in: candidates.map(\.id))   // 1 query
    for log in candidates where !existing.contains(log.id.uuidString) {
        await save(volumeML: log.volumeML, timestamp: log.timestamp, logID: log.id)
    }
}
```

Melhor ainda: marcar no `IntakeLog` que a amostra já foi escrita (um `healthKitWrittenAt: Date?`), e passar ao `backfill` só `FetchDescriptor` com `healthKitWrittenAt == nil`.

### A-5 · `flushPending` varre seis tabelas inteiras a cada foreground

`HidrataPOC/Services/CloudKitSyncService.swift:307-335`:

```swift
if let logs = try? context.fetch(FetchDescriptor<IntakeLog>()) {
    for log in logs where log.syncStatus != .synced { await push(log) }
}
// ... idem NotificationEvent, UIInteractionEvent, SlotDecision, UserProfile, DailyGoal
```

Seis fetches sem predicado, e o filtro de `syncStatus` em Swift. Chamado em `setUpOnLaunch()` **e** em `handleScenePhaseChange(.active)` (`HidrataPOCApp.swift:50`, `:59`) — logo, duas vezes no launch. Os pushes são `await` em série: 50 registros pendentes = 50 round trips sequenciais.

**Correção:**

```swift
let pending = SyncStatus.synced.rawValue
let descriptor = FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.syncStatusRaw != pending })
```

e usar `modifyRecords(saving:deleting:savePolicy:atomically:)` em lotes de 300, como `push(_ goals: [DailyGoal])` (`:180-208`) já faz corretamente.

### A-6 · "Configurar lembretes" não abre nada

`HidrataPOC/Views/Profile/ProfileView.swift:223-251`:

```swift
private var remindersCard: some View {
    Button {
        Haptic.primary.play()
        showReminders = true        // ← nada observa isso
    } label: { /* "Configurar lembretes" / "O monstro te provoca quando você esquece de beber" */ }
    .buttonStyle(GradientProminentButtonStyle(cornerRadius: 20))
}
```

`showReminders` aparece apenas duas vezes no projeto inteiro: a declaração (`:16`) e essa atribuição. Não há `.sheet(isPresented: $showReminders)`, `.navigationDestination` nem nada. Comparar com os vizinhos `liveActivitiesRow` (`:279-282`) e `siriRow` (`:311-314`), que têm o `.sheet` logo depois do `.buttonStyle`.

O cartão é o maior e mais destacado da tela (o único com o gradiente de marca depois do cartão da meta), então um usuário que toca nele recebe um haptic e nada mais.

**Correção:** implementar a tela de lembretes (ou, se não houver escopo, remover o cartão em vez de deixar um botão morto na tela mais visitada das Configurações).

### A-7 · Botão "Gole" grava `tipoEntrada: "personalizado"`

`HidrataPOC/Views/Home/HomeView.swift:390-401`:

```swift
private func goleCard(height: CGFloat) -> some View {
    Button { logIntake(.custom(volumeML: 40), cardID: "gole") } label: {
        IntakeCardContent(icon: .symbol("drop.fill"), title: "Gole", subtitle: "40 mL", ...)
    }
}
```

`Constants.IntakePreset.gole` existe, vale 40 mL e tem `tipoEntrada == "gole"` (`Constants.swift:80`, `:89`), mas o cartão passa `.custom(volumeML: 40)`, cujo `tipoEntrada` é `"personalizado"` (`:90`). Como `IntakeLog.init` copia `preset.tipoEntrada` (`IntakeLog.swift:55`), todo gole registrado **pelo botão da Home** entra no dataset como "personalizado".

As outras quatro superfícies gravam `"gole"` corretamente: ação rápida da notificação (`NotificationDelegate.swift:72`), Siri (`SiriIntents.swift:44`), Control Center (`HydrationControlWidgets.swift:59` → `.matching(volumeML: 40)` → `.gole`) e Live Activity. Ou seja: a mesma ação de 40 mL recebe dois rótulos diferentes dependendo de onde foi registrada, o que torna `tipoEntrada` inutilizável como dimensão de análise e também bagunça a fala do mascote (`WaterHeaderView.swift:131` compara volume, então essa parte sobrevive).

**Correção:** `logIntake(.gole, cardID: "gole")`. Vale também um script de migração dos registros já gravados (`volumeML == 40 && tipoEntrada == "personalizado" && source == "app"`), ou pelo menos uma nota no `PIPELINE_README.md` sobre a janela afetada.

### A-8 · `adjustmentLocked` não sobrevive ao restore

`DailyGoal.adjustmentLocked` (`Models/DailyGoal.swift:24-29`) existe por um motivo bem documentado:

> WeatherKit keeps revising "today's forecast high" as the day goes on, and without a lock a later, different reading would silently replace a goal the user may have already met.

Mas o push omite o campo (`CloudKitSyncService.swift:182-190`):

```swift
record["userID"] = goal.userID
record["dayKey"] = goal.dayKey
record["baseGoalML"] = goal.baseGoalML
record["adjustmentML"] = goal.adjustmentML
record["atualizadoEm"] = goal.atualizadoEm
// adjustmentLocked ausente
```

e o restore também (`:491-511`): `applyDailyGoal` monta `DailyGoal(userID:dayKey:baseGoalML:adjustmentML:)`, cujo default é `adjustmentLocked: false`.

Consequência: depois de uma reinstalação ou num segundo aparelho, toda linha de `DailyGoal` volta destravada. Se o restore acontecer no mesmo dia, a próxima previsão (`HomeView.swift:118-121` → `DailyGoal.recordToday`) reescreve o ajuste de hoje — exatamente o cenário que o lock previne. E o dataset de pesquisa no CloudKit nunca registra se um ajuste era definitivo.

**Correção:** `record["adjustmentLocked"] = goal.adjustmentLocked ? 1 : 0` no push, e no `applyDailyGoal`:

```swift
let locked = (record["adjustmentLocked"] as? Int).map { $0 != 0 } ?? false
// existing.adjustmentLocked = existing.adjustmentLocked || locked   (nunca destravar)
```

Note que `push(_ goals:)` usa `savePolicy: .allKeys`, então o campo precisa estar presente ou será sobrescrito com nulo no servidor.

### A-9 · Peso e altura sem validação

`HidrataPOC/Views/Profile/ProfileFormView.swift:160-184`:

```swift
TextField("kg", text: $pesoText)
    .keyboardType(.decimalPad)
    .onChange(of: pesoText) { _, val in
        if let n = Self.parseDecimal(val) { pesoKg = n }   // qualquer Double
    }
```

e na confirmação (`:238-241`):

```swift
let finalIdade = Int(idadeText).map { max(10, min(120, $0)) } ?? idade   // idade: limitada
let finalPeso = Self.parseDecimal(pesoText) ?? pesoKg                   // peso: livre
let finalAltura = Self.parseDecimal(alturaText) ?? alturaCm             // altura: livre
```

Com `pesoKg = 0`, `WaterIntakeCalculator.recommend` (`:100-101`) dá `baselineL = 0`, `suggestedGoalML` retorna 0, e todo o app passa a mostrar "0 mL / 0 mL": `progress` é 0 por causa do `guard effectiveGoalML > 0` (`HomeView.swift:67`), o mascote fica no estágio 5 para sempre, o streak nunca conta (`metGoal` exige `goal > 0`), o widget mostra tanque vazio e `HydrationPlanner.idealDayCurve` retorna `nil`. Nada crasha — o app simplesmente deixa de funcionar, sem nenhuma mensagem.

No outro extremo, 500 kg produz ~21 L, cortado para o teto de 11 L (`dailyCeilingL`), uma meta de 11.000 mL apresentada como recomendação de saúde.

Há também um problema menor de UX: quando `parseDecimal` retorna `nil` (ex. "7,5,2"), o valor antigo é mantido silenciosamente, então o campo mostra um texto e o modelo guarda outro número.

**Correção:**

```swift
private static let pesoRange = 20.0...300.0
private static let alturaRange = 80.0...250.0

private var validationError: String? {
    guard let p = Self.parseDecimal(pesoText), Self.pesoRange.contains(p) else { return "Informe um peso entre 20 e 300 kg." }
    guard let a = Self.parseDecimal(alturaText), Self.alturaRange.contains(a) else { return "Informe uma altura entre 80 e 250 cm." }
    return nil
}
// Button(confirmLabel) { ... }.disabled(validationError != nil)
// + Text(validationError) no footer da seção
```

### A-10 · Fetch de localização sem timeout trava o clima para sempre

`HidrataPOC/Services/WeatherContextService.swift:148-158`:

```swift
private func fetchOneTimeLocation() async throws -> CLLocation {
    let status = locationManager.authorizationStatus
    guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw CLError(.denied) }
    return try await withCheckedThrowingContinuation { continuation in
        locationContinuation = continuation
        locationManager.requestLocation()      // sem timeout
    }
}
```

`requestLocation()` normalmente chama `didUpdateLocations` ou `didFailWithError`, mas há cenários reais em que nenhum dos dois chega em tempo útil (serviços de localização recém-ligados, indoor sem rede, device em modo de baixo consumo). Nesse caso a continuation fica pendurada e — mais grave — `resolveLocation` (`:126-142`) nunca limpa `inflightLocationTask`:

```swift
if let t = inflightLocationTask { return try await t.value }
```

Toda chamada subsequente a `currentContext()`/`temperatureAdjustmentContext()` fica aguardando essa mesma task para sempre. Os efeitos em cascata: o `.task` do `HomeView`, do `HistoricoView`, do `WaterHeaderView` e do `ProfileView` nunca completam; `NotificationScheduler.tick()` trava em `refreshCacheIfStale()` na primeira linha (`:469`), então nada de `armNextSlotIfClear`, captura de contexto, resolução de timeouts ou `touchIfNeeded` da Live Activity volta a rodar — o pipeline inteiro de notificações para silenciosamente até o app ser reiniciado.

**Correção:**

```swift
private func fetchOneTimeLocation(timeout: Duration = .seconds(10)) async throws -> CLLocation {
    // ... guard de autorização
    return try await withThrowingTaskGroup(of: CLLocation.self) { group in
        group.addTask { try await self.awaitLocationCallback() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw CLError(.locationUnknown)
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
```

limpando `locationContinuation` no cancelamento. Vale também registrar `logger.error` no `catch` de `temperatureAdjustmentContext` (`:95`), que hoje é um `catch { return nil }` mudo.

### A-11 · N+1 no restore do CloudKit

`HidrataPOC/Services/CloudKitSyncService.swift:458-468`:

```swift
private func applyIntakeLog(_ record: CKRecord, context: ModelContext) -> Bool {
    // ...
    if ((try? context.fetchCount(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0 { return false }
    let healthKitUUID = record["healthKitUUID"] as? String
    if let healthKitUUID,
       ((try? context.fetchCount(FetchDescriptor<IntakeLog>(predicate: #Predicate { $0.healthKitUUID == healthKitUUID }))) ?? 0) > 0 {
        return false
    }
```

Duas queries SQLite por registro, dentro do laço de `pull` (`:391-393`). Num restore completo (`logPredicate` sem `lastPull`, `:389`) com um ano de histórico, são ~6.000 queries encadeadas, na main actor, na primeira abertura do app depois de reinstalar — bem no momento em que o usuário está olhando a tela `ICloudRestoreView`.

**Correção:** carregar os conjuntos uma vez, antes do laço:

```swift
let existingIDs = Set((try? context.fetch(FetchDescriptor<IntakeLog>()))?.map(\.id) ?? [])
let existingHKUUIDs = Set((try? context.fetch(FetchDescriptor<IntakeLog>()))?.compactMap(\.healthKitUUID) ?? [])
```

(um fetch só, reutilizando o resultado) e passar os dois `Set` para `applyIntakeLog`, atualizando-os à medida que insere.

### A-12 · O `tick` de 60 segundos faz varreduras completas

`HidrataPOC/Services/NotificationScheduler.swift:468-483` roda a cada 60 s enquanto o app está em primeiro plano (`HidrataPOCApp.swift:93-100`) e a cada `BGAppRefreshTask`:

```swift
func tick(context: ModelContext) async {
    await WeatherContextService.shared.refreshCacheIfStale()   // pode ser rede + GPS
    await armNextSlotIfClear()                                 // decode JSON dos slots + queries ao UNUserNotificationCenter
    await captureImminentSlots(context: context)               // fetch de IntakeLog do usuário (sem limite)
    closePolicyDecisions(context: context)                     // fetch de SlotDecision + decode dos slots
    await resolvePendingDismissals(context: context)
    await resolveTimedOutEvents(context: context)              // fetch de NotificationEvent sem filtro de usuário
    await refreshPendingMascotIfNeeded()                       // outro fetch completo de IntakeLog + possível WeatherKit
    // + LiveActivityManager.touchIfNeeded → mais um fetch
}
```

Em particular, `refreshPendingMascotIfNeeded` → `currentHydrationState` (`:1043-1049`) carrega **todos** os logs do usuário e chama `effectiveGoalML` (`:1057-1070`), que pode disparar `temperatureAdjustmentContext()` (GPS + WeatherKit) se o ajuste do dia ainda não estiver travado. E `updateSlot` (`:1179-1184`) faz decode + encode do array de slots inteiro por slot alterado.

**Correção:** (a) predicado de data nos fetches de `IntakeLog` (só hoje importa para o mascote e para o déficit); (b) manter os `PendingSlot` em memória, persistindo só no fim do tick; (c) separar as cadências — o mascote e o clima não precisam de 60 s, enquanto `armNextSlotIfClear` sim.

### A-13 · `resumeWatching()` nunca é chamado

`HidrataPOC/Services/LiveActivityManager.swift:134-137`:

```swift
/// Re-attaches the dismissal watcher to an activity that survived an app relaunch.
func resumeWatching() {
    Activity<HydrationAttributes>.activities.forEach { watchForDismissal(id: $0.id) }
}
```

Nenhuma referência no projeto. O observador de `activityStateUpdates` só é instalado por `requestIfOverdue` (`:109`), `restartIfNearingLimit` (`:52`) e `touchIfNeeded` (`:91`). Como `touchIfNeeded` roda em cada `tick`, na prática o watcher acaba sendo reinstalado em até 60 s — mas o `watchForDismissal` só funciona se a atividade **ainda existir** quando a Task começa a observar (`:121-122`), e o descarte pelo usuário é instantâneo. Então, entre o relaunch e o primeiro tick, descartar o cartão da tela de bloqueio perde a variante island-only de vez, que é justamente o comportamento documentado em `:113-115`.

**Correção:** chamar `resumeWatching()` em `HidrataPOCApp.setUpOnLaunch()` (ou em `refreshLiveActivity()`), ou remover o método se o fallback por tick for considerado suficiente.

---

## 4. Código morto, pronto para remoção

Agrupado por arquivo. Tudo abaixo foi verificado por busca no projeto inteiro (incluindo `project.pbxproj`).

**Arquivos inteiros**
- `BubblePOC.swift` (43 linhas, raiz) — não está em nenhum alvo do `project.pbxproj`; chama `ShaderLibrary.bubble`, que não existe mais em `Shaders/Bubble.metal`. Não compilaria.
- `notification/NotificationService.swift` (35 linhas) e `notification/Info.plist` — a pasta é um `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:293`) referenciado apenas como filho de um grupo (`:404`), nunca em `fileSystemSynchronizedGroups` de um alvo. É o template do Xcode, que acrescenta `" [modified]"` ao título.
- `gulun.m4a` (raiz) — fonte não convertida; o app usa `HidrataPOC/Support/Sounds/gulun.caf`.

**`HidrataPOC/Support/AppTheme.swift`**
- `:239` — `Color.appAccentLight` (1 referência: a própria declaração)
- `:269-272` — `Color.appOnTrack` (1 referência)
- `:377` — `View.appCardBackground(cornerRadius:)` (1 referência)

**`HidrataPOC/Services/HealthKitService.swift`**
- `:248-250` — `resetSyncDate()` (1 referência)

**`HidrataPOC/Views/Home/HomeView.swift`**
- `:19` + `:128-137` + `:447-449` + `:492-495` — `pendingDeleteLog`, o `confirmationDialog` "Excluir este registro?", `isPresentingDeleteConfirm` e `deleteLog(_:)`: `pendingDeleteLog` nunca recebe um valor não-nil, então o fluxo é inalcançável. (A exclusão funcional vive em `DayDetailSheet.deleteIntake`.)
- `:24-25` + `:115` + `:460-463` — `weather`, `isLoadingWeather`, `loadWeather()` e o `.task` que a invoca: ambos os `@State` são escritos e nunca lidos. Além de morto, o `.task` custa um fetch de GPS + WeatherKit por aparição da Home.

**`HidrataPOC/Models/UserProfile.swift`**
- `:14` — `generoAutoDeclarado`: as únicas escritas são `= nil` (`ProfileView.swift:549`) e a passagem pelo CloudKit. `Genero` só tem `masculino`/`feminino`, então nenhuma tela pode produzir um valor.
- `:18` — `fusoHorario`: gravado no onboarding e sincronizado, mas nenhum cálculo de data no app o lê (tudo usa `Calendar.current`), e a edição de perfil não o atualiza. *Decisão de produto, não remoção automática* — o pipeline Python o usa (`dataset.py:88`), então removê-lo do app quebraria o `to_local` do treino.

**`HidrataPOC/Services/CloudKitSyncService.swift`**
- `:249` / `:38` — o parâmetro `recordType` de `delete(recordType:id:)` e o campo homônimo de `PendingDeletion`: usados só em log; `flushPendingDeletions` (`:267-282`) ignora o tipo.

**`Shaders/Bubble.metal`**
- `:65` — `static float fbm(float2 p)`, sinalizado pelo compilador (`-Wunused-function`).

**Debug compilado em release** (não é morto, mas não deveria estar no binário de produção)
- `HidrataPOC/Services/NotificationScheduler.swift:1098-1134` — `sendDebugNotification(after:)`, `sendDebugNotification(copy:after:)` e `sendRandomDebugCopy(after:)`. As chamadas em `ProfileView` estão sob `#if DEBUG`; as implementações não.

**Features mortas do modelo** (requer coordenação app ↔ pipeline)
- `busy` e `event_density`: `AppPolicyContextProvider.swift:45-46` e `NotificationEvent.swift:62-67` fixam `ocupadoNoMomento: false`/`densidadeEventosDia: 0` desde que o contexto de calendário foi removido. `PolicyFeatures.raw` (`PolicyParams.swift:103-105`) ainda as emite, e `ml/python/config.py:31` ainda as treina — duas colunas de variância zero no vetor de 14.

---

## 5. Plano de ação priorizado

**Fase 0 — correções de uma linha, retorno imediato** (meio dia)

1. **A-7** `logIntake(.gole, ...)` em `HomeView.swift:391` — para de corromper o dataset agora; cada dia de atraso é mais dado com rótulo errado.
2. **A-8** incluir `adjustmentLocked` no push/restore de `DailyGoal`.
3. **B-9** `import SwiftData` em `SheetLifecycleTracking.swift` (apaga um warning do build).
4. **A-13** chamar `resumeWatching()` no launch, ou remover.
5. **M-5** mover a gravação de `lastRefreshKey` para depois do sucesso em `PolicyStore.refreshFromCloudKit`.
6. **M-4** só gravar `lastSyncKey` quando a `HKSampleQuery` não falhar.
7. **M-6** tirar `remote-notification` e `processing` do `UIBackgroundModes`.

**Fase 1 — remoção de código morto** (meio dia, risco ~zero, reduz a superfície a manter)

8. Apagar `BubblePOC.swift`, `notification/`, `gulun.m4a`, `fbm` no Metal, as três cores/modificador de `AppTheme`, `resetSyncDate()`, o diálogo de exclusão inalcançável e os `@State` de clima da `HomeView` (**M-14, M-15, B-1..B-4, B-8, B-10**). Envolver o trio de debug do scheduler em `#if DEBUG` (**B-20**).

**Fase 2 — performance perceptível** (2–3 dias, é aqui que o app fica visivelmente mais rápido)

9. **A-1** mover `idealPlan` para `@State` + `.task` — o maior ganho por linha mudada de toda a lista.
10. **A-2** dar predicado aos sete `@Query`.
11. **A-3** pré-agregar os totais por dia e cachear o streak.
12. **M-8** `static let` para `Calendar`, `Locale` e os `DateFormatter` do Histórico.
13. **A-4** uma query só no `backfill` do HealthKit (ou marcar no `IntakeLog`).
14. **A-12** predicados e memoização no `tick`.

**Fase 3 — robustez** (2–3 dias)

15. **A-10** timeout no fetch de localização — hoje um GPS mudo congela todo o pipeline de notificações.
16. **A-5** e **A-11** predicados e lotes no `flushPending`/`pull`.
17. **M-12** backoff respeitando `retryAfterSeconds`.
18. **M-10** ordem do `expirationHandler` + `setTaskCompleted(success: false)`.
19. **M-11** tirar os `fatalError` do caminho de launch.
20. **M-2** um `save()` centralizado que loga; **M-1** trocar os `print()` por `Logger`.

**Fase 4 — UX e correção funcional** (3–5 dias)

21. **A-6** implementar (ou remover) "Configurar lembretes".
22. **A-9** validar peso e altura.
23. **M-3** separar autorização de leitura e de escrita no HealthKit.
24. **M-13** registrar N goles da Siri numa transação só.
25. **M-7** honrar `Reduzir Movimento`.

**Fase 5 — privacidade e conformidade** (precisa de decisão de produto; comece a discussão agora, em paralelo)

26. **C-1** decidir entre banco privado + sharing ou pseudonimização do push. É a mudança mais invasiva do relatório e a que mais depende de o que o projeto precisa do dataset — por isso vale decidir cedo e implementar depois.
27. **C-2** reescrever o texto de consentimento (pode ir antes do item 26; é independente e barato).
28. **C-3** tela "Meus dados" com exportar e apagar.

**Fase 6 — dívida de longo prazo**

29. **M-20** testes para `CloudKitSyncService` e `IntakeLogService.record`.
30. **M-16** decidir o destino de `busy`/`event_density` (app + pipeline juntos).
31. **M-17** lockfile do pipeline Python; **M-18** tirar o patch no `site-packages`.
32. **B-5..B-7, B-19** limpar `generoAutoDeclarado`, decidir `fusoHorario`, atualizar os comentários sobre `Genero` e o de `SLOT_HOURS`.
33. **M-19** decidir sobre localização.

---

## 6. O que está bom (manter)

Vale nomear explicitamente, porque é raro e porque uma refatoração descuidada destruiria:

- **Comentários que explicam o porquê, não o quê.** Praticamente toda decisão não óbvia tem um comentário que registra a alternativa descartada e a razão. Exemplos concretos do que isso salva: `ShareProgressView.swift:300-314` documenta três tentativas erradas antes de descobrir que o crash do eyedropper era profundidade de apresentação, não timing; `NotificationScheduler.swift:140-144` explica por que `requestGenerations` existe; `HistoricoData.generateMonth:30-33` registra que a versão anterior travava o arrasto. **Qualquer refatoração deve preservar esses comentários** — eles são a documentação de arquitetura real do projeto.
- **Paridade testada entre Swift e Python.** `ThompsonPolicyTests.matchesPythonReference` compara a implementação do device com vetores gerados pelo código de treino (`policy_parity_vectors.json`), e `ThompsonPolicy.swift:11-12` instrui a manter os dois em lockstep. É exatamente a proteção certa para um modelo portado à mão.
- **Fontes citadas nas constantes do domínio.** `WaterIntakeCalculator.swift:43-83` cita IOM 2004, ACSM e a tabela WBGT do U.S. Army, com nível de confiança por componente e um aviso para não "melhorar" os números sem atualizar as duas implementações. Isso é o que torna uma heurística de saúde auditável.
- **Fronteiras de concorrência bem pensadas.** `@MainActor` consistente nos serviços; `NotificationDelegate.swift:12-18` explica por que os callbacks são `@MainActor` e não `nonisolated` (com o modo de falha concreto: "Call must be made on main thread"); `BGTaskBox` justifica seu `@unchecked Sendable`; `WaterTankWidget.swift:41-43` explica cada `nonisolated(unsafe)`.
- **Deduplicação de trabalho concorrente.** `inflightEnsureTodayScheduledTask` (`NotificationScheduler.swift:133-138`), `inflightLocationTask` (`WeatherContextService.swift:33`) e `pullTask` (`CloudKitSyncService.swift:343`) resolvem corridas reais, cada um com o comentário dizendo qual bug concreto apareceria sem ele.
- **Imutabilidade do histórico por design.** `DailyGoal` + `DailyGoalResolver` garantem que editar a meta hoje não re-julga dias passados, com busca binária sobre `dayKey` ordenável como string e nove testes cobrindo os casos de borda (dia sem registro, dias antes do primeiro registro, meta subindo hoje sem quebrar a streak).
- **Separação entre matemática pura e persistência.** `HydrationMath`, `WaterIntakeCalculator`, `DailyGoalResolver`, `QuietHours`, `PolicyFeatures`, `NotificationScheduler.slotsToArm`/`decideSlotAction`/`selectVariant` são funções puras e `static`, deliberadamente testáveis sem SwiftData nem `UNNotification` — e são justamente as que têm os 59 testes.
- **Acessibilidade acima da média de um POC.** `touchTarget()` força os 44 pt do HIG sem alterar o layout; `PageDots` tem `accessibilityAdjustableAction` para trocar de página sem o gesto de arrasto; os botões dos minijogos têm `onAccessibilityPulse`; os comentários da paleta em `AppTheme.swift:234-299` registram as razões de contraste calculadas (5,0:1, 3,4:1, ≥4,5:1) por cor e por modo. O gap é só `reduceMotion` (M-7).
- **Nenhum segredo no repositório.** `.gitignore` cobre `*.pem`, `ml/data/`, `ml/out/`; `cloudkit_io.py` lê a chave de `CK_KEY_FILE`/`CK_KEY_ID` do ambiente; o histórico do git não tem nenhum arquivo de credencial. O `PIPELINE_README.md` ainda avisa explicitamente para manter o `eckey.pem` fora do repo.
- **Pipeline ML com separação de responsabilidades clara.** `config.py` centraliza o que o app tem de reproduzir, com `LEAKY_COLUMNS` nomeando explicitamente as colunas de desfecho que nunca podem ser features — uma proteção contra vazamento de rótulo que muitos projetos não têm.
