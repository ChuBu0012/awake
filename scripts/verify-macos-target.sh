#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: verify-macos-target.sh APP_EXECUTABLE CLI_EXECUTABLE INFO_PLIST" >&2
    exit 2
fi

app_executable=$1
cli_executable=$2
info_plist=$3
expected_minimum="12.0"

minimum_version() {
    otool -l "$1" | awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { build_version = 1; next }
        build_version && $1 == "minos" { print $2; exit }
    '
}

app_minimum=$(minimum_version "$app_executable")
cli_minimum=$(minimum_version "$cli_executable")
plist_minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")

for item in "app:$app_minimum" "cli:$cli_minimum" "Info.plist:$plist_minimum"; do
    name=${item%%:*}
    actual=${item#*:}
    if [[ "$actual" != "$expected_minimum" ]]; then
        echo "ERROR: $name minimum is '$actual'; expected macOS $expected_minimum" >&2
        exit 1
    fi
done

echo "macOS deployment target verified: app, CLI, and Info.plist all require $expected_minimum or later."
