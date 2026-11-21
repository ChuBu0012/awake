# Awake Automation and Open Source Readiness — Design

This is the macOS-first product behavior specification. Cross-platform engine ownership, state format, platform capabilities, and release sequence are defined in [`2026-11-21-awake-cross-platform-architecture.md`](2026-11-21-awake-cross-platform-architecture.md). Where implementation details differ, preserve the behavior and safety rules in both documents.

## Intent

Make Awake feel useful without routine manual on/off actions. The app should notice selected work locally, follow user-defined schedules, and clearly explain why it is keeping the Mac awake. The first-run flow should make setup approachable for people who do not know what a process or sleep assertion is.

Prepare the public repository so people can understand the privacy model, contribute safely, and install the app with clear expectations.

## Goals

- Add local Activity and weekly Schedule automation alongside the existing `awake run` command.
- Let each watcher and schedule be enabled or disabled independently. Awake remains active while any enabled source requests it.
- Add a friendly, skippable Get Started flow with multi-select goals, locally discovered relevant app recommendations, a review step, and setup choices.
- Use macOS appearance and native controls, with a clean layout, clear status reasons, and concise state-change notifications.
- Keep all app discovery, rules, and decisions on the Mac. Do not add accounts, telemetry, or network services.
- Improve Open Source readiness with a clear privacy statement, accurate build/contribution guidance, automated tests and macOS CI, and a prioritized GitHub setup checklist.
- Prepare a release path for a drag-and-drop `.dmg`, a `.zip` app archive, source install, and a later Homebrew distribution option.

## Non-goals

- Waking a sleeping Mac when a schedule begins.
- Cloud sync, accounts, telemetry, or remote process inspection.
- Automatically enabling a watcher merely because an app is installed.
- Watching all installed or running apps without the user's explicit selection.
- Publishing a release as part of this change.
- Changing sudoers scope beyond the existing `pmset -a disablesleep 0|1` commands.

## Approaches considered

1. **Build every automation feature at once.** This gets to a broad feature surface quickly but couples app discovery, schedule evaluation, UI, and global sleep state in one large change.
2. **Build the shared rule model first, then add usable automation slices.** A single local rule evaluator owns source arbitration, after which Activity watching and Schedule rules can be added without one source turning off another. This is the selected approach because independent sources and predictable cleanup are core requirements.
3. **Ship Activity watching only.** This is the smallest feature but leaves the accepted weekly Schedule and Get Started experience incomplete.

## User experience

### First launch

```text
Step 1 — What should Awake help with? (select any)
  [ ] Keep Mac awake while an AI agent works
  [ ] Keep Mac awake during a weekly schedule
  [ ] Keep Mac awake while a command runs
                                       [Continue] [Skip setup]

Step 2 — Recommended apps found on this Mac
  [ ] <recognized installed AI/developer app> — Why it is suggested
      Watch mode: [Recommended: Work process ▾]
  [ ] Add app or process...
                                       [Back] [Continue]

Step 3 — Review and optional setup
  Selected watchers and schedules, each independently enabled
  Start Awake when I log in: [On]
  Lid-closed support: [Set up once] [Skip]
  Schedule details (if selected): weekdays, start, end
                                       [Back] [Start using Awake]
```

- Use 2–3 short steps with progressive disclosure; do not show all controls on one dense screen.
- The wizard asks goals in plain language, supports multiple selections, and can be skipped at any time. Settings can reopen it later.
- App discovery scans installed application metadata locally and matches only a curated AI/developer catalog. Show only matching installed apps, explain each suggestion, and require the user to select each item and confirm the final rule set. Provide manual app/process addition.
- The catalog chooses a recommended watch mode per app, but the user can change it. Do not start a watcher merely because an app is installed.
- Some IDEs and AI tools keep background daemons alive when idle. Catalog entries must distinguish `Work process` from `App is open`; use task/process monitoring where the app exposes a reliable process, and label app-lifetime watching as a broad fallback that can keep the Mac awake while idle.
- Offer launch-at-login as an explicit setup choice, initially on as the recommendation. The user can decline or change it in Settings.
- Closing the Settings window leaves the menu-bar app running in the background. Whether Activity/Schedule must survive an explicit Quit or app crash without the menu-bar process is a separate helper/daemon decision below.
- Explain the two sleep-prevention layers and the admin requirement before offering lid-closed support. It can be skipped; do not broaden the sudoers rule.

