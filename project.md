# Awake Project Status

Last updated: 2026-11-21

## Current stage

**Stage 1 — Design readiness (prepared for implementation).** The macOS automation behavior and cross-platform architecture are aligned in [`docs/superpowers/specs/2026-11-21-awake-automation-design.md`](docs/superpowers/specs/2026-11-21-awake-automation-design.md) and [`docs/superpowers/specs/2026-11-21-awake-cross-platform-architecture.md`](docs/superpowers/specs/2026-11-21-awake-cross-platform-architecture.md). The implementation sequence is in [`docs/superpowers/plans/2026-11-21-cross-platform-awake.md`](docs/superpowers/plans/2026-11-21-cross-platform-awake.md). No product code has been changed for this work. The first implementation task is the macOS 12/Go 1.26 compatibility and shared-engine ownership gate.

## Development stages

| Stage | Status | Outcome |
|---|---|---|
| 0. Open Source baseline | In workspace; not published | MIT license, community policies, contribution/support docs, issue/PR forms, Git workflow, and GitHub setup checklist. Privacy policy and sudoers threat/revocation docs remain planned. `AGENTS.md` stays local and ignored. |
| 1. Design readiness | **Prepared** | Cross-platform capabilities, arbitration, state ownership, recovery limits, toolchain constraint, and staged delivery are documented. |
| 2. Shared engine foundation | Next | Prove Go 1.26/macOS 12 compatibility; establish the Go CLI as sole state/power owner; add versioned private state, locking, atomic writes, leases, arbitration, and recovery. |
| 3. macOS automation slice | Pending | Migrate CLI/UI safely, then Activity catalog, weekly schedules, snooze, battery guard, and `awake run` integration. |
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

1. **Engine compatibility gate:** verify the planned Go 1.26 build and CLI delegation on macOS 12 before migrating the existing CLI; if it fails, revise the engine choice without silently raising the macOS floor.
2. **Signing credentials:** verify Apple Developer Program/Developer ID access before preparing a public release; release builds stay gated until signing and notarization can be completed.
3. **Catalog implementation details:** define exact bundle IDs/process mappings for the initial supported apps during implementation planning.
4. **Universal build feasibility:** preferred `arm64` + `x86_64`; fall back to separate labeled downloads if the macOS 12 toolchain/build requires it.

## Repository status

- The connected GitHub repository is public and private vulnerability reporting has been enabled by the maintainer.
- The local repository has a baseline commit; current design and project-status refinements are uncommitted in the workspace.
- Do not stage, commit, or push the root `AGENTS.md`.
- No product implementation, tests, CI workflow, or release artifact has been added for this design yet. This preparation updated design, plan, and project status only.
