# Awake Cross-Platform Architecture Specification

**Status:** Implementation-ready baseline; platform support is capability-based.

**Updated:** 2026-11-21

## Intent

Extend Awake from its current macOS menu-bar app and Bash CLI to macOS, Linux, and Windows. Preserve one understandable command model and one local request-arbitration model while using the sleep-prevention mechanism and native UI conventions of each operating system.

This specification complements [`2026-11-21-awake-automation-design.md`](2026-11-21-awake-automation-design.md). The automation design defines the product behavior (Activity, Schedule, Manual On/Off, Snooze, Battery Guard, Get Started). This document defines the cross-platform engine, persistence, OS capabilities, and delivery order. The macOS product behavior is implemented first; Linux and Windows follow only after their capability matrices pass verification.

## Product rules

- Keep discovery, rule evaluation, state, and process inspection on the user's device. No account, telemetry, cloud service, or network access.
- Use the shared request coordinator for CLI, menu UI, Activity, Schedule, and manual requests. Each source can be stopped independently; effective Awake state is the OR of eligible live requests.
- `awake run <command>` is an explicit request. It continues during the Activity/Schedule snooze and checks Battery Guard even when the tray app is closed.
- Show which source is keeping the system awake and which capabilities are available on the current platform.
- Never claim that Awake can override explicit user sleep, thermal emergency, low-battery firmware behavior, enterprise policy, or hardware-specific power behavior.
- Keep the root `AGENTS.md` local and ignored. Never stage, commit, or publish it.

## Supported capability matrix

| Platform | Idle system sleep | Lid-close behavior | v1 condition |
|---|---|---|---|
| macOS 12+ | Process-lifetime IOPM assertion (`caffeinate -i` fallback) | Optional admin setup via narrow `pmset -a disablesleep 1` rule | Supported. Lid support is separately explained and skippable. |
| Linux with systemd-logind | Process-owned logind inhibitor | Request `handle-lid-switch` inhibitor where logind owns lid handling | Supported only on validated logind sessions. Desktop policy may own lid behavior. |
| Linux without usable systemd-logind | No equivalent system-sleep guarantee in v1 | Unsupported | CLI reports unsupported capability; no `xset`/screensaver fallback may be described as system-sleep prevention. |
| Windows 10+ | `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` for an active request | Optional user-consented AC/DC lid-action change with exact recovery | Idle prevention supported. Lid support remains opt-in and may be blocked by policy/admin permissions. |

Across all platforms, user-initiated sleep and power-button actions remain respected unless a separately described native mechanism explicitly supports the requested operation. Network continuity is not guaranteed.

## Architecture

### Shared engine and UI boundary

- Implement one Go engine/CLI as the owner of arbitration, persistence, battery checks where available, and platform power adapters. Use a supported Go release and build macOS artifacts with the latest Go 1.26 patch while macOS 12 remains supported; Go 1.27 requires macOS 13 or later. Revisit this policy before Go 1.26 leaves upstream support or if the macOS floor changes.
- Keep the existing Swift/AppKit menu-bar experience as the macOS presentation layer during the migration. It delegates state changes and queries to the `awake` CLI rather than independently writing shared state or changing power settings.
- Use platform-native tray presentation. Linux tray builds may require cgo and GTK/AppIndicator development/runtime packages; those are documented package dependencies. A universal zero-dependency binary is not a release requirement.
- Share command semantics, status reasons, mascot assets, and core behavior. Native menu appearance, tray support, and package formats may differ by OS.
- Build cgo/tray artifacts on native platform runners. Cross-compile only targets whose native dependencies permit it.

### CLI contract

The first shared commands are:

```text
awake on [--duration DURATION]
awake off [--source SOURCE]
awake status [--json]
awake run <command> [args...]
awake rules list|enable|disable ...
awake recover
```

