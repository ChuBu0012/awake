# Awake Cross-Platform Architecture — Review and Implementation Plan

**Date:** 2026-11-21

**Status:** Design refinement complete; ready to begin implementation at the compatibility gate.
**Scope:** Review, implementation sequence, and verification requirements. This preparation changes documentation only; it does not implement product code or run tests.

## Review summary

The cross-platform direction is promising, but the current specification is not safe or internally consistent enough to implement as written. It describes persistent OS power-setting changes as if they were process-scoped, promises restoration after hard termination, and combines multiple platform approaches without defining which one owns a request. The implementation roadmap also starts from a completed macOS phase while proposing a later rewrite from the current Swift and Bash implementation into Go.

### Findings to address first

1. **Critical — restoration promises exceed what process signal handlers can guarantee.** `SIGKILL`, power loss, panic, and Windows forced termination bypass cleanup handlers. macOS `pmset` and Windows power-plan settings can outlive Awake. The design needs a durable baseline journal, startup recovery, explicit recovery limits, and exact restoration of the values Awake changed. Do not describe cleanup as guaranteed or immediate after uncatchable termination.

2. **Critical — Windows lid settings can overwrite user preferences.** The proposal changes only the AC lid-close action and always restores it to `Sleep` (`1`). It ignores DC power and the user's original value. Snapshot the active scheme and original AC/DC values before changing anything, restore those exact values, and report policy or privilege failures. `SetThreadExecutionState` does not override lid-close or explicit user sleep; `ES_DISPLAY_REQUIRED` also keeps the display on and should not be enabled by default for a sleep-only request.

3. **High — Linux lid-close support is conditional.** A `systemd-inhibit` command holds locks only while its process lives. A persistent `awake on` request therefore needs a long-lived owner of the inhibitor FD (or a clearly specified service). Desktop environments can own lid handling, and `xset`/`xdg-screensaver` fallbacks do not provide equivalent system-sleep or lid-close protection. Define supported session types and report unsupported capabilities honestly.

4. **High — macOS paths and restoration conflict with project safety guidance.** The `/tmp/awake-$UID` fallback is a predictable shared-temp path. The spec should use a private per-user directory with restrictive permissions, matching the repository guidance. The existing automation design also requires preserving the observed `disablesleep` baseline and recovering stale state; restoring a hard-coded default is unsafe.

5. **High — implementation phases contradict the proposed stack.** The stack promises a Go CLI and tray application, while Linux and Windows phases may use shell/PowerShell and Phase 4 later rewrites them. Phase 1 is the current Swift/Bash macOS app, not a completed cross-platform core. Decide whether Go is a staged replacement or only the shared core before defining deliverables.

6. **High — tray and packaging claims overstate portability.** `getlantern/systray` uses cgo and native Linux GTK/AppIndicator development and runtime libraries. This is incompatible with a universal zero-dependency/single-binary promise, particularly on Linux. Separate shared interaction design from pixel-identical UI and document per-platform packaging dependencies.

7. **High — toolchain and performance targets need grounding.** The `Go 1.23+` floor is stale for this 2026 plan. Choose a currently supported Go release policy. RAM under 20 MB and cold start under 50 ms should be retained only with defined measurement conditions and repeatable benchmarks.

8. **High — acceptance criteria promise outcomes outside Awake's control.** Lid-close behavior, network continuity, enterprise policy, thermal events, and user-initiated sleep vary by platform and hardware. Replace the universal guarantee with a supported-platform/session matrix and explicit manual verification cases.

9. **Medium — persisted state does not model multiple independent request sources.** A single `active` flag and inhibitor PID cannot safely represent CLI, Activity watcher, Schedule, manual toggle, and snooze simultaneously. Reconcile this spec with `2026-11-21-awake-automation-design.md`: independent leases/requests should be arbitrated by one local coordinator, with durable configuration separated from live process-owned inhibitors.

## Recommended architecture decisions

These decisions are the implementation baseline:

- Keep one shared request/arbitration model and CLI contract, with a platform-specific power adapter behind it.
- Use Go 1.26 latest patch for macOS builds while macOS 12 remains supported; Go 1.27+ would raise the runtime floor to macOS 13. Keep the Swift menu-bar UI initially and delegate mutations/status to the Go CLI. Revisit this toolchain policy before Go 1.26 leaves upstream support.
- Model each manual, CLI, schedule, and watcher request as an independent lease with an owner, expiry/liveness rule, and reason. Turning one source off must not cancel another source's request.
- Keep process-scoped inhibitors process-scoped (macOS assertions, Linux inhibitor FD, Windows execution state). Treat persistent system setting changes as separate, journaled operations with an exact baseline and startup recovery.
- Support Linux system-sleep/lid inhibition only on explicitly validated systemd-logind sessions. Any fallback must advertise narrower capability, such as idle/display prevention only.
- On Windows, prefer user-mode execution-state prevention for idle sleep. Make lid-close changes a separately explained, opt-in capability requiring exact AC/DC snapshot and restore. Never claim this overrides user sleep or policy.
- Preserve the existing project rule: private per-user state, narrow privilege boundaries, no telemetry/network, paired install and uninstall, and no staging/committing `AGENTS.md`.
- Require a compatibility gate before CLI migration: build and run the engine on macOS 12 and current macOS, invoke it from the Swift app, and prove serialized concurrent mutations. If that gate fails, revise the engine choice without silently changing the macOS floor.

## Implementation plan

### Phase 0 — Resolve and revise the specification (complete)