### Main window and menu bar

- Use a native Settings window for watcher and weekly schedule management. Keep the menu bar for quick status, pause/snooze, and on/off controls.
- Respect system Light/Dark appearance and accessibility settings.
- Show why Awake is active, for example `Agent: <name>`, `Schedule: Weekdays 22:00–02:00`, or `Command: awake run ...`.
- Notify only on automatic state transitions, with the source that caused the transition.
- Manual Off clears the Manual On request and starts a 30-minute pause of Activity/Schedule automation without changing saved rules. A user can disable an individual rule in Settings to stop it persistently.
- A direct `awake run` command is an explicit request and continues through an Activity/Schedule Snooze. Manual On cancels Snooze and adds its own request. Show the effective source and Snooze expiry so users understand why Awake remains active.
- Saved Activity/Schedule rules and the Snooze expiry survive app restarts. Manual On is session-scoped and ends when the menu-bar app quits or crashes; it does not reactivate at the next login.

## Automation behavior

- Sources are the existing `awake run` command wrapper, selected Activity watchers, weekly Schedule rules, and a separate Manual On request. Manual On is session-scoped and ends when the menu-bar app quits or crashes; it does not reactivate at the next login.
- Each source has its own enabled state and active request. The normal aggregate is logical OR: any active request keeps the Mac awake; turning off one source removes only that request.
- Arbitration order: (1) Battery Guard suppresses Awake's effective assertion when battery is at or below 20% on battery power, but does not delete active leases or kill the user's command; restore Awake's `SleepDisabled` change to the captured baseline while suppressed, then reapply it when AC returns or battery rises above the threshold. If the captured baseline was already `SleepDisabled=1`, Awake cannot force the system to sleep and must explain that another setting owns the behavior; (2) an explicit `awake run` lease remains active through an Activity/Schedule Snooze; (3) Manual Off clears Manual On and starts a 30-minute Snooze that suppresses only Activity and Schedule requests; (4) Manual On cancels Snooze and adds its own request; (5) all unsnoozed enabled Activity/Schedule requests are combined with OR semantics. Turning an individual rule off disables that rule until the user turns it back on.
- A process watcher waits 2 minutes after its last matching process disappears before releasing its request. This grace period handles short restarts.
- `App is open` matches the selected app by bundle identity. `Work process` uses an app-specific curated process mapping; custom process entries match the exact selected executable/process identity. Do not watch broad names such as `node` globally without an explicit user choice, and do not assume every child process means work is active.
- A weekly schedule uses local wall-clock time and selected weekdays. The selected day is the start day: `Weekdays 22:00–02:00` includes Friday 22:00 through Saturday 02:00. Time-zone changes recalculate future occurrences in the Mac's current time zone. Daylight-saving gaps/repeated times need deterministic Foundation `Calendar` handling and user-visible documentation.
- A schedule prevents sleep during its active window but does not wake a sleeping Mac.
- The Battery Guard threshold is 20% or lower while running on battery power; it does not block requests while connected to AC. The existing Battery Guard toggle remains available. Evaluate it before every GUI or CLI request, including standalone `awake run` when the menu-bar app is not open. If battery falls to the threshold during an active request, suppress Awake's IOPM assertion and restore the captured `SleepDisabled` baseline, but leave the lease and user's command running. If another owner had already disabled sleep, show that Battery Guard cannot override that setting. When the guard clears, resume all still-active eligible requests and notify once.
- The menu-bar app continues evaluating rules when its Settings window is closed. In v1, explicit Quit stops Activity/Schedule evaluation; the optional login item launches the menu-bar app at the next login. Do not add a separate always-on helper in v1. `awake run` itself remains standalone.
- Before the first active request, snapshot the prior `SleepDisabled` setting once. Do not replace that baseline when another source joins. When the final request ends, restore the snapshot. Treat an unknown or unreadable baseline as an error for privileged lid mode rather than guessing.