- Validate arguments before arithmetic, process signaling, file operations, or command execution. Pass child arguments as an argument array; never interpolate untrusted input into shell source.
- `awake on` creates/updates only the Manual On lease. `awake off` removes only the requested source; with no source it applies the existing product behavior: clear Manual On and snooze Activity/Schedule for 30 minutes, while `awake run` continues.
- `awake status` reports effective state, active sources, Battery Guard/snooze state, available platform capabilities, and any pending recovery/error.
- `awake run` owns its command child, a unique lease, and its process-bound inhibitor. Normal completion and catchable signals clean up that lease and reconcile system settings even if the GUI is not running.
- Do not promise cleanup on SIGKILL, forced process termination, kernel panic, or power loss. Startup/next-command recovery is the v1 fallback for persistent settings.

## Shared state and concurrency contract

- State is private to the current user. Use the absolute `XDG_CONFIG_HOME` if set; otherwise use `$HOME/.config/awake`. On macOS, `$HOME/Library/Application Support/Awake` is acceptable only if both CLI and app resolve to that same canonical path. Create directories/files with user-only permissions. Never fall back to a shared predictable `/tmp` path.
- Separate durable user rules/preferences from ephemeral leases and OS recovery journals. The versioned schema contains: schema version, platform, durable rules, snooze expiry, lease records, and per-platform recovery snapshots. Do not persist a single global `active` flag as the source of truth.
- Every lease has a unique ID, source, owner PID, process start identity, boot/session identity, creation time, optional expiry, and user-facing reason. Platform-specific identities must prevent PID reuse from preserving a stale lease.
- A single engine process serializes mutations and owns all OS setting changes. The Swift UI communicates through CLI commands and JSON status; it does not independently modify files. This avoids a shell/Swift lock protocol with different implementations.
- Write state to a same-directory private temporary file, flush it, and atomically rename it into place. Serialize engine mutations with an OS-appropriate interprocess lock. Lock acquisition has a bounded wait and reports errors without partially applying state.
- Prune leases whose owner is dead, whose process start identity differs, whose boot/session identity is stale, or whose expiry has passed. Prune before evaluating requests on every engine start/command.
- On schema corruption, preserve the unreadable file for diagnosis, enter a safe inactive state where possible, reconcile any recoverable system journal, and report a repair path. Never guess an original system setting.

## Sleep-prevention and recovery behavior

### Process-lifetime mechanisms

- **macOS idle sleep:** use `IOPMAssertion` of type `kIOPMAssertionTypePreventUserIdleSystemSleep`, or `caffeinate -i` until the Go/native assertion implementation is proven. This may allow display sleep and does not itself prevent lid-close sleep.
- **Linux:** acquire a logind inhibitor FD for the active request. The owning process retains the FD until its lease ends; closing it releases the inhibitor. For `awake run`, the request is scoped to the command lifetime. Request `sleep` and, where supported, low-level `handle-lid-switch` locks; report which lock was granted. The CLI must not depend on a detached short-lived `systemd-inhibit` process.
- **Windows idle sleep:** call `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` for the active lease and clear it when no qualifying request remains. Do not include `ES_DISPLAY_REQUIRED` by default. Do not use away mode for ordinary developer work.

### Persistent system settings