1. Define the supported OS versions, Linux session environments, architectures, and capability matrix.
2. Specify request-source precedence, expiry, manual Off behavior, snooze behavior, and `awake run` behavior consistently with the existing automation design.
3. Define state ownership, private paths/permissions, atomic writes and locking, lease liveness, recovery journal, and exact restore rules for each OS.
4. Separate catchable shutdown cleanup from recovery after SIGKILL, crash, reboot, or power loss. State the limits of recovery in product documentation.
5. Select the core/UI migration path, tray dependency policy, Go toolchain floor, packaging targets, and measurable performance targets.
6. Update the cross-platform architecture spec, align the automation design, and record the stage in `project.md`.

**Exit condition met:** user-setting restoration, unsupported capabilities, recovery limits, toolchain/macOS-floor interaction, and delivery order are specified. Remaining work belongs to implementation gates or release readiness.

### Phase 1 — Shared request model and persistence contract

1. Define platform-neutral request and capability interfaces, source identifiers, reason strings, deadlines, and status output.
2. Separate durable settings and recovery snapshots from ephemeral leases and OS inhibitor handles.
3. Implement private state-directory creation, schema versioning, atomic replacement, interprocess locking, stale-owner pruning, and corruption recovery.
4. Specify deterministic arbitration for manual toggle, snooze, CLI, schedule, and Activity requests.

### Phase 2 — macOS adapter and compatibility slice

1. Map the shared model to the existing Swift app and Bash CLI before replacing either component.
2. Keep `IOPMAssertion`/`caffeinate` process-lifetime protection separate from privileged `pmset disablesleep` lid behavior.
3. Journal the original `disablesleep` value, restore exactly, and recover stale state on the next app/CLI launch as documented.
4. Verify setup, install, uninstall, sudoers validation/revocation, and source-checkout versus installed CLI paths.

### Phase 3 — Linux adapter

1. Implement and validate the long-lived systemd-logind inhibitor lifecycle, including close/release behavior.
2. Define whether `awake run <cmd>` uses `systemd-inhibit` as a scoped child or the shared adapter directly; avoid two owners for one request.
3. Detect unavailable logind or conflicting desktop lid handling and surface precise capability/status messages.
4. Package only the explicitly supported distributions and document native tray dependencies.

### Phase 4 — Windows adapter

1. Implement idle-sleep prevention with the narrowest appropriate Win32 execution-state flags and a dedicated owning thread if required by API semantics.
2. Keep display-on behavior separate and disabled unless the user explicitly requests it.
3. For optional lid-close behavior, capture the active power scheme and original AC/DC values, apply changes only after clear user consent, and restore the captured values on normal stop and startup recovery.
4. Handle policy restrictions and failed restoration as visible actionable errors; document limits around lid and explicit user sleep.

### Phase 5 — CLI, tray, and automation integration

1. Preserve the shared `on`, `off`, `status`, and `run` mental model while documenting platform capability differences.
2. Integrate tray/manual controls with the shared coordinator so a source can be stopped independently.
3. Add Activity and Schedule automation only after lease arbitration and recovery work across the first supported platform.
4. Keep UI native where platform conventions require it; share the mascot assets and interaction semantics rather than requiring identical rendering.

### Phase 6 — Packaging, documentation, and release readiness

1. Define a build matrix and CI artifacts for only the supported architectures and platforms.
2. Produce platform-appropriate packages and list native runtime dependencies. Revisit `.dmg`, Linux packages, portable Windows archive, and package-manager distribution as separate release deliverables.
3. Update README, SECURITY, installation/uninstall, recovery, privacy, support matrix, and troubleshooting documentation.
4. Set performance budgets only after measuring representative release builds on named hardware/OS versions.

## Verification plan (for implementation stage)

Do not treat these as completed checks. When implementation begins, add automated coverage for arbitration, state-file concurrency/corruption, expiry, stale owners, and exact baseline restoration. Run a manual platform matrix for normal stop, SIGINT/SIGTERM, forced kill, app crash, reboot recovery, AC/DC transitions, lid close, explicit user sleep, and policy-denied settings. Record OS version, hardware, session type, and which capability is being verified. Do not assert network continuity as a product guarantee.

## Remaining implementation gates

The architecture choices above are resolved defaults, not blockers. The first implementation gate verifies Go 1.26/macOS 12 and Swift-to-CLI ownership. Release signing credentials and exact app catalog mappings remain later implementation/release inputs and do not block the state/arbitration foundation.

## First implementation task

### Task 1 — Prove engine/toolchain compatibility before migration

**Files to inspect or change:** `Makefile`, `src/Awake.swift`, `bin/awake`; add the minimal Go module/CLI entry point only in the implementation task on its feature branch.

**Required evidence:**

- Build the Go 1.26 latest patch binary for macOS `arm64` and `amd64` with a deployment target compatible with macOS 12.
- Run the CLI on macOS 12 and a current macOS release; verify JSON status output and a harmless command path.
- Invoke `awake status --json` and a state mutation from the Swift app without letting Swift or Bash write state directly.
- Exercise two concurrent CLI mutations and verify the lock serializes them and the state remains valid.
- Record native build and app-bundle implications for the selected tray dependency; do not add the Linux tray dependency to the macOS engine target.

**Gate:** proceed to state migration only when all evidence passes. If Go 1.26 cannot meet macOS 12 behavior or the Swift-to-CLI boundary is unreliable, stop and revise this architecture plan before implementing platform adapters.

## Git execution rules

- Start the engine compatibility work on a dedicated feature branch; continue with separate branches for Linux, Windows, packaging, and unrelated chores.
- Commit each coherent deliverable separately: compatibility spike, state contract, arbitration, macOS adapter, Linux adapter, Windows adapter, UI integration, and packaging/docs.
- Do not stage or commit the root `AGENTS.md`. Follow `docs/GIT_WORKFLOW.md`.
