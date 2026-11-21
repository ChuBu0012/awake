#!/usr/bin/env bash
# scripts/setup-sudoers.sh
# Sets up passwordless sudo for `pmset -a disablesleep` only.

set -euo pipefail
umask 077

TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    CONSOLE_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "")
    if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
        TARGET_USER="$CONSOLE_USER"
    else
        TARGET_USER=$(id -un)
    fi
fi

SUDOERS_FILE="/etc/sudoers.d/awake"
TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/awake-sudoers.XXXXXX")
trap 'rm -f "$TEMP_FILE"' EXIT HUP INT TERM

if [[ ! "$TARGET_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: Target username '$TARGET_USER' contains characters that cannot be safely written to sudoers." >&2
    exit 1
fi

echo "==> Configuring passwordless sudo for Awake..."
echo "Target User: $TARGET_USER"
echo "Target rule: /usr/bin/pmset -a disablesleep [0|1]"

# Create temp sudoers content
cat <<EOF > "$TEMP_FILE"
# Awake permissions - allow sleep toggle without password prompt
$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF

# Validate syntax with visudo
if ! sudo visudo -cf "$TEMP_FILE"; then
    echo "ERROR: Generated sudoers syntax is invalid. Aborting." >&2
    exit 1
fi

# Move to /etc/sudoers.d and set strict permissions
sudo mkdir -p /etc/sudoers.d
sudo cp "$TEMP_FILE" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"
echo "==> Successfully installed $SUDOERS_FILE!"

echo "==> Testing sudo pmset permission without password..."
ORIGINAL_SLEEP_DISABLED=$(/usr/bin/pmset -g 2>/dev/null | awk '$1 == "SleepDisabled" { print $2; exit }' || echo "0")
if [[ "$ORIGINAL_SLEEP_DISABLED" != "0" && "$ORIGINAL_SLEEP_DISABLED" != "1" ]]; then
    ORIGINAL_SLEEP_DISABLED="0"
fi

if sudo -u "$TARGET_USER" sudo -n /usr/bin/pmset -a disablesleep "$ORIGINAL_SLEEP_DISABLED" 2>/dev/null || sudo -n /usr/bin/pmset -a disablesleep "$ORIGINAL_SLEEP_DISABLED" 2>/dev/null; then
    echo "==> Sudoers check PASSED! $TARGET_USER can now toggle sleep without passwords."
else
    echo "NOTE: Setup completed, but sudo -n check requires password or session refresh."
fi