- **macOS optional lid support:** before the first request that enables `pmset -a disablesleep`, read and save the original `SleepDisabled` value. Use only the narrowly scoped sudoers commands `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. Unknown/unreadable baseline means do not change the setting.
- **Windows optional lid support:** with explicit user consent, capture the active scheme GUID and its original AC and DC lid-action values before changing them. Apply `Do Nothing` only to the selected scheme. Restore the captured values on stop/recovery only if the scheme and values still match Awake's applied state; if another actor changed them, preserve that newer state and report a restore conflict. Do not assume the default is Sleep.
- Linux v1 must not modify persistent system power settings.
- Write a durable recovery journal before applying any persistent change. On last lease removal, Battery Guard suppression where applicable, app/CLI startup, and `awake recover`, reconcile the current system against the journal and active leases.
- If another actor changes a persistent setting while Awake is active, avoid overwriting the newer value during cleanup; surface a conflict and provide a user-directed recovery command.
- A restart or panic may leave persistent settings changed until Awake next runs. v1 does not install a privileged boot daemon, so recovery before login/next invocation is not guaranteed. README and SECURITY must state this and document the audit/recovery command.

## Platform implementation details

### macOS

- Keep macOS 12+ as the product floor and retain the existing Swift AppKit UI during the engine migration.
- User state lives in one private canonical directory shared by the app and engine.
- Keep the idle assertion separate from `pmset` lid behavior. Battery Guard suppresses Awake-owned assertions and reconciles only Awake-owned persistent changes; it does not override a pre-existing `SleepDisabled=1` set by another owner.
- Keep the sudoers rule restricted to the exact two `pmset` commands, validate generated rules with `visudo`, and pair setup with uninstall/revocation.
- Login-at-startup uses the supported API for each OS: legacy login item/LaunchAgent on macOS 12 and `SMAppService.mainApp` on macOS 13+.

### Linux

- Support `systemd-logind` sessions that permit the requested inhibitor. Detect absence, denial, and lock type distinctly.
- A desktop environment may own lid handling; the app must not imply that a logind inhibitor overrides every desktop policy. Include a documented manual test for supported desktop/session combinations.
- No non-systemd fallback may claim to prevent lid-close/system sleep. It may be added later as an explicitly narrower idle/display feature.
- Package native tray dependencies for supported distributions; provide a CLI-only build where tray dependencies are unavailable.

### Windows

- Support Windows 10+ on `amd64` first. Add other architectures only when the CI and package matrix is verified.
- Prefer the user-mode execution-state API for idle sleep. Lid-close changes are a separate opt-in with clear AC/DC and system-wide-effect explanation.
- Do not promise that an API prevents user-initiated sleep, power-button behavior, Modern Standby policy, or enterprise policy.
- If a power plan changes while Awake is active, restore only the scheme/value Awake changed; report if exact safe restoration is no longer possible.

## Performance and dependencies

- No Electron, Node.js, Python, telemetry, network client, or privileged background daemon.
- Use Go's standard library for the engine unless a dependency has a documented platform need and maintenance owner. Tray dependencies are platform-specific and disclosed.
- Do not make `<20 MB RAM` or `<50 ms cold start` release requirements until measured. Record target hardware, OS, binary type, warm/cold conditions, and benchmark method before adopting numeric budgets.
- Startup and memory are product quality goals; sleep safety and correct restoration take priority over binary size.

## Distribution and release

- Keep the current source build/install route for contributors.
- macOS: `.dmg` primary and `.zip` companion, arm64 and x86_64, signed/notarized before public release. Universal builds are preferred if the toolchain and macOS 12 floor permit; otherwise label separate downloads.
- Linux: publish CLI packages for the verified systemd distributions and a tray package only where its native dependencies are available. Begin with `.deb` and `.rpm`; add other formats after support validation.
- Windows: portable `.zip` for Windows 10+ amd64; add winget metadata after stable versioned artifacts and checksums exist.
- Every installer path has a documented uninstall/recovery counterpart. Releases include checksums, supported-OS matrix, native dependencies, privilege behavior, and known lid-close limitations.
- Do not publish signed releases until signing, notarization, and artifact verification are configured.

## Phased implementation roadmap

1. **Shared engine contract and macOS compatibility:** add Go engine/CLI behind existing macOS UI; define private state, leases, atomic writes/lock, source arbitration, recovery journal, and JSON status; preserve current CLI behavior during migration.
2. **macOS automation and release slice:** Activity/catalog, Schedule, snooze/manual arbitration, Get Started, settings, login item, battery guard, install/uninstall and `.dmg`/`.zip`.
3. **Linux CLI and logind adapter:** implement scoped `run`, persistent leases, capability reporting, supported-session verification, and distro packages. Add tray only for distributions with supported dependencies.
4. **Windows CLI and power adapter:** implement idle prevention, safe recovery, optional AC/DC lid support, policy/error handling, and portable package.
5. **Cross-platform tray parity and release automation:** implement native tray presentation by platform, mascot assets, CI build matrix, checksums, and release documentation.

Each phase ships a usable, reviewable slice and uses a separate branch and coherent commits according to [`docs/GIT_WORKFLOW.md`](../../GIT_WORKFLOW.md). Do not bundle unrelated features into one commit.

## Verification and acceptance criteria

Automated coverage is required for arbitration, concurrent commands, atomic state replacement, corrupt state handling, lease expiry/PID reuse, Battery Guard decisions, schedule boundaries, and exact safe restoration. Platform adapter tests use injectable OS-command/API wrappers where hardware access is unavailable.

Manual verification records platform version, hardware, power source, session type, package type, and result for:

- Normal completion, SIGINT/SIGTERM, SIGKILL/forced termination, app crash, reboot, and next-start recovery.
- Two simultaneous request sources, source-specific Off, Snooze, Battery Guard threshold crossing, and GUI closed/not running.
- macOS baseline already enabled, unknown baseline, sudoers denial, and another actor changing the setting.
- Linux granted/denied inhibitor, logind unavailable, supported desktop lid handling, and command termination releasing the FD.
- Windows AC/DC transitions, active scheme change, external setting edit, policy denial, explicit user sleep, and optional lid close.
- Install, upgrade, uninstall, sudoers revocation, and recovery command from outside the source checkout.

Acceptance means Awake reports the capability actually granted and never claims tested behavior outside the recorded platform matrix. Network continuity, surviving user-initiated sleep, and restoration before next login are not acceptance guarantees.

## Primary technical references

- [Go 1.26 release notes](https://go.dev/doc/go1.26) and [Go 1.27 release notes](https://go.dev/doc/go1.27): macOS 12 is supported through Go 1.26; Go 1.27 requires macOS 13+.
- [Apple IOPM assertion type](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep): process-lifetime prevention of automatic idle system sleep.
- [systemd-inhibit](https://www.freedesktop.org/software/systemd/man/latest/systemd-inhibit.html) and [logind.conf](https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html): inhibitor scope, supported lock types, and lid handling behavior.
- Microsoft [SetThreadExecutionState](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate), [powercfg command options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options), and [lid-close action values](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action).
- [`getlantern/systray` build and Linux requirements](https://github.com/getlantern/systray): cgo, GTK, and AppIndicator development/runtime dependencies.

## Maintainer decisions and gates

- **Selected default:** maintain macOS 12+. Use Go 1.26 latest patch for macOS artifacts while upstream supports it; Go 1.27 builds require macOS 13+, so do not silently raise the product floor. Revisit the toolchain/floor together before Go 1.26 support ends.
- **Selected default:** one Go engine/CLI owns shared state and power adapters; existing Swift UI delegates to the CLI during migration. Native per-platform tray UI is allowed; zero-dependency/single-binary is not required.
- **Selected default:** Linux system sleep/lid support is limited to validated systemd-logind sessions; unsupported environments receive an explicit capability result.
- **Selected default:** Windows idle prevention is default; lid behavior is opt-in, requires consent, snapshots AC/DC, and restores only when safe.
- **Selected default:** macOS stays first; Linux/Windows ship only after their adapter and recovery matrix passes.
- **Implementation gate:** first engine task must prove Go 1.26 builds and runs on macOS 12 and current macOS, the CLI can be invoked by the Swift app, and the chosen state/lock mechanism works across simultaneous Swift-launched and CLI mutations. If this gate fails, retain the existing Swift/Bash engine and revise the cross-platform core before adding platform adapters.
- **Deferred details:** initial curated app bundle/process mappings, exact package/release automation, and Apple signing credentials are implementation/release tasks; none changes arbitration or restoration rules.
