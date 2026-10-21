# HidrataPOC — reminder timing model

This repository decides, for each user and each reminder slot, whether to send a notification. The goal is to send when the user is most likely to log water within 10 minutes. It learns each user's patterns over time and never sends between 22:00 and 08:00.

## How it works

There are two layers, and the second one lives on the phone.

**Population prior (Python, offline).** A hierarchical Bayesian logistic regression is fitted across all users. It answers two questions: how context (time of day, weather, calendar, hydration deficit) affects the chance of drinking after a reminder, and how much users differ from one another. The fit is exported as `policy_params.json`. That file holds the feature standardization, a prior mean and variance for every coefficient, and the policy settings. It is published as a CloudKit public record that the app downloads.

**Per-user bandit (Swift, on device).** Each phone keeps its own posterior over the same coefficients. It starts from the population prior and is updated after every slot whose 10-minute window has closed. Slots are decided by Thompson sampling, and every decision is logged to `SlotDecision` with the probability the policy had of making it. That logged probability is what makes later analysis valid (off-policy evaluation) and lets the population model be refit on unbiased data.

The model behind both layers is

    P(intake within 10 min | context x, action a) = sigmoid(w · [x, a·x])

The first block of `w` is the user's natural tendency to drink in that context. The second block is the extra effect of a reminder. With `objective = "response"`, the policy sends when the sampled P(intake | send) exceeds `lambda`. With `"uplift"`, it sends only when the reminder adds at least `lambda` over what the user would have done anyway.

## Phases

**Phase 0 (now).** The app sends at every fixed slot, so `NotificationEvent` already observes the response at every hour. That makes it unbiased data for the response objective. Use it with `evaluate.py` to compare the logistic baseline, LightGBM and the hierarchical model. Then build the first prior with `--source events`.

**Phase 1.** Ship the bandit with that prior. `SlotDecision` rows start accumulating, including skips. Skips are the only source of "would they have drunk anyway?" data.

**Phase 2 (repeat monthly, or when the user count grows a lot).** Refit the prior with `--source decisions`, which estimates the send effect directly from logged sends and skips. Check it with `ope.py` and the convergence diagnostics, publish it, and every device replays its own history on top of the new prior.

## Python

    cd python
    pip install -r requirements.txt

    # dry run on synthetic data shaped like the CloudKit tables
    python simulate.py --out data/sim
    python evaluate.py --data data/sim --hier
    python build_prior.py --data data/sim --source events --out out
    python simulate.py --out data/sim_bandit --seed 11 --bandit-params out/policy_params.json
    python ope.py --data data/sim_bandit --params out/policy_params.json
    python check_adaptation.py --params out/policy_params.json

    # real data
    export CK_KEY_ID=...  CK_KEY_FILE=eckey.pem
    python cloudkit_io.py export --env production --out data/export
    python evaluate.py --data data/export --hier
    python build_prior.py --data data/export --source events --out out
    python cloudkit_io.py publish --env production --params out/policy_params.json

| File | Purpose |
|---|---|
| `config.py` | Slots, quiet hours, feature list, forgetting rate |
| `dataset.py` | CloudKit tables → features; leak-free user history; standardization spec exported to the app |
| `models.py` | Logistic baseline, LightGBM (+ isotonic calibration), hierarchical model (bambi/PyMC) |
| `evaluate.py` | Time-split and new-user cross-validation: log loss, Brier, AUC, calibration, top-3 slot hit rate |
| `build_prior.py` | Fits the population model, writes `policy_params.json` and parity fixtures for the Swift tests |
| `policy.py` | Reference implementation of the on-device policy |
| `ope.py` | IPS / SNIPS / doubly-robust value of candidate policies from `SlotDecision` logs |
| `simulate.py`, `check_adaptation.py` | Synthetic users with known ground truth; personalization and drift test |
| `cloudkit_io.py` | Export from and publish to the public database via a server-to-server key |

### Fitting the population model

The hierarchical fit is the slow step. `build_prior.py` checks convergence after every fit and refuses to write `policy_params.json` unless all four checks pass: no divergent transitions, under 5% of iterations at maximum tree depth, r-hat at most 1.01, and bulk ESS of at least 400 for every population coefficient and between-user SD. The results are stored in the params under `fitDiagnostics`, so every published prior carries its own audit trail. Use `--force` only for dry runs.

