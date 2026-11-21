#!/usr/bin/env bash
# scripts/toggle-appearance.sh
# Toggle or query macOS system Dark Mode / Light Mode for quick UI contrast verification

set -euo pipefail

cmd="${1:-toggle}"

case "$cmd" in
    dark)
        osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'
        echo "==> macOS Appearance set to: Dark Mode"
        ;;
    light)
        osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to false'
        echo "==> macOS Appearance set to: Light Mode"
        ;;
    toggle)
        is_dark=$(osascript -e 'tell app "System Events" to tell appearance preferences to get dark mode')
        if [ "$is_dark" = "true" ]; then
            osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to false'
            echo "==> macOS Appearance switched to: Light Mode"
        else
            osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'
            echo "==> macOS Appearance switched to: Dark Mode"
        fi
        ;;
    status)
        is_dark=$(osascript -e 'tell app "System Events" to tell appearance preferences to get dark mode')
        if [ "$is_dark" = "true" ]; then
            echo "Dark Mode"
        else
            echo "Light Mode"
        fi
        ;;
    *)
        echo "Usage: $0 [dark|light|toggle|status]" >&2
        exit 1
        ;;
esac
