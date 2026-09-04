# HidrataPOC

iOS POC (TestFlight-only) that collects hydration behavior data — profile, daily
check-ins, water intake, and full context around every reminder notification sent —
for training a future notification-timing recommendation model. The app makes no
predictions itself; see `instrucoes_poc_hidratacao_swift.md` for the full spec this
was built from.

## Opening the project

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen).
If you add/remove/rename files, regenerate before building:

```bash
xcodegen generate
open HidrataPOC.xcodeproj
```

## Required setup before this runs for real (developer's responsibility)

Everything below started from a placeholder identity so the project would build out
of the box. `project.yml` now uses `com.hidratapoc` — update the rest as below.

1. **Bundle ID / Team** — set in `project.yml` (`options.bundleIdPrefix`, the target's
   `PRODUCT_BUNDLE_IDENTIFIER`, and the entitlements' `icloud-container-identifiers`).
   `DEVELOPMENT_TEAM` must be your **10-character Team ID** (Apple Developer →
   Membership, or Xcode → Settings → Accounts → your team), not the team's display
   name — Xcode/codesign won't resolve a name there.
   **Two identifiers are duplicated in Swift code and must match `project.yml` by
   hand** (XcodeGen only generates the Info.plist/entitlements, it doesn't rewrite
   Swift source):
   - `Constants.cloudKitContainerID` in [`Constants.swift`](HidrataPOC/Support/Constants.swift)
     must match `entitlements.properties.com.apple.developer.icloud-container-identifiers`.
   - `BackgroundRefreshService.taskIdentifier` in
     [`BackgroundRefreshService.swift`](HidrataPOC/Services/BackgroundRefreshService.swift)
     must match `info.properties.BGTaskSchedulerPermittedIdentifiers`. A mismatch here
     is exactly what causes `BGTaskScheduler`'s "Registration rejected; ... is not
     advertised in the application's Info.plist" crash at launch.
   After editing any of these, re-run `xcodegen generate`.
2. **CloudKit container** — the container (`iCloud.com.hidratapoc`) is created
   automatically the first time you open the project in Xcode with the iCloud
   capability enabled and a valid team selected.
3. **CloudKit Dashboard schema + Security Roles** (manual, in the [CloudKit Console](https://icloud.developer.apple.com)):
   - Record types (`UserProfile`, `DailyCheckin`, `IntakeLog`, `NotificationEvent`)
     are auto-created in the **Development** environment the first time the app
     saves each one — no manual schema work needed there. Before shipping, use
     "Deploy Schema Changes to Production" to copy that schema over.
   - This app writes to the **Public** database so every tester's data lands in one
     place you can query. Under Schema → Security Roles, set the `_icloud` (or
     `Authenticated Users`) role's permission on each record type to **Create only**
     — leave **Read** off. Create doesn't imply read, so this keeps testers from
     reading each other's data while still letting the developer read everything
     from the dashboard (roles apply to app requests; dashboard access is separate,
     tied to your developer account).
   - Do this in both the Development and Production environments once you deploy.
4. **WeatherKit capability** — requires an active, paid Apple Developer Program
   membership. Enable the WeatherKit capability for this App ID in the developer
   portal (Xcode's "+ Capability" does this automatically once you're signed in
   with a paid account).
5. **TestFlight** — archive & upload as usual; nothing else in this app is
   TestFlight-specific.

## Known limitations (by design, for a POC)

- **Background notification timing is best-effort.** iOS gives local notifications
  no exact-time background hook — `BGAppRefreshTask` is opportunistic. Context
  (weather/calendar/deficit) is captured a few minutes ahead of each reminder while
  the app is foregrounded, via a best-effort background refresh task, or — as a
  last resort — synchronously the moment a tester interacts with a notification
  whose context was never pre-captured. No interaction is ever left without a
  `NotificationEvent` row, but on a device that's rarely opened, background capture
  timing (and therefore how "fresh" the weather looks) is not guaranteed. See the
  doc comment on `NotificationScheduler` for the full reasoning.
- **CloudKit sync needs a signed-in iCloud account** (Settings → \[your name] on
  the test device/simulator). Without one, the app falls back to a locally
  generated anonymous ID so onboarding still works, but nothing syncs until pushed
  again after signing in.
- **SwiftData's own CloudKit mirroring is intentionally disabled**
  (`ModelConfiguration(cloudKitDatabase: .none)` in `PersistenceController`) — it
  only supports the private database and would conflict with the manual public-DB
  sync in `CloudKitSyncService`. Don't re-enable it without also removing the
  manual sync layer.
