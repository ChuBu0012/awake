# Awake

<p align="center">
  <img src="config/AppIcon_1024.png" width="96" height="96" alt="Awake icon" style="border-radius: 20px;">
</p>

<p align="center">
  <strong>Keep your Mac awake during long tasks — even with the lid closed.</strong><br>
  A lightweight menu bar app and CLI for macOS, built for AI agent workflows, background builds, and long-running scripts.
</p>

<p align="center">
  <strong>English</strong> | <a href="README.th.md">ภาษาไทย</a>
</p>

<p align="center">
  <a href="https://github.com/ChuBu0012/awake/releases"><img src="https://img.shields.io/badge/release-v1.0.0-blue.svg?style=flat-square" alt="Release v1.0.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg?style=flat-square" alt="macOS 12+">
  <img src="https://img.shields.io/badge/architecture-Universal%20(Apple%20Silicon%20%2F%20Intel)-orange.svg?style=flat-square" alt="Universal Apple Silicon / Intel">
  <img src="https://img.shields.io/badge/security-Zero%20Sudo%20by%20Default-success.svg?style=flat-square" alt="Zero Sudo Default">
</p>

<p align="center">
  <a href="https://github.com/ChuBu0012/awake/releases/latest/download/Awake.dmg">
    <img src="https://img.shields.io/badge/Download-Awake.dmg-2563eb?style=for-the-badge&logo=apple&logoColor=white" alt="Download Awake.dmg" height="38">
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/ChuBu0012/awake/releases/latest/download/Awake.zip">
    <img src="https://img.shields.io/badge/Download-Awake.zip-64748b?style=for-the-badge&logo=apple&logoColor=white" alt="Download Awake.zip" height="38">
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/ChuBu0012/awake/releases">
    <img src="https://img.shields.io/badge/All%20Releases-GitHub-181717?style=for-the-badge&logo=github&logoColor=white" alt="All Releases" height="38">
  </a>
</p>

---

## Quick Start & Installation

> **System Requirements**: macOS 12.0 (Monterey) or later. Universal binary supporting both Apple Silicon (M1/M2/M3/M4) and Intel Macs.

