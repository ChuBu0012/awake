# Awake Smooth Menu Bar Popover — Design

## Intent

Make Awake feel responsive and calm when opened from the menu bar. The current standard `NSMenu` has limited control over content transitions, and the app reconstructs automation rows after every five-second status refresh, even when nothing changed.

## Goals

- Replace the standard menu with an anchored, transient `NSPopover` containing a SwiftUI interface.
- Add a short system popover entrance/exit and subtle state/list transitions; skip custom content motion when Reduce Motion is enabled.
- Keep menu-bar state, controls, automations, Battery Guard, and Quit available with the current behavior.
- Avoid visible changes when a poll returns the same status. Refresh the UI only when meaningful state changes.
- Follow the current Light/Dark appearance using system semantic colors and materials.

## Non-goals

- Do not change the shared Go engine, CLI commands, arbitration, persistence, sleep behavior, or setup flow.
- Do not add new automation capabilities or a settings window.
- Do not add a third-party UI or animation dependency.

## Approaches

1. **Keep `NSMenu`:** Diff status before updating and rebuild Automation rows only when rules change. This is the smallest change and retains the familiar system menu, but custom transitions inside it remain unavailable.
2. **Use an `NSPopover` with SwiftUI (chosen):** Keep the menu-bar anchor and actions, but render a compact custom surface that can animate meaningful status and rule changes. This is a focused UI replacement and matches the requested transitions.

The user selected the popover approach and asked to begin implementation.

## Interaction and motion

- Clicking the menu-bar item toggles the transient popover. Clicking outside or pressing Escape closes it.
- Keep the current hierarchy: summary and active reason first, primary Awake toggle and duration next, Automation controls and rules, Battery Guard, then Quit.
- Use the native popover animation for open/close. Use a brief opacity/vertical transition for inserted or removed rule rows and state sections; do not animate layout dimensions or reorder unrelated controls.
- Polls that return equivalent state must not animate or change layout. The popover stays interactive while state updates arrive.
- Respect Reduce Motion for SwiftUI content transitions. Use semantic system colors so both appearances remain legible.
- Keep keyboard shortcuts and accessible names/roles for all controls.

## Technical shape

- Retain `NSStatusItem` as the anchor and attach an `NSPopover` with transient behavior.
- Host the SwiftUI root view with `NSHostingController`.
- Move UI state and CLI actions behind a small observable view model; keep command execution off the main thread and publish state changes on the main queue.
- Compare decoded status before publishing. Update status fields independently where needed, and rebuild visible rule content only when the rule collection changes.
- Keep the app's bundled CLI preference and existing error details.
- Maintain the macOS 12 deployment target and avoid SwiftUI APIs introduced after macOS 12.

## Acceptance checks

- The app builds for macOS 12 and `make test` passes.
- The popover opens/closes from the menu-bar anchor and closes on outside click/Escape.
- Manual On/Off, duration, add/pause/remove rules, Battery Guard, and Quit continue to invoke the same CLI commands.
- Repeated identical status polls do not publish state changes or recreate rows.
- Rule insertion/removal and active status changes transition smoothly; Reduce Motion disables custom content transitions.
- Light and Dark appearances remain readable, and keyboard/screen-reader semantics remain available.

## Trade-offs

- A custom popover gives control over content transitions but requires maintaining a SwiftUI view alongside the AppKit status item.
- Popover presentation animation is system-managed. Apple documents `NSPopover.animates` as a hint and does not guarantee every behavior will animate; content transitions remain controlled by SwiftUI.
- Manual interaction review is required because build tests cannot judge perceived motion quality.
