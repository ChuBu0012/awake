#!/usr/bin/env bash
# scripts/clean-run.sh
# Stops Awake, cleans previous runtime state and preferences, rebuilds, and launches fresh from build/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "==> 1. Stopping running Awake instances..."
killall Awake 2>/dev/null || true

# Optional: pass --reset-permission to also test the Touch ID / Admin permission prompt from scratch
if [[ "${1:-}" == "--reset-permission" ]]; then
    echo "==> Removing sudoers rule to test GUI permission prompt..."
    sudo rm -f /etc/sudoers.d/awake
fi

echo "==> 2. Resetting runtime state, rules, and preferences..."
rm -rf ~/.config/awake ~/.config/mac-awake
rm -f ~/Library/Preferences/com.most-too.Awake.plist
rm -rf /tmp/awake* /tmp/mac-awake*

echo "==> 3. Rebuilding fresh binary and app bundle..."
make clean
make build

echo "==> 4. Launching fresh build/Awake.app..."
open build/Awake.app

echo ""
echo "========================================================"
echo "✅ Clean run complete! Awake is running from: build/Awake.app"
echo "• Default duration: 1 hour"
echo "• CLI tool: ./build/awake status"
if [[ "${1:-}" == "--reset-permission" ]]; then
    echo "• Permission reset: Click 'Grant…' in the popover to test GUI Touch ID prompt."
fi
echo "========================================================"