### Shared state, locking, and stale CLI sessions

- Store versioned rules and runtime requests under the current user's private configuration directory, shared by the app and CLI.
- Keep durable user rules separate from ephemeral runtime leases. Each `awake run` gets a unique lease record containing a run ID, wrapper/command PIDs, process start identity, boot-session identity, and start time.
- Publish changes through same-directory temporary files followed by atomic rename. The shared engine is the sole owner of state mutations, locking, and `pmset` reconciliation. The Swift UI and the legacy Bash CLI delegate state changes to the engine CLI; they must not independently write the state file or change power settings. Remove the Bash state-management path after command parity is verified.
- `awake run` checks battery guard before adding its lease, starts a process-bound `caffeinate` assertion, and removes only its own lease on normal completion or catchable termination. It reconciles system state itself; it must not depend on the GUI process.
- `SIGKILL` cannot run shell cleanup. The evaluator prunes a lease when its PID is absent, its process start identity no longer matches, or its boot-session identity is stale. Run pruning on every app evaluation and every CLI state command.
- A pruned request releases its assertion and triggers reconciliation. If the menu-bar app is not running, the next CLI invocation performs pruning and reconciliation.
- When the menu-bar app is not running, normal `awake run` still enables the battery guard, assertion, and privileged lid layer; normal completion/handled signals reconcile and restore the saved baseline. After `SIGKILL`, a repair requires another evaluator (app/CLI invocation or an installed helper), so immediate cleanup cannot be guaranteed by a shell trap.

### Sleep-prevention layers and crash recovery

- **Idle-sleep layer without admin setup:** use a process-lifetime `kIOPMAssertionTypePreventUserIdleSystemSleep` assertion (or the equivalent `caffeinate -i`) to prevent automatic idle system sleep. The display may still dim or sleep. This does not prevent sleep caused by lid close, explicit user sleep, low battery, or thermal emergency. The assertion disappears when its owning process exits. ([Apple assertion documentation](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep))
- **Lid-closed layer with admin setup:** use the narrowly allowed `sudo pmset -a disablesleep 1` setting, in addition to the process-lifetime assertion. This is a system-wide persistent preference, not a process-lifetime assertion.
- Normal CLI completion, GUI stop, Snooze, and uninstall must reconcile active leases and restore the original `disablesleep` value when appropriate.
- `pmset` settings are saved in the system-wide power-management preferences file. A panic/reboot can therefore outlive the app process. Recovery must not assume the kernel assertion is enough: on startup, compare the saved Awake baseline and active leases, clear stale records, and restore `disablesleep` if no valid request remains.
- **Recovery limitation:** startup at user login can recover after login but cannot guarantee restoration before login. v1 accepts recovery on the next app/CLI start plus a documented manual recovery command. Do not install a privileged LaunchDaemon in v1; it expands the privileged attack surface and installer/removal complexity. The UI and docs must clearly state this limitation.

## Open Source readiness

### Repository changes

- Add a `PRIVACY.md` stating that installed-app discovery and rule evaluation stay local, with no account, telemetry, or network transfer.
- Document the sudoers threat model, the exact allowed command, the system-wide effect, recovery behavior, and how to revoke the rule in `SECURITY.md`.
- Add an easy-to-audit README uninstall/revocation command, and ensure it restores active state before removing the app, CLI, launch item/helper, state files, and sudoers rule.
- Add automated tests for duration parsing, request arbitration, stale leases, schedule boundaries, and restoration, plus macOS CI that builds the app and runs those tests.
- Ensure README and contributor instructions accurately describe supported macOS, build requirements, sudo setup, and current test/build coverage.
- Keep MIT licensing, contribution, conduct, security, support, changelog, issue and pull-request templates, and Git workflow linked from the README.
- Keep `AGENTS.md` ignored and local as previously requested.
- Do not publish releases or signed binaries as part of this scope.

### GitHub settings checklist