The defaults (4 chains × 1000 draws) are meant for a machine with at least 4 cores. On the synthetic data (40 users, 8,400 decisions), the phase-2 fit passed with 2 chains × 1200 draws in about 3 minutes on a single CPU core. A 2 × 800 run failed the ESS check (304), which is the gate doing its job. `--max-users 15` gives a quick dry run, and `--sampler nutpie` is available if installed.

**Why the phase-2 fit uses a different parameterization.** Written as `[x, send·x]`, the model makes every coefficient on sent rows identifiable only as a sum with its partner. The 15 resulting strongly correlated pairs made NUTS hit maximum tree depth on every iteration; it could not finish even a 15-user subset in five minutes. The fit therefore uses separate skip and send blocks (columns `f_k = f·skip`, `f_s = f·send`) with no shared columns. That is the same model, and the 15-user subset then took 15 seconds with no divergences. `build_prior.py` converts the result back to the device layout, computing send minus skip draw by draw so the posterior covariance is kept.

**What to expect from the estimates.** The "natural drinking" (skip) block is estimated from rare events: un-prompted logs inside a 10-minute window happen about 5% of the time. Its coefficients are therefore noisy, and the send-effect block is much better determined. On the synthetic data, the policy implied by the refitted prior earned 0.079 true reward per decision against 0.053 for the bootstrap prior.

**Reading `ope.py`.** IPS and SNIPS ranked the policies correctly in simulation. The doubly-robust estimate came out consistently low (0.061 against a true 0.079), because the LightGBM reward model is fitted on biased logs. Treat IPS/SNIPS together with the effective sample size (ESS) as the primary numbers, and DR as a cross-check.

## CloudKit setup

**Server-to-server key.** Generate a key with `openssl ecparam -name prime256v1 -genkey -noout -out eckey.pem` and print its public half with `openssl ec -in eckey.pem -pubout`. Paste that public key in CloudKit Console under Tokens & Keys to get the key ID. Keep `eckey.pem` out of the repository.

**Indexes.** Export queries list every record of a type, so each record type needs a QUERYABLE index on `recordName`.

**Schema.** `SlotDecision` and `PolicyParams` are new record types. Create them in Development (running the app once, and publishing once, does that), then deploy the schema to Production. TestFlight builds use Production, so a type that only exists in Development will make pushes fail for testers.

**Security roles (please check this one).** By default, public-database record types are readable by everyone (the World role). In practice that means any user of the app can read other users' weight, age and intake history. That is personal and health-adjacent data, which matters under LGPD. Remove World read from `UserProfile`, `IntakeLog`, `NotificationEvent`, `UIInteractionEvent` and `SlotDecision` (Creator keeps read/write). Keep World read on `PolicyParams`, which every device must download, and give write access to that type only to its creator (the server key). After changing roles, rerun the export to confirm the server key can still read everything.

## iOS integration

The files in `ios/` are meant to be added to the app target. The tests file goes to the test target.

1. Add `SlotDecision.self` to the SwiftData schema (same App Group store) and to `CloudKitSyncService`'s push and `flushPending`, using `makeCKRecord()`.
2. Bundle `policy_params.json` from the latest `build_prior.py` run so the first launch works offline. Add it and `policy_parity_vectors.json` to the test target too, and run `ThompsonPolicyTests` after every change on either side.
3. Implement `PolicyContextProvider` with the services that already fill `NotificationEvent`: weather forecast for the slot time, `CalendarContext` evaluated at the slot time, `HydrationMath` for deficit and last intake, and `UserProfile`. Reusing the same helpers keeps feature meanings identical to the training data.
4. Call `PolicyCoordinator.runCycle()` at app launch and foreground, after an intake is logged, from notification responses, and from a `BGAppRefreshTask` scheduled for the morning. It downloads new params, learns from finished slots, and decides every undecided slot through tomorrow's 08:00.
5. The scheduler arms exactly the returned send decisions, choosing the copy variant as today and writing it to `notificationVariant`. A decision is final. If an existing rule (`dropUnsent` or similar) wants to suppress a slot, it must do so before the policy is asked; dropping a "send" afterwards would make the logged action wrong.
6. Only run the policy while notification permission is granted.

