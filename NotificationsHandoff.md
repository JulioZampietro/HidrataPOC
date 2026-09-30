# Notifications: current logic, reported bugs, and fix plan

Hand-off for the agent implementing the fixes. Part 1 describes behavior that **must not change** (copy, variant selection rules, fixed hours). Parts 2–4 describe the bugs, their causes, and the recommended fixes. Causes for bugs 1–3 come from reading the code; bug 4's cause is **unconfirmed** (see its section). No fix has been implemented yet.

Key files:
- `HidrataPOC/Services/NotificationScheduler.swift` — scheduling, context capture, blocking, mascot refresh
- `HidrataPOC/Services/NotificationDelegate.swift` — handles taps, quick actions, snooze, dismiss
- `HidrataPOC/Support/NotificationVariant.swift` — all copy
- `HidrataPOC/Support/Constants.swift` — hours, thresholds, timings
- `HidrataPOC/Services/BackgroundRefreshService.swift`, `HidrataPOC/App/HidrataPOCApp.swift` — tick drivers
- `HidrataPOC/Services/PersistenceController.swift` — SwiftData container (App Group)
- `HidrataPOCTests/NotificationVariantSelectionTests.swift` — existing tests for variant selection

---

## Part 1 — Current logic (do not change)

All notification text comes from `NotificationVariant`. The variant is chosen by `NotificationScheduler.selectVariant(...)`. The only place a `UNMutableNotificationContent` is built is `scheduleSystemNotification`. The mascot avatar changes with goal progress; the text does not.

### When notifications are scheduled
- **Fixed slots:** 8h, 10h, 12h, 14h, 16h, 18h, 20h, 22h (`Constants.notificationFixedHours`). Only slots still in the future are scheduled.
- **Snooze:** the "Lembrar mais tarde" action adds one extra slot 15 minutes out, with a variant chosen by the same rules.
- **Debug:** `sendDebugNotification` fires a throwaway "Teste de notificação" with no category or `eventID`, so it never creates a real event.

### Variant selection (first match wins)

| # | Condition | Variant |
|---|---|---|
| 1 | Fires at hour >= 19 **and** streak at risk | `streak_risk_evening` |
| 2 | Temperature >= 30°C | `hot_day` |
| 3 | Temperature <= 15°C | `cold_day` |
| 4 | Fires at hour < 9 | `mild_morning` |
| 5 | Fires at hour >= 19 | `symptom_irritability_evening` |
| 6 | Otherwise (midday) | Random of `midday_neutral`, `symptom_headache_midday`, `symptom_concentration_midday` |

- "Streak at risk" = `HydrationMath.isStreakAtRisk`: today's intake is below goal and the streak was > 0 as of yesterday.
- Temperature comes from WeatherKit. If unavailable, rules 2–3 are skipped.
- A re-pick with fresher context passes `keeping:` so an already-armed midday variant is not re-rolled.
- `fallback_generic` ("Hora de beber água 💧") is meant only for "no profile yet". It currently also appears via push-back, which is bug 2.

### Copy (pt-BR)

| Variant | Title | Body |
|---|---|---|
| hot_day | Vai desidratar nesse calor? | Que calorão. Já estou de cadeira de praia esperando você desidratar. |
| cold_day | Esqueceu de beber água de novo? | Fazendo frio, né. Aposto que você nem vai lembrar de beber água hoje. |
| mild_morning | Não vai beber água? | Bom dia. Você já esqueceu de beber água e nem são 9h. |
| midday_neutral | Continua sem beber água... | Faz tempo que você não bebe água. Eu percebi. |
| symptom_headache_midday | Essa dor de cabeça não é à toa | Aquela dorzinha de cabeça do nada? Sou eu, de nada. |
| symptom_concentration_midday | Não consegue focar? | Tá difícil de se concentrar aí? Isso é ponto pra mim. |
| streak_risk_evening | Vai perder sua sequência? | Faltam poucas horas pra perder sua sequência pra uma pedra. |
| symptom_irritability_evening | Reparou como está irritado hoje? | Aquela irritação com todo mundo hoje sem motivo? Talvez seja eu fazendo a festa. |
| fallback_generic | Hora de beber água 💧 | Um gole agora ajuda a manter sua meta do dia. |

