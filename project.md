# Awake Project Status

Last updated: 2026-11-21

## Current stage

**Stage 1 — Design refinement (in progress).** Automation, shared-state safety, recovery, privacy, and distribution requirements are captured in [`docs/superpowers/specs/2026-11-21-awake-automation-design.md`](docs/superpowers/specs/2026-11-21-awake-automation-design.md). Implementation has not started. User-selected defaults are recorded; the design still needs review before implementation planning.

## Development stages

| Stage | Status | Outcome |
|---|---|---|
| 0. Open Source baseline | In workspace; not published | MIT license, community policies, contribution/support docs, issue/PR forms, Git workflow, and GitHub setup checklist. Privacy policy and sudoers threat/revocation docs remain planned. `AGENTS.md` stays local and ignored. |
| 1. Design refinement | **In progress** | User-facing trade-offs have recommended defaults; review the updated design before implementation planning. |
| 2. Shared automation foundation | Pending design approval | Versioned local rules/leases, cross-process locking, atomic writes, arbitration, stale CLI cleanup, sleep-state restoration. |
| 3. Automation sources | Pending | Activity watcher/catalog first; weekly schedules with cross-midnight and timezone behavior; standalone `awake run`. |
| 4. Get Started and Settings | Pending | Progressive first-run questions, local app suggestions, per-rule review/toggles, login item, snooze, notifications, Light/Dark appearance. |
| 5. Open Source readiness | Partly prepared | Privacy statement, sudoers threat model and uninstall docs, automated test/CI decision, branch and security settings review. Private vulnerability reporting is enabled; verify its reporting and notification path. |
| 6. Distribution | Pending | Universal or architecture-specific `.dmg` and `.zip`; signing/notarization; consider Homebrew after stable releases. |

## Decisions confirmed

- Activity and weekly Schedule automation should complement the existing `awake run` command.
- All discovery, rules, and automation evaluation remain local; no account, telemetry, or cloud service.
- Activity catalog targets AI agents and long-running developer work. Recommend only relevant apps found locally; ask the user to select recommendations and confirm before enabling.
- For each app, recommend `Work process` or `App is open` based on that app, while allowing the user to change the mode.
- Schedule uses selected weekdays and local start/end times, supports crossing midnight, and does not wake a sleeping Mac.
- Each rule/source is independently enabled. Awake stays active while any unsuppressed source requests it.
- Manual Off starts a 30-minute pause for Activity/Schedule. Explicit `awake run` and Manual On continue; turn a rule off in Settings to disable it persistently.
- Wait two minutes after a watched process disappears before releasing that request.
- Use catalog-specific process mappings for known apps and exact matching for custom process targets; avoid broad process-family watches unless the user opts in.
- Low battery releases keep-awake and sends a notice but does not terminate the user's command.
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

## Decisions still needed

1. **Design approval:** review the revised design and approve it before implementation planning.
2. **Signing credentials:** verify Apple Developer Program/Developer ID access before preparing a public release; release builds stay gated until signing and notarization can be completed.
3. **Catalog implementation details:** define exact bundle IDs/process mappings for the initial supported apps during implementation planning.
4. **Universal build feasibility:** preferred `arm64` + `x86_64`; fall back to separate labeled downloads if the macOS 12 toolchain/build requires it.

## Repository status

- The connected GitHub repository is public and private vulnerability reporting has been enabled by the maintainer.
- The local repository currently has no commits; existing and newly prepared files are uncommitted in the workspace.
- Do not stage, commit, or push the root `AGENTS.md`.
- No implementation, tests, CI workflow, or release artifact has been added for this design yet.