Slots are decided for the rest of the day when the app runs, because iOS gives no chance to run code at each slot otherwise. The features stored with each decision are the ones actually used at decision time, so training and serving stay consistent. One small mismatch exists only in phase 1: the bootstrap prior learned from features captured at send time. It disappears after the first `--source decisions` refit.

## Quiet hours (22:00–08:00)

The quiet window is `[22:00, 08:00)` in the device's local time, so the 08:00 slot stays and the 22:00 slot is gone. The window is defined once in `config.py` (`QUIET_START_MIN`, `QUIET_END_MIN`), exported in the params, and enforced at four independent points:

- The candidate slot list sent to devices (`slotHours`) is 08:00–20:00.
- `ThompsonPolicy.decide` returns nil for a quiet slot, so nothing is sent and nothing is logged.
- `PolicyCoordinator` checks `QuietHours.allows` before deciding and before returning anything to arm.
- `QuietHours.removePendingQuietRequests` deletes any pending request that would fire in the window. This cleans up 22:00 reminders armed by older builds and catches any other code path.

`QuietHours.allows` falls back to 22:00–08:00 before any params exist. Remove 22 from the app's own fixed slot list as well, and route every notification request through `QuietHours.allows`. `ThompsonPolicyTests` asserts the boundaries (07:59 quiet, 08:00 allowed, 21:59 allowed, 22:00 quiet) and that the policy never decides inside the window.

Historical 22:00 reminders stay in the training data. They help estimate the evening part of each user's daily curve; the policy simply never acts there.

## Adapting to each user over time

**Personal posterior.** Every resolved slot updates the user's own coefficients, so the policy learns, for example, that this user ignores 08:00 reminders but reliably responds at 14:00.

**Two peaks per day.** Time of day is encoded with 24-hour and 12-hour harmonics, so a user can have two good periods (morning and late afternoon) with a dip in between.

**Forgetting.** Each day, precision decays toward the prior precision by `dailyDecay` (default 0.97, which gives an effective memory of about a month). Learned preferences are kept but become less certain. The policy then explores again and recent outcomes can move it when routines change (a new job, holidays, summer).

**Prior updates do not reset users.** When a new population prior arrives, the app replays the user's resolved decisions from the last 180 days on top of it.

`check_adaptation.py` measures this on simulated users whose preferred hour shifts by six hours partway through. On the synthetic data, the gap in send rate between slots near and far from each user's preferred hour reached about 0.30. After a shift at day 98, the policy without forgetting was still mostly wrong three weeks later (gap about 0.10). With `dailyDecay = 0.97` it had recovered to about 0.24. The price of forgetting is a slightly blunter policy for users whose routine never changes.

## Tuning knobs (`build_prior.py`)

| Flag | Default | Effect |
|---|---|---|
| `--lam` | 0.10 | Cost of one reminder. Higher means fewer, better-targeted reminders. |
| `--objective` | `response` | `uplift` stops reminding at times the user would drink anyway. Needs phase-2 data to be meaningful. |
| `--epsilon` | 0.10 | Share of random decisions. Keeps learning alive and keeps skip data flowing. |
| `--floor` | 0.05 | Minimum probability of either action. Bounds importance weights in off-policy evaluation. |
| `--decay` | 0.97 | Forgetting rate. Lower adapts faster to changes but is noisier. |
| `--var-floor` | 0.15² | Minimum prior variance per coefficient. Higher lets each user move further from the population. |
| `--chains`, `--draws` | 4, 1000 | Sampling effort. Must pass the convergence gate. |
| `--max-users`, `--sampler`, `--force` | | Dry-run helpers. Never publish a prior built with `--force`. |

Check any change with `check_adaptation.py` on synthetic data and `ope.py` on real logs before publishing.

## Things worth knowing

**Label leakage.** `statusInteracao`, `tempoAteAgirMin` and `resultouEmConsumo` are outcomes and are never used as features. `feriado` is always false and `ActivityLevel` is not collected, so neither is used.

**What counts as success.** The outcome is "any intake logged within 10 minutes of the slot". It also credits drinks that would have happened anyway, which is why the uplift objective and the logged skips exist.

**Reinstalls.** A reinstall or new phone starts from the population prior, because the app does not pull `SlotDecision` history from CloudKit. Pulling the user's own records on first launch and calling `adopt` would restore their personalization.
