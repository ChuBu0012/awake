# Changelog

User-visible changes to Awake are recorded here. This project follows the general format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-22

### Added
- **Manual Sleep Lock**: Preset durations (`30m`, `1h`, `2h`, `4h`, `8h`, `∞ Indefinite`) with live countdown timer and prominent reason banner.
- **Smart Background Worker Detection**: CPU-aware watcher with >5% threshold and 60-second sustained idle debounce; immediate 0s release on process exit.
- **Backpack Clamshell Protection**: Hard 2-hour timeout safety ceiling when lid is closed on battery to prevent heat and battery drain.
- **Hardware Guards**:
  - Battery Guard auto-pause below 20% on battery power.
  - Thermal Guard auto-pause on `.serious` or `.critical` temperature pressure.
- **Clamshell Hardware Sleep Lock**: Optional `pmset -a disablesleep 1|0` execution with narrowly scoped sudoers rule and guaranteed baseline restoration.
- **CLI & Agent Hooks**:
  - `awake run <cmd...>` with child command process isolation and self-cleaning sleep leases.
  - `awake hold <id> [--ttl <duration>]` and `awake release <id>` for autonomous AI agent pipelines.
  - `awake verify` live power assertion diagnostic checker.
- **Native Keyboard Shortcuts**:
  - `⌘T` Toggle Sleep Lock.
  - `⌘,` Open Settings.
  - `⌘Q` Quit Awake.
- **Native macOS Settings Window**:
  - General Preferences with Login Item (LaunchAgent) management.
  - Automations manager with developer process presets (VS Code, Cursor, Claude, Node, Python, Xcode, Docker).
  - System Test tab with live pmset assertion inspector and sleep lock verification.
  - About Awake tab.
- **Distribution Packaging**: Distributable `.dmg` with Applications symlink and `.zip` archive via `make dmg` and `make zip`.
- **Open Source Foundation**: MIT License, security policy, contributing guidelines, and reproducible build system.