| Method | Download Link | Description |
| :--- | :--- | :--- |
| **Disk Image (`.dmg`)** | [**Download Awake.dmg** (Recommended)](https://github.com/ChuBu0012/awake/releases/latest/download/Awake.dmg) | Standard macOS installer. Drag and drop into `/Applications`. |
| **ZIP Archive (`.zip`)** | [**Download Awake.zip**](https://github.com/ChuBu0012/awake/releases/latest/download/Awake.zip) | Portable archive. Extract and run directly. |
| **GitHub Releases** | [**View Releases & Assets**](https://github.com/ChuBu0012/awake/releases) | All release tags, assets, and changelogs. |

---

### Option 1: Install via Disk Image (`.dmg`) — Recommended

1. Download [**`Awake.dmg`**](https://github.com/ChuBu0012/awake/releases/latest/download/Awake.dmg).
2. Double-click `Awake.dmg` to open the installer window.
3. Drag **`Awake.app`** into your **`/Applications`** folder.
4. Launch **Awake** from Spotlight (<kbd>⌘</kbd> + <kbd>Space</kbd>) or Launchpad.

---

### Option 2: Install via ZIP Archive (`.zip`)

1. Download [**`Awake.zip`**](https://github.com/ChuBu0012/awake/releases/latest/download/Awake.zip).
2. Double-click `Awake.zip` to uncompress it.
3. Move **`Awake.app`** into `/Applications` (or run directly).

---

### Security & First Launch (Gatekeeper)

#### Why does macOS show a security warning?

When you download Awake from GitHub or the web, macOS automatically flags it with an internet quarantine attribute (`com.apple.quarantine`). 

By default, Apple's Gatekeeper system requires distributed Mac apps to be signed with a paid Apple Developer ID certificate ($99/year) and notarized by Apple's cloud servers. Because **Awake is a 100% free, independent open-source project**, it is signed with a standard local Ad-hoc signature rather than a paid Apple license.

As a result, macOS displays a generic alert:
> *"Awake cannot be opened because Apple cannot check it for malicious software"* or *"Awake is from an unidentified developer"*.

**This is a standard macOS Gatekeeper check for unsigned open-source software, not a security vulnerability.**

#### Our Security & Privacy Guarantees
- **100% Auditable Code:** Every line of Awake is open source in this repository under the MIT license. You can inspect, audit, or build it yourself.
- **Zero Sudo for Everyday Use:** Standard sleep prevention relies on Apple's native `/usr/bin/caffeinate` tool running entirely under your regular user permissions.
- **Narrow Sudoers Scope:** If you enable lid-closed support, Awake only requests permission to run two explicit commands (`pmset -a disablesleep 0` and `1`). It cannot run arbitrary shell commands or access user data.
- **Completely Offline:** Zero telemetry, zero analytics, zero external network requests.

#### How to open Awake on first launch (one-time only):
1. In Finder, open your **`/Applications`** folder.
2. **Right-click** (or <kbd>Control</kbd>-click) **`Awake.app`** and select **Open**.
3. In the confirmation dialog, click **Open**.

> **For macOS 15 Sequoia (if "Open" does not appear in the right-click menu):**
> - Go to **System Settings > Privacy & Security**, scroll down to the **Security** section, and click **"Open Anyway"**.
> - Or remove the quarantine attribute directly via Terminal (one command):
>   ```bash
>   xattr -cr /Applications/Awake.app
>   ```

---

### Option 3: Build from Source (For Developers & CLI Users)

```bash
git clone https://github.com/ChuBu0012/awake.git
cd awake
make install
```

This builds the native app to `~/Applications` and installs the CLI to `~/.local/bin/awake`. Ensure `~/.local/bin` is in your `$PATH`.

> **CLI Shortcut for DMG / ZIP Users:**  
> The CLI binary is included inside `Awake.app`. You can link it without installing Go:
> ```bash
> mkdir -p ~/.local/bin && ln -sf /Applications/Awake.app/Contents/Resources/awake ~/.local/bin/awake
> ```

---

## Why Awake?

| Problem with traditional tools | How Awake solves it |
|---|---|
| MacBook goes to sleep as soon as you close the lid | Optional clamshell mode (`pmset -a disablesleep 1`) with automatic baseline restoration when tasks finish |
| "App is open" rules keep your Mac awake all day even when idle | CPU-aware watcher: stays awake only when your build or agent is actively working (>5% CPU) |
| Forgot sleep prevention was on; battery drains in your backpack | Hard 2-hour timeout on battery with lid closed; auto-pauses below 20% battery |
| Have to remember to click a menu bar icon before leaving | `awake run <cmd>` or `awake hold` directly in your scripts and agent hooks |

---

## Features

- **Zero sudo for normal use**: Standard sleep prevention uses native macOS power assertions (`/usr/bin/caffeinate`) with normal user permissions.
- **Lid-closed support**: Keeps long-running builds, downloads, and AI agent workflows active when your MacBook screen is folded down.
- **Smart worker detection**: Monitors specified developer tools (VS Code, Cursor, Node, Python, Xcode, Docker) and only holds sleep while they are actively computing. Releases sleep immediately when the process exits.
- **Backpack protection**: Hard 2-hour safety limit when operating on battery with the lid closed to prevent overheating and battery depletion in bags.
- **Battery & thermal guards**: Automatically suspends sleep lock below 20% battery or during high hardware thermal states.
- **Menu bar popover & shortcuts**: Real-time timer countdown, current sleep status reason, and native shortcuts (<kbd>⌘</kbd><kbd>T</kbd> toggle, <kbd>⌘</kbd><kbd>,</kbd> settings, <kbd>⌘</kbd><kbd>Q</kbd> quit).
- **100% private**: No network access, no telemetry, no analytics.

---

## Keyboard Shortcuts

When Awake is running:

| Shortcut | Action | Description |
|:---:|:---|:---|
| <kbd>⌘</kbd> <kbd>T</kbd> | **Toggle Sleep Lock** | Turn sleep prevention On / Off immediately |
| <kbd>⌘</kbd> <kbd>,</kbd> | **Preferences…** | Open the Settings window |
| <kbd>⌘</kbd> <kbd>Q</kbd> | **Quit Awake** | Safely release all assertions and restore system sleep |

---

## AI Agent & Script Integration

Awake provides two patterns for AI agents (Claude Code, Cursor, Windsurf, OpenHands) and long-running shell scripts:

### Pattern 1: Command Wrapper (`awake run`)
Wraps any command. Acquires a sleep lease, runs the command, and releases the lease immediately upon completion:

```bash
# Compiles and tests
awake run npm run build

# Docker or compiler tasks
awake run docker compose up --build

# AI agent sessions
awake run claude
```

### Pattern 2: Hold & Release (`awake hold` / `awake release`)
Ideal for multi-step workflows, agent hooks, or Python/Node scripts:

#### Shell
```bash
# Acquire a lease with a 45-minute safety ceiling
awake hold "nightly-agent-sync" --ttl 45m

# Run your tasks...
python3 run_agent_workflow.py

# Release when done
awake release "nightly-agent-sync"
```

#### Python
```python
import subprocess

def keep_awake(session_id: str, ttl: str = "30m"):
    subprocess.run(["awake", "hold", session_id, "--ttl", ttl], check=True)

def release_awake(session_id: str):
    subprocess.run(["awake", "release", session_id], check=True)

# Usage:
keep_awake("agent-session-1", ttl="1h")
try:
    run_agent_task()
finally:
    release_awake("agent-session-1")
```

#### Node.js / TypeScript
```typescript
import { execFileSync } from "child_process";

export function holdSleep(leaseId: string, ttl = "30m"): void {
  execFileSync("awake", ["hold", leaseId, "--ttl", ttl]);
}

export function releaseSleep(leaseId: string): void {
  execFileSync("awake", ["release", leaseId]);
}
```

---

## CLI Reference

The `awake` command-line tool manages sleep leases and system settings:

| Command | Usage | Description |
|---|---|---|
| `awake on [duration]` | `awake on 2h` / `awake on indefinite` | Turn on manual sleep lock (`30m`, `1h`, `2h`, `4h`, `8h`, `indefinite`) |
| `awake off` | `awake off` | Turn off manual sleep lock; background automations continue |
| `awake status [--json]` | `awake status --json` | Show active assertions, leases, battery level, and lock status |
| `awake run <cmd...>` | `awake run make test` | Run command inside an isolated, self-releasing sleep lease |
| `awake hold <id> [--ttl <dur>]` | `awake hold agent-1 --ttl 1h` | Acquire a named sleep lease with automatic TTL safety expiry |
| `awake release <id>` | `awake release agent-1` | Release a named sleep lease |
| `awake rule ...` | `awake rule process p1 "Build" "ninja"` | Manage application and background process rules |
| `awake set <guard> on\|off` | `awake set battery-guard on` | Toggle `battery-guard` or `lid-support` |
| `awake verify` | `awake verify` | Check live kernel power assertions in real time |
| `awake setup` | `awake setup` | Configure passwordless sudoers for `pmset` (lid-closed mode) |
| `awake recover` | `awake recover` | Restore system sleep settings if a previous session crashed |

### Verifying Sleep Prevention

To verify that your Mac stays awake during background execution:

```bash
# 1. Run the test counter for 60 seconds
awake run ./scripts/sleep-test-counter.sh 60

# 2. Or run continuously (Ctrl+C to stop)
./scripts/sleep-test-counter.sh
```

The script records a timestamp every second. If macOS sleeps, a time gap is detected and reported when the system wakes.

---

## How Lid-Closed Support Works

By default, macOS forces laptops to sleep when the lid is closed unless connected to external power and a monitor.

To keep your MacBook awake on battery with the lid closed, Awake temporarily sets `pmset -a disablesleep 1`. This requires a strictly-scoped sudoers entry configured via `awake setup` (or from the app):

```sudoers
username ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- **Narrow scope**: Only allows those two explicit `pmset` commands. Awake cannot run arbitrary commands or shells.
- **Automatic restoration**: Awake records your original sleep state before modifying it and restores it the instant all tasks finish.
- **Clean removal**: Remove the sudoers file anytime with `sudo rm -f /etc/sudoers.d/awake` or `make uninstall`.

---

## Uninstallation

To completely remove Awake, its CLI, local configurations, and sudoers rules:

```bash
make uninstall
```

Or manually:
```bash
rm -f ~/.local/bin/awake
rm -rf ~/Applications/Awake.app ~/.config/awake
sudo rm -f /etc/sudoers.d/awake
sudo visudo -c
```

---

## Contributing

Contributions, bug reports, and suggestions are welcome!

- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Support & Questions](SUPPORT.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Changelog](CHANGELOG.md)

---

## License

Awake is open source under the [MIT License](LICENSE).