- Private vulnerability reporting has been enabled by the maintainer; verify the report button and notification/contact path before inviting security reports.
- Protect `main` with pull requests and prevent force-push/deletion; require CI only after a stable workflow exists.
- Enable secret scanning and push protection where available.
- Add repository description and relevant topics.
- Confirm the copyright holder in `LICENSE` before release.
- Configure repository description/topics, and publish a release only after its artifact, signing, and checksum process is documented.

GitHub settings are not changed by repository files. They remain a maintainer action.

## Distribution design

- Keep `make install` as the source-build path for contributors.
- Primary end-user artifact: a drag-and-drop `.dmg` containing `Awake.app`, Applications-folder instructions, version, supported macOS floor, and checksum.
- Also attach a `.zip` of the app to each GitHub Release for users who prefer archive downloads and automated tooling.
- Build a universal `arm64` + `x86_64` app while macOS 12+ remains supported, or publish clearly labeled architecture-specific artifacts if toolchain constraints prevent a universal build.
- Require Developer ID code signing and Apple notarization for public `.dmg`/`.zip` releases; do not put signing credentials in the repository. Unsigned artifacts may be used for private previews with clear Gatekeeper instructions, but are not the public release target.
- Consider a Homebrew Cask for the app and a separate formula for the CLI after stable versioned releases exist. This is a later distribution channel, not a prerequisite for the first `.dmg`.
- Include an uninstall path that removes the login item/background helper and sudoers rule, restores the prior power setting, and does not delete unrelated user data.

## Constraints

- Current product minimum is macOS 12+. Use the legacy login-item/LaunchAgent path on macOS 12 and `SMAppService.mainApp` on macOS 13+.
- Native Swift/AppKit remains the macOS presentation layer. The cross-platform engine and CLI migration is defined in [`2026-11-21-awake-cross-platform-architecture.md`](2026-11-21-awake-cross-platform-architecture.md); no new network dependencies.
- Local-only operation; no new network dependencies.
- Keep the privileged command whitelist narrow.
- Do not include the local-only root `AGENTS.md` in any commit or push.
- Do not claim verification unless the relevant check has actually run.

## Open design calls for implementation

- The initial curated app catalog and the exact bundle/process mapping for each recommendation.
- Exact app-to-process mappings for the initial curated catalog; known apps may use catalog-specific process groups, while custom targets match the exact process identity.
- Exact versioned schema and transition protocol for rules/leases, consistent with the shared-lock and atomic-write requirements above.
- The exact native Settings/Get Started layouts and accessibility labels.
- Exact command output and UI copy for the recovery flow; state ownership, atomic writes, interprocess locking, and the `awake recover` command are defined in the cross-platform architecture spec.
- Whether the maintainer has an Apple Developer Program identity for Developer ID signing/notarization. Public releases require signing/notarization; private previews may be unsigned.
- Exact release architecture matrix if a universal binary proves impractical; preferred default remains universal arm64+x86_64.
- DST behavior is set: missing boundaries use the next valid local time; repeated boundaries form one continuous interval and do not activate twice.
- macOS minimum is set to 12+. Use the legacy login-item/LaunchAgent approach on macOS 12 and `SMAppService.mainApp` on macOS 13+, subject to implementation compatibility review.
- Homebrew is deferred until `.dmg`/`.zip` release automation is stable.
- Snooze/Off arbitration is set: Off applies a 30-minute Activity/Schedule Snooze; `awake run` and Manual On remain active; persistent rule changes happen in Settings.
- Manual On is session-scoped; it ends on explicit Quit or crash and does not resume at login. Saved rules and the Snooze expiry persist.
- Runtime model is set: the menu-bar process evaluates Activity/Schedule while running (even with its window closed); explicit Quit stops those rules; no separate helper in v1.
- Recovery is set: next app/CLI start repairs stale state, and docs provide manual recovery; no privileged boot LaunchDaemon in v1.
- Battery behavior is set: at 20% or lower while on battery, suppress Awake's assertion, restore Awake's `SleepDisabled` change to the captured baseline, and notify without terminating the command; resume eligible active requests when the guard clears; skip the guard while on AC, and respect the user's Battery Guard toggle.
- Automated tests and macOS CI are included in the Open Source readiness work before public release.