### Lifecycle of a slot
1. **Scheduling.** `ensureTodayScheduled()` runs at launch and on every scene `.active`. On the first call of a day it creates a `PendingSlot` (UserDefaults JSON) per remaining fixed hour. It arms a system notification for each with a variant picked from the weather and intake at that moment. The day is then recorded in `scheduledDayKey`. Concurrent calls are de-duplicated with `inflightEnsureTodayScheduledTask`.
2. **Capture (`tick`).** Every 60s while foregrounded, and opportunistically from `BGAppRefreshTask` (earliest 15 min apart). For each uncaptured slot within `captureLeadMinutes` (10) of firing, or already past, `captureImminentSlots` runs. If nothing blocks it, it calls `captureContext`, which creates the `NotificationEvent` (weather, calendar, deficit, variant), re-picks the variant with fresher data, and re-arms the same request id in place if it has not fired.
3. **Blocking.** If any *other* hydration-category notification is still in `deliveredNotifications()` (unread and undismissed), the slot is held back: `pushBackPendingSlot` re-arms it `notificationBlockedRetryMinutes` (3) from now. After `notificationBlockedGiveUpMinutes` (15) blocked, the pending request is cancelled and the event is recorded as silently missed.
4. **Overdue.** A slot whose time has passed and that the system never delivered is force-delivered about 2s later with a fresh pick.
5. **Interaction.** `NotificationDelegate.didReceive` captures context if no event exists yet, then records the action: glass, bottle and gole (quick-log intake plus `aberta`), snooze (`soneca` plus a new slot), dismiss (`ignorada`, needs `.customDismissAction`), default tap (`aberta`).
6. **Timeout.** `resolveTimedOutEvents` marks events with no status after `notificationResponseWindowMinutes` (10) as `ignorada`.
7. **Mascot refresh.** `refreshPendingMascotIfNeeded` re-renders pending requests' avatars when the day's mascot changes. It preserves the id, trigger, title and body.

---

## Part 2 — Reported bugs and root causes

### Bug 1: multiple notifications at once, repeatedly, not at 8h/10h/…
**Cause:** the blocking logic, `captureImminentSlots` and `pushBackPendingSlot`.
- A slot only becomes `captured` when a tick reaches it. If the app wasn't open near 8h, the slot stays uncaptured even though iOS delivered the notification on time.
- On the next app open, every earlier uncaptured slot is evaluated. The other slots' delivered, unread notifications count as "outstanding", because `hasOutstandingHydrationNotification` excludes only the slot's own id. All of them are considered blocked.
- Each blocked slot is re-armed for now + 3 min **under the same identifier it was already delivered with**. This re-fires reminders the user already received.
- Several re-armed at the same instant fire together. Each 60s tick slides them another 3 min out, so the burst lands once the app is backgrounded.
- `savePendingSlots` keeps slots for 24h, so an unread pile-up from yesterday makes this worse.
- Secondary race: `refreshPendingMascotIfNeeded` re-adds pending requests with a `firesAt` read before several `await`s (`donate`). It can overwrite a concurrent push-back, or resurrect a request that was just cancelled.

### Bug 2: always the generic text, at random times
**Cause:** `pushBackPendingSlot` falls back to `.fallbackGeneric` when `slot.variant` is nil.
- `PendingSlot.variant` was added later and is optional. Slots persisted by an older build decode with nil.
- Notifications an older build already queued with the system can also carry the old generic copy and old (semi-random) times. This is unverified; it fits users who updated.
- Push-backs are also what produce the random times, which explains why the two symptoms appear together.
- `captureContext` returns nil (variant unchanged) when an event already exists, so a nil variant is never repaired.

### Bug 3: notifications still arrive despite unanswered ones
**Cause:** suppression is app-side only.
- iOS delivers every queued request whether or not the app runs.
- The block can act only inside the tick window (10 min before the slot). Background refresh is opportunistic and often absent.
- Even when it acts, it only delays the slot by 3 min; it never cancels it.
- After 15 min the block is dropped.
- Users who rarely open the app never see any suppression.

