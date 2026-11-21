#!/usr/bin/env bash
# scripts/setup-sudoers.sh
# Sets up passwordless sudo for `pmset -a disablesleep` only.

set -euo pipefail
umask 077

CURRENT_USER=$(id -un)
SUDOERS_FILE="/etc/sudoers.d/awake"
TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/awake-sudoers.XXXXXX")
trap 'rm -f "$TEMP_FILE"' EXIT HUP INT TERM

RESTORE_PENDING=0
RESTORE_VALUE=""
restore_sleep_setting() {
    if [[ "$RESTORE_PENDING" == "1" ]]; then
        sudo -n /usr/bin/pmset -a disablesleep "$RESTORE_VALUE" 2>/dev/null || true
        RESTORE_PENDING=0
    fi
}
trap 'restore_sleep_setting; rm -f "$TEMP_FILE"' EXIT

if [[ ! "$CURRENT_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: Current username contains characters that cannot be safely written to sudoers." >&2
    exit 1
fi

echo "==> Configuring passwordless sudo for Awake..."
echo "User: $CURRENT_USER"
echo "Target rule: /usr/bin/pmset -a disablesleep [0|1]"

# Create temp sudoers content
cat <<EOF > "$TEMP_FILE"
# Awake permissions - allow sleep toggle without password prompt
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
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
ORIGINAL_SLEEP_DISABLED=$(/usr/bin/pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')
if [[ "$ORIGINAL_SLEEP_DISABLED" != "0" && "$ORIGINAL_SLEEP_DISABLED" != "1" ]]; then
    echo "NOTE: Setup completed, but the original SleepDisabled value could not be read for a safe permission check."
elif sudo -n /usr/bin/pmset -a disablesleep 1 2>/dev/null; then
    RESTORE_VALUE="$ORIGINAL_SLEEP_DISABLED"
    RESTORE_PENDING=1
    restore_sleep_setting
    echo "==> Sudoers check PASSED! You can now toggle sleep without passwords."
else
    echo "NOTE: Setup completed, but sudo -n check requires password or session refresh."
fi
