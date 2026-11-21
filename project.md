# Awake Project Status

Last updated: 2026-11-21

## Current stage

**Stages 2–3 — Shared engine and first macOS automation slice (implemented).** The Go CLI owns private state, locking, lease arbitration, Battery Guard, recovery, and macOS sleep adapters. The Swift menu bar app delegates through the CLI and exposes Activity and weekly Schedule rules. The app and CLI have both launched and run on macOS 12.7.6 in an Apple Silicon VM. Manual interaction review remains outstanding.

## Development stages

| Stage | Status | Outcome |
|---|---|---|
| 0. Open Source baseline | In workspace; not published | MIT license, community policies, contribution/support docs, issue/PR forms, Git workflow, GitHub setup checklist, and sudoers threat/revocation guidance. A standalone privacy policy remains planned. `AGENTS.md` stays local and ignored. |
| 1. Design readiness | **Prepared** | Cross-platform capabilities, arbitration, state ownership, recovery limits, toolchain constraint, and staged delivery are documented. |
| 2. Shared engine foundation | **Implemented and runtime-verified on macOS 12.7.6** | Go CLI owns versioned private state, file locking, atomic writes, lease arbitration, battery/lid support, migration, and recovery. Go CLI status and `awake run /usr/bin/true` completed successfully on Apple Silicon macOS 12.7.6. A lock descriptor inheritance bug found during this check is fixed with close-on-exec and a regression test. |
| 3. macOS automation slice | **Implemented; launch/delegation smoke verified** | Swift menu bar delegates state and power changes to the CLI; Activity rules support app-open and exact process names; weekly schedules, snooze, battery guard, and `awake run` share arbitration. The app launched on macOS 12.7.6 and wrote its owner PID and locally observed bundle IDs through the CLI. Manual interaction review remains. Get Started and curated recommendations remain Stage 4. |
| 4. Get Started and Settings | Pending | Progressive setup, local recommendations, per-rule controls, login item, notifications, and Light/Dark appearance. |
| 5. Linux support | Pending | systemd-logind engine adapter, explicit capability reporting, validated sessions, and packages with disclosed tray dependencies. |
| 6. Windows support | Pending | Idle prevention, safe recovery, opt-in AC/DC lid behavior, policy/error handling, and portable package. |
| 7. Open Source and distribution readiness | Partly prepared | Privacy/security/uninstall docs, automated tests and CI, `.dmg`/`.zip`, platform packages, signing/notarization, then later Homebrew. Private vulnerability reporting is enabled; verify its report and notification path. |

## Decisions confirmed

- Activity and weekly Schedule automation should complement the existing `awake run` command.
- All discovery, rules, and automation evaluation remain local; no account, telemetry, or cloud service.
- Activity catalog targets AI agents and long-running developer work. Recommend only relevant apps found locally; ask the user to select recommendations and confirm before enabling.
- For each app, recommend `Work process` or `App is open` based on that app, while allowing the user to change the mode.
- Schedule uses selected weekdays and local start/end times, supports crossing midnight, and does not wake a sleeping Mac.
- Each rule/source is independently enabled. Awake stays active while any unsuppressed source requests it.
- Manual Off clears Manual On and starts a 30-minute pause for Activity/Schedule. Explicit `awake run` continues; Manual On clears Snooze. Turn an individual rule off in Settings to disable it persistently.
- Manual On is temporary to the current app session; Quit/crash clears it. Saved Activity/Schedule rules and the Snooze expiry persist across app restarts.
- Wait two minutes after a watched process disappears before releasing that request.
- Use catalog-specific process mappings for known apps and exact matching for custom process targets; avoid broad process-family watches unless the user opts in.
- At 20% battery or lower while unplugged, Battery Guard suppresses Awake's assertion, restores Awake's `SleepDisabled` change to the captured baseline, and notifies without terminating the user's command or discarding its lease. Eligible active requests resume when AC returns or battery rises above the threshold. If sleep was already disabled by another owner, explain that Awake cannot override it. The guard is inactive on AC and respects its toggle.
- Get Started is a skippable 2–3 step flow with multi-select goals, local app recommendations, review, and optional administrator setup.
- Offer login-at-startup, initially recommended on with explicit user confirmation.
- Provide a 30-minute Snooze and transition notifications that explain the active source.
- Use native, clean Settings UI that follows macOS Light/Dark appearance.
- Keep macOS 12+ as the minimum; use the legacy login-item path on macOS 12 and `SMAppService` on macOS 13+.
- Distribution target: `.dmg` first, `.zip` alongside it, Homebrew later unless the maintainer chooses otherwise.
- Keep Activity/Schedule evaluation in the menu-bar app while it runs in the background; explicit Quit stops them. `awake run` works without the app.
- Do not add a privileged boot daemon in v1. Recover persistent `pmset` state on next app/CLI start and document a manual recovery command; recovery before login is not guaranteed.
- Handle missing DST boundaries at the next valid local time and repeated times as one continuous schedule interval.
- Public `.dmg`/`.zip` releases require signing and notarization. Unsigned builds are for private preview only.
- Add automated tests and macOS CI before a public release.
- Private vulnerability reporting has been enabled by the maintainer; verify the reporting button and notification path before inviting reports.
- Cross-platform defaults: Go 1.26 latest patch while macOS 12 remains supported; one engine owns state mutations and OS adapters; the Swift UI delegates to the CLI during migration; Linux system-sleep support requires validated systemd-logind; Windows lid changes are opt-in with captured AC/DC values and safe restore.
- Recovery limit: SIGKILL, forced termination, panic, and power loss cannot run cleanup handlers. Persistent OS changes are repaired on the next app/CLI invocation; v1 does not guarantee recovery before login.

## Decisions still needed

1. **Signing credentials:** verify Apple Developer Program/Developer ID access before preparing a public release; release builds stay gated until signing and notarization can be completed.
2. **Catalog implementation details:** define exact bundle IDs/process mappings for the initial curated recommendations; current rules can be added locally by the user.
3. **Universal release build:** verify arm64 and x86_64 app packaging and choose universal or separate labeled downloads.

## Repository status

- The connected GitHub repository is public and private vulnerability reporting has been enabled by the maintainer.
- Core implementation is on `feat/awake-foundation` in a separate ignored worktree; the follow-up fix is on `fix/prefer-bundled-cli`, based on that branch. The app now prefers its bundled CLI over an older installed copy and shows CLI error details. Code commits are grouped by concern.
- Do not stage, commit, or push the root `AGENTS.md`.
- Current local verification: `make test` passes (Go tests, `go vet`, shell syntax, Swift app and CLI build); the build verifies app, CLI, and Info.plist minimum versions are all 12.0. On a Monterey 12.7.6 Apple Silicon VM, `awake status --json` returned valid empty arrays, `awake run /usr/bin/true` exited successfully without retaining the state lock, and the menu bar app launched and delegated owner/bundle discovery state to the CLI. The state lock now uses `O_CLOEXEC`. Build and install replace executable files atomically to avoid in-place replacement of a running binary. Manual UI behavior review, notarization, and release packaging remain outstanding.