### Bug 4: crash when dismissing a notification
**Cause not confirmed. Get crash logs first** (Xcode Organizer or TestFlight crash reports). Check whether the exception is a watchdog kill (`0x8badf00d`) or a trap in `PersistenceController`.
Dismiss is special: `.customDismissAction` wakes the app in the **background**, often from the lock screen. Two candidates:
1. **Watchdog or time limit.** `didReceive` awaits `handle`, which awaits `captureContext` when no event exists. That does location (`requestLocation`), WeatherKit, EventKit and CloudKit pushes in sequence. Background launch time is short, and location/WeatherKit may stall in the background.
2. **`fatalError` in `PersistenceController.container`.** On a locked device the background launch may be unable to open the SQLite store in the App Group container (data protection), or the App Group container may be unavailable. It crashes the whole process.

---

## Part 3 — Fix plan

Keep the variant rules and copy from Part 1 exactly as they are.

### Fix for bugs 1 and 3: rework the blocking mechanism
1. **Never push back a slot that was already delivered.** In `captureImminentSlots`, check `isAlreadyDelivered(id)` (and/or `firesAt <= now`) *before* the outstanding check. If delivered, capture without forcing delivery, mark `captured = true`, and `continue`. Never re-arm a delivered request.
2. **Only apply blocking to slots that are still pending.** A slot that is genuinely in the future and pending can be delayed or skipped. Slots in the past are only captured.
3. **Redefine "outstanding".** Ignore delivered notifications older than `notificationBlockedGiveUpMinutes`, and ignore ones from a previous day. Today an unread notification from yesterday blocks forever. This is a product decision; the recommendation is that old unread reminders stop counting after the existing give-up window.
4. **Push back at most once per slot, or skip instead of delaying.** Don't re-arm every 60s tick. Store `retryAt` in the slot (derive it from `firstBlockedAt`) and only re-arm if the pending trigger is earlier than `retryAt`. Preferred: while blocked, **cancel** the pending request (`removePendingNotificationRequests`) and record the event as suppressed. This matches "don't send while one is unanswered" and stops slots colliding.
5. **Make scheduling idempotent and serialized.** Route all `center.add` / remove / refresh calls through one path (a private actor or a serial queue of operations), and have `refreshPendingMascotIfNeeded` re-read the request right before re-adding. Skip ids touched since it read the list. This removes the resurrection race.
6. **Be honest about the limit.** Suppression is only possible while the app runs. To improve coverage for users who rarely open it, two options:
   - Cap how many reminders can pile up: use one `threadIdentifier` per day, and/or remove older delivered hydration notifications when a new one is presented (`removeDeliveredNotifications`), so a stack of unread reminders never forms.
   - Accept the app-running limitation and document it.
   A `UNNotificationServiceExtension` does **not** help: it only mutates remote pushes, never local ones. The `notification/` target is still the Xcode template. It appends " [modified]" to titles, and it is not embedded in the app target. Delete it or leave it unembedded, but don't rely on it.
7. **Tests.** Add tests around `captureImminentSlots`'s decision (extract it into a pure function): delivered slots are never re-armed, overlapping blocked slots never share a fire time, and stale delivered notifications don't block.

### Fix for bug 2: variants can never be nil at re-arm time
1. **Never use `.fallbackGeneric` as a push-back copy.** When `slot.variant` is nil, resolve it with `selectVariant(...)` (via `provisionalVariant`). Use `.fallbackGeneric` only when there is no profile.
2. **Migrate persisted slots.** When loading slots, backfill any nil variant using `selectVariant`, then save. Also handle `NotificationVariant(rawValue:)` failing.
3. **Clean up old-build notifications once.** Store a schema/version key in UserDefaults. On first launch of this build (or any time it changes), remove all pending hydration requests and re-schedule from scratch. Pre-existing requests with old copy and random times then disappear.
4. **Assertion or log.** Log a warning if the generic variant is ever armed while a profile exists, to catch regressions.

