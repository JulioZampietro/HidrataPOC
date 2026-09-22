# HYDRATE-NP-01 — Notificações com Persona (variantes por contexto)

## 1. Contexto

Hoje toda notificação de lembrete sai com o mesmo texto fixo (`"Hora de beber água 💧"`
/ `"Um gole agora ajuda a manter sua meta do dia."`), montado em
`NotificationScheduler.scheduleSystemNotification(id:firesAt:)`. Esta spec troca isso
por 8 variantes de persona, escolhidas por contexto (clima, horário do dia, risco de
perder a sequência), e usa a infraestrutura que **já existe** —
`NotificationEvent.statusInteracao` / `resultouEmConsumo` / `tempoAteAgirMin` — para
te dizer depois qual variante converte melhor, por usuário. Não precisa de um sistema
de tracking novo: basta gravar **qual variante foi enviada** em cada
`NotificationEvent`, porque o resto do dado de efetividade (abriu? logou água depois?
em quanto tempo?) já é capturado automaticamente pelo pipeline existente
(`NotificationScheduler.recordQuickAction`/`resolveInteraction`,
`NotificationDelegate`).

## 2. Não-objetivos

- Nenhuma personalização adaptativa em runtime (bandit, "a variante que converteu
  mais pra esse usuário passa a ser priorizada"). Igual o README já declara para o
  app inteiro: "The app makes no predictions itself" — esta spec só **rotula** os
  dados; a otimização por variante é análise offline, depois.
- Nenhum record type novo no CloudKit — `NotificationEvent` ganha um campo, só isso.
- Não mexe nas ações rápidas da notificação (Gole/Copo/Garrafa/Soneca) nem na
  categoria (`HYDRATION_REMINDER`) — todas as variantes mantêm as mesmas ações.

## 3. Catálogo de variantes

| id | Título | Corpo | Gatilho |
|---|---|---|---|
| `hot_day` | Vai desidratar nesse calor? | Que calorão. Já estou de cadeira de praia esperando você desidratar. | Clima muito quente |
| `cold_day` | Esqueceu de beber água de novo? | Fazendo frio, né. Aposto que você nem vai lembrar de beber água hoje. | Clima muito frio |
| `mild_morning` | Não vai beber água? | Bom dia. Você já esqueceu de beber água e nem são 9h. | Manhã, clima ameno |
| `midday_neutral` | Continua sem beber água... | Faz tempo que você não bebe água. Eu percebi. | Meio-dia, clima ameno (1 de 3, sorteado) |
| `symptom_headache_midday` | Essa dor de cabeça não é à toa | Aquela dorzinha de cabeça do nada? Sou eu, de nada. | Meio-dia, clima ameno (1 de 3, sorteado) |
| `symptom_concentration_midday` | Não consegue focar? | Tá difícil de se concentrar aí? Isso é ponto pra mim. | Meio-dia, clima ameno (1 de 3, sorteado) |
| `streak_risk_evening` | Vai perder sua sequência? | Faltam poucas horas pra perder sua sequência pra uma pedra. | Fim do dia, streak em risco |
| `symptom_irritability_evening` | Reparou como está irritado hoje? | Aquela irritação com todo mundo hoje sem motivo? Talvez seja eu fazendo a festa. | Fim do dia, streak não em risco |
| `fallback_generic` | Hora de beber água 💧 | Um gole agora ajuda a manter sua meta do dia. | Rede de segurança — usado se o contexto nunca foi capturado a tempo (ver §7) |

Títulos das 6 sem exemplo seu foram escritos no mesmo tom das duas que você deu —
ajuste à vontade, é a parte mais fácil de trocar depois.

## 4. Decisões confirmadas com você

- **D-1 — Prioridade no fim do dia: streak em risco vence o clima.** Se ao mesmo
  tempo está muito quente/frio E o streak está em risco, sai `streak_risk_evening`.
- **D-2 — Meio-dia: sorteio uniforme entre as 3 variantes a cada envio.** Não é fixo
  por usuário — o mesmo usuário pode receber variantes diferentes em dias
  diferentes, o que dá mais dado pra comparar efetividade (inclusive dentro da mesma
  pessoa, não só entre pessoas).
- **D-3 — Títulos variam por variante**, no tom provocador/debochado que você já usa
  no corpo das mensagens (a persona "fala" tanto no título quanto no corpo).

## 5. Novas decisões técnicas (minhas, documentadas — sinalize se quiser mudar)

- **D-4 — Seleção acontece dentro de `captureContext(id:firesAt:context:)`**, não em
  `ensureTodayScheduled()`. É o único ponto que já busca clima fresco (~10 min antes
  do disparo, via `captureImminentSlots`/`tick()`) — escolher a variante em outro
  lugar significaria usar previsão de manhã pra decidir o texto de uma notificação
  de à noite.
- **D-5 — Clima "quente"/"frio" usa `WeatherContext.temperaturaC`** (leitura atual,
  não a máxima do dia usada em `TemperatureAdjustmentContext.todayMaxC` pra meta).
  Thresholds novos e ajustáveis:
  ```swift
  static let notificationHotThresholdC: Double = 30
  static let notificationColdThresholdC: Double = 15
  ```
  (mesma lógica de "ajuste pro clima da sua região" que já existe no comentário de
  `baselineMaxTempC`.)
- **D-6 — Horário do dia por hora do disparo, não por índice do slot**:
  ```swift
  static let notificationMorningEndHour = 11   // dispara antes disso => manhã
  static let notificationEveningStartHour = 19 // dispara a partir disso => fim de dia
  ```
  Entre os dois => meio-dia. Mais robusto que rotular pelo índice do slot (o
  primeiro slot do dia nem sempre cai de manhã, por causa do `earliestAllowed =
  max(windowStart, .now)` em `ensureTodayScheduled`).
- **D-7 — Reagendamento in-place, só se ainda não disparou.** A notificação já foi
  agendada (com o texto genérico `fallback_generic`) muitas horas antes, em
  `ensureTodayScheduled()`. Quando `captureContext` roda perto do horário, ele
  **substitui** o `UNNotificationRequest` pendente (mesmo `identifier`, mesma data
  de disparo, só título/corpo mudam) — `center.add(_:)` com o mesmo identifier
  sobrescreve o pendente. Se `captureContext` só roda depois que a notificação já
  disparou (fallback de último caso em `NotificationDelegate`), não tem o que
  reagendar — a notificação já foi vista com o texto genérico; o evento ainda grava
  qual variante *teria* sido escolhida, pra não perder o dado.

## 6. Modelo de dados

`HidrataPOC/Models/NotificationEvent.swift` ganha um campo:

```swift
/// Qual variante de copy foi (ou seria) mostrada — ver HYDRATE-NP-01. Default
/// aponta pro fallback genérico, pro mesmo motivo de `IntakeLog.customIntakeML` ter
/// default: migração leve de linhas antigas sem quebrar o schema.
var notificationVariant: String = NotificationVariant.fallbackGeneric.rawValue
```

Adicionar ao `init(...)` como parâmetro (sem default lá — todo `NotificationEvent`
novo deve vir de `captureContext`, que sempre sabe a variante).

`CloudKitSyncService.push(_ event: NotificationEvent)` ganha uma linha:
```swift
record["notificationVariant"] = event.notificationVariant
```

## 7. Algoritmo de seleção

Nova função pura em `HidrataPOC/Services/NotificationScheduler.swift` (fácil de
testar isolada, igual `HydrationMath`):

```swift
enum NotificationVariant: String {
    case hotDay = "hot_day"
    case coldDay = "cold_day"
    case mildMorning = "mild_morning"
    case middayNeutral = "midday_neutral"
    case symptomHeadacheMidday = "symptom_headache_midday"
    case symptomConcentrationMidday = "symptom_concentration_midday"
    case streakRiskEvening = "streak_risk_evening"
    case symptomIrritabilityEvening = "symptom_irritability_evening"
    case fallbackGeneric = "fallback_generic"

    var title: String { /* tabela da seção 3 */ }
    var body: String { /* tabela da seção 3 */ }
}

private func selectVariant(
    firesAt: Date,
    weather: WeatherContext?,
    profile: UserProfile,
    logs: [IntakeLog],
    calendar: Calendar = .current
) -> NotificationVariant {
    let hour = calendar.component(.hour, from: firesAt)
    let isEvening = hour >= Constants.notificationEveningStartHour
    let isMorning = hour < Constants.notificationMorningEndHour

    if isEvening, HydrationMath.isStreakAtRisk(logs, metaDiariaML: profile.metaDiariaML, calendar: calendar, firesAt: firesAt) {
        return .streakRiskEvening
    }
    if let temp = weather?.temperaturaC {
        if temp >= Constants.notificationHotThresholdC { return .hotDay }
        if temp <= Constants.notificationColdThresholdC { return .coldDay }
    }
    if isMorning { return .mildMorning }
    if isEvening { return .symptomIrritabilityEvening }
    return [.middayNeutral, .symptomHeadacheMidday, .symptomConcentrationMidday].randomElement()!
}
```

Novo helper puro em `HidrataPOC/Services/HydrationMath.swift`:

```swift
/// Há uma sequência ativa vinda de antes de hoje (`currentStreak` contando só até
/// ontem é > 0) e hoje ainda não bateu a meta — ou seja, ela quebra se o dia acabar
/// assim. Usa `firesAt` (não `.now`) pra ser puro e testável com qualquer horário.
static func isStreakAtRisk(_ logs: [IntakeLog], metaDiariaML: Int, calendar: Calendar = .current, firesAt: Date) -> Bool {
    guard metaDiariaML > 0 else { return false }
    guard totalML(logs, on: firesAt, calendar: calendar) < metaDiariaML else { return false }
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: firesAt)) else { return false }
    return currentStreak(logs, metaDiariaML: metaDiariaML, calendar: calendar, now: yesterday) > 0
}
```

## 8. Fases de implementação

### Fase 1 — Modelo e sync
1.1. Adicionar `notificationVariant` a `NotificationEvent` (§6) e ao `init`.
1.2. Atualizar `CloudKitSyncService.push(_ event: NotificationEvent)`.
1.3. **Critério de aceite:** compila; schema existente não quebra (campo tem default).

### Fase 2 — Constantes e catálogo
2.1. Adicionar `notificationHotThresholdC`, `notificationColdThresholdC`,
     `notificationMorningEndHour`, `notificationEveningStartHour` em
     `Constants.swift`.
2.2. Criar `HidrataPOC/Support/NotificationVariant.swift` com o enum completo (§7) e
     as 9 combinações de título/corpo da tabela da seção 3.
2.3. **Critério de aceite:** compila isolado, sem call sites ainda.

### Fase 3 — Seleção + streak helper
3.1. Adicionar `HydrationMath.isStreakAtRisk(...)` (§7).
3.2. (Opcional, recomendado) Testes em `HidrataPOCTests/` cobrindo `selectVariant`
     pros 9 casos da tabela — são funções puras, dá pra testar sem SwiftData de
     verdade, só passando arrays de `IntakeLog` em memória.
3.3. Adicionar `selectVariant(...)` privada em `NotificationScheduler`.

### Fase 4 — Reagendamento em `captureContext`
4.1. Refatorar `scheduleSystemNotification(id:firesAt:)` para
     `scheduleSystemNotification(id:firesAt:title:body:)`, com os dois call sites
     existentes (`ensureTodayScheduled`, `scheduleSnoozeSlot`) passando
     `NotificationVariant.fallbackGeneric.title/body` — comportamento hoje não muda
     nesses dois pontos.
4.2. Em `captureContext(id:firesAt:context:)`, depois de buscar `weather` e `logs`
     (já existe esse código pra montar o `NotificationEvent`): chamar
     `selectVariant(...)`, passar o resultado pro `NotificationEvent(...)`, e — só
     se `firesAt > .now` — chamar `scheduleSystemNotification(id:firesAt:title:
     variant.title, body: variant.body)` de novo com o mesmo `id`, substituindo o
     pendente.
4.3. **Critério de aceite:** agendar o dia, adiantar o relógio do simulador pra
     dentro da janela de captura (`captureLeadMinutes = 10`) de um slot, confirmar
     no Xcode (`po` na fila de notificações pendentes, ou só esperar disparar) que o
     texto mudou do genérico pra variante escolhida.

### Fase 5 — Verificação
5.1. Simular os 6 cenários principais manualmente (mockar `WeatherContext` e
     `IntakeLog`s no preview/teste, não precisa esperar clima real): dia quente,
     dia frio, manhã amena, meio-dia ameno (rodar 10x pra ver os 3 sortearem), fim
     de dia com streak em risco, fim de dia sem streak em risco.
5.2. Confirmar que `NotificationEvent.notificationVariant` gravado bate com a
     variante que apareceu na notificação de verdade.
5.3. Confirmar que as ações rápidas (Gole/Copo/Garrafa/Soneca) continuam
     funcionando em notificações com qualquer variante.

## 9. Como isso te diz "qual notificação é melhor pra cada usuário" (depois)

Sem código novo de análise agora — só uma nota de como consultar isso quando tiver
volume de dado, já que os campos que importam já existem em `NotificationEvent`:

- **Taxa de conversão por variante:** agrupar por `notificationVariant`, calcular
  `% resultouEmConsumo == true`.
- **Por usuário:** agrupar por `userID` + `notificationVariant` — revela se a mesma
  pessoa reage melhor a `symptom_headache_midday` do que a `midday_neutral`, por
  exemplo (é exatamente pra isso que o sorteio uniforme da Decisão D-2 existe: sem
  variedade dentro do mesmo usuário, essa comparação não dá pra fazer).
- **Velocidade de reação:** `tempoAteAgirMin` médio por variante — uma variante pode
  converter no mesmo total, mas mais rápido.

## 10. Perguntas em aberto (não bloqueiam implementação)

- Thresholds de 30°C/15°C são um chute razoável pro clima de Campinas — ajuste
  depois de ver leituras reais em `temperaturaC` por uma semana.
- Os 6 títulos que eu escrevi (tudo exceto os 2 que você deu de exemplo) são um
  primeiro rascunho no seu tom — troque livremente, é só texto, não afeta a lógica.
