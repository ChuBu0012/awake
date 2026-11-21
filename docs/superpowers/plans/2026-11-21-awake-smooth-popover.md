# Awake Smooth Menu Bar Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the jitter-prone menu-bar `NSMenu` with a smooth, accessible SwiftUI `NSPopover` while preserving existing Awake actions.

**Architecture:** Keep `NSStatusItem` and the Go CLI. Host a SwiftUI root view in a transient `NSPopover`; an observable model owns decoded status and dispatches CLI operations. Polling remains at the current cadence, but equivalent status snapshots do not trigger view updates. The popover uses native appearance plus restrained, Reduce Motion-aware content transitions.

**Tech Stack:** Swift, AppKit, SwiftUI, Go CLI (unchanged), macOS 12 minimum.

**Spec:** `docs/superpowers/specs/2026-11-21-awake-smooth-popover-design.md`

## Global Constraints

- Preserve the macOS 12 minimum deployment target.
- Keep sleep-prevention behavior and state mutations in the shared Go engine/CLI.
- Keep the bundled CLI as the first CLI candidate.
- Add no external UI or animation dependency.
- Keep CLI work off the main thread; update observable UI state on the main thread.
- Do not stage or commit root `AGENTS.md`.

## Review Focus

- An unchanged five-second poll must not republish equivalent status or rebuild rules; verify by a status equality/update seam.
- Manual On/Off, expiration, and snooze must remain routed to the same CLI commands; verify through the view-model action mapping and CLI smoke checks.
- Automation rule add/enable/disable/remove must remain available and dynamic rows must not be recreated on unrelated state updates; verify the view's rule identity/update behavior.
- Battery Guard and Quit must retain their current command and termination behavior; verify menu actions and app smoke launch.
- Reduce Motion and Light/Dark appearances must stay usable; inspect the environment-driven animation policy and native semantic colors.

---

### Task 1: Model and deduplicate UI state updates

**Files:**
- Modify: `src/Awake.swift`
- Create: `src/AwakeStatus.swift`
- Create: `src/AwakePopoverModel.swift`
- Create: `tests/swift/AwakeStatusTests.swift`
- Create: `scripts/test-swift-status.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces `AwakeStatus: Decodable, Equatable` and `AwakePopoverModel: ObservableObject` for the SwiftUI view.
- The model exposes current status, selected duration, `refresh()`, and the existing CLI actions; all process execution stays on the serial utility queue.

- [ ] Write `AwakeStatusTests` for equal snapshots and snapshots that differ in active state, battery state, or rule collection.
- [ ] Run `scripts/test-swift-status.sh` and confirm it fails because `AwakeStatus` / `StatusUpdatePolicy` are not implemented yet.
- [ ] Implement `AwakeStatus: Decodable, Equatable` and `StatusUpdatePolicy.shouldPublish(previous:next:)` in `src/AwakeStatus.swift`; rerun the test and confirm it passes.
- [ ] Extract status decoding, CLI lookup, command execution, refresh, and action dispatch from `AppDelegate` into `AwakePopoverModel` without changing CLI arguments.
- [ ] Compare decoded status before publishing; equivalent snapshots must not trigger view updates or row reconstruction.
- [ ] Keep the last successful status visible if a later refresh fails, while surfacing actionable command errors for user initiated actions.
- [ ] Add the Swift status test to `make test`; build with the macOS 12 deployment target and inspect the model/action diff before proceeding.

### Task 2: Replace `NSMenu` with an animated SwiftUI popover

**Files:**
- Modify: `src/Awake.swift`
- Create: `src/AwakePopoverView.swift`
- Modify: `Makefile`

**Interfaces:**
- `AppDelegate` owns the `NSStatusItem`, `NSPopover`, and `NSHostingController<AwakePopoverView>`.
- `AwakePopoverView` consumes `@ObservedObject var model: AwakePopoverModel` and renders status, duration, automations, Battery Guard, and Quit.

- [ ] Make the status item button toggle a transient `NSPopover` anchored to the button; enable the native popover presentation animation.
- [ ] Render current status, active reason, primary toggle, duration, Automation add/list controls, Battery Guard, and Quit with SwiftUI native controls and semantic colors.
- [ ] Animate only meaningful status/row insertion and removal with short opacity/vertical transitions; honor `accessibilityReduceMotion` and keep controls interactive during animation.
- [ ] Preserve app picker and schedule/process prompts by bridging to the existing AppKit panels/alerts.
- [ ] Add both Swift files to the Swift build inputs and verify the app and CLI retain `minos 12.0`.
- [ ] Run `make test` and launch the built app on macOS 12.7.6; verify popover open/close, outside click/Escape, and that an unchanged refresh does not visibly reflow content.

### Task 3: Verify interactions and finalize branch

**Files:**
- Modify: `project.md`
- Review: `src/Awake.swift`, `src/AwakePopoverModel.swift`, `src/AwakePopoverView.swift`, `Makefile`

- [ ] Run `make test` and build the `.app` for the macOS 12 deployment target.
- [ ] Run the app on macOS 12.7.6 and verify open/close, Escape/outside dismissal, Manual On/Off, duration, Automation actions, Battery Guard, and Quit.
- [ ] Inspect the UI under Light/Dark appearance and Reduce Motion; confirm repeated identical polling causes no visible row/layout jitter.
- [ ] Update `project.md` with the popover implementation and verification status.
- [ ] Commit the UI implementation in focused commits, push `fix/prefer-bundled-cli`, verify the remote branch, then remove only the associated worktree.