### Fix for bug 4: make the dismiss path fast and non-fatal
1. **Confirm the crash type** first (Part 2, bug 4).
2. **Keep the dismiss handler minimal.** For `UNNotificationDismissActionIdentifier`, don't run the slow `captureContext` path (no location, WeatherKit, EventKit, or awaiting CloudKit). Options:
   - Use only cached weather (`WeatherContextService.cachedContext`) and skip calendar/network, then push to CloudKit in a detached task (or defer it to `flushPending` on the next foreground).
   - Or persist a lightweight "dismissed event IDs" list in UserDefaults and resolve it on the next foreground.
   Either way, `didReceive` should return quickly.
3. **Remove the `fatalError` risk in `PersistenceController`.**
   - Replace `fatalError` with a recoverable failure: return an optional container or retry after unlock. Then `didReceive` and BG tasks can no-op, and persist the pending action for later, instead of crashing.
   - Set the app group / store's data protection to `completeUntilFirstUserAuthentication` (entitlement `com.apple.developer.default-data-protection` on the app and widget targets), so the store is readable when a background launch happens on a locked device.
4. **Timeouts.** Wrap any remaining awaited work in the handler in a short timeout.

---

## Part 4 — No slots on days the app isn't opened

**Problem:** `ensureTodayScheduled()` schedules only today, and only when the app runs. `scheduledDayKey` then blocks any further scheduling for the day. A user who doesn't open the app on a given day gets no reminders. There is also a related gap: if scheduling runs while notification permission is denied, `center.add` fails silently, yet the day is still marked scheduled.

**Recommended fix: a rolling window, scheduled ahead.**
1. **Schedule several days ahead.** Keep the next N days scheduled (e.g. 3 days x 8 slots = 24, plus snooze slots). iOS allows at most 64 pending local notifications per app, so keep the total well under 64. Rebuild or extend the window at every launch, at scene `.active`, and from the background refresh task.
2. **Replace `scheduledDayKey` with idempotent per-slot creation.** Give each slot a deterministic key, `(calendar day, hour)`. On each run, for every day in the window and every fixed hour, create a slot only if none with that key exists and it is in the future. This also makes duplicate slots impossible, and it can replace the in-flight task de-duplication in `ensureTodayScheduled`.
3. **Copy for future days.**
   - Today's slots keep the current logic (weather plus intake).
   - For future days you can't know weather or intake. Run `selectVariant` with `weather = nil`, and the intake and streak from the data available. That yields time-of-day variants (`mild_morning`, `middayNeutral`/random, `symptomIrritabilityEvening`).
   - The existing capture pass, when the app does run, refines the copy near the fire time as it does today.
   - `streak_risk_evening` for a future day can only be estimated. Leaving it to the capture pass is fine.
4. **Check authorization before marking anything as scheduled.** Read `center.notificationSettings().authorizationStatus`. If not `.authorized` (or provisional), don't record success, and re-run scheduling when permission is later granted (e.g. after `PermissionsCoordinator.requestAll()`).
5. **Handle time zone and date changes.** Rebuild the window on `NSSystemTimeZoneDidChange` and on significant date changes.
6. **Stale slots.** Keep the existing pruning (`savePendingSlots` drops slots older than 24h). Do the same for delivered-but-uncaptured slots after fix 1 handles them.
7. **Dataset note.** When the app never runs, no `NotificationEvent` is captured before the notification fires. That is true today as well; the delegate's fallback capture handles interactions. Mention it in the data docs rather than trying to fix it.

---

## Suggested order of work
1. Get crash logs for bug 4 and decide its fix.
2. Bug 2, migration and variant backfill (small, low risk, and clears old-build pending requests).
3. Bugs 1 and 3, blocking rework and idempotent scheduling.
4. Part 4, rolling window (reuses the idempotent per-slot creation from step 3).
5. Bug 4, once the cause is confirmed. The minimal dismiss handler and the `PersistenceController` `fatalError` change can go earlier if desired.

Verification: unit tests for the pure decision logic. On a device, test with several unread notifications stacked while opening the app. Also test with the app force-quit for a full day. Test a dismiss from the lock screen with the device locked.
