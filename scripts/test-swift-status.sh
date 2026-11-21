#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/awake-status-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT

mkdir -p "${TMPDIR:-/tmp}/swift-module-cache"
swiftc -parse-as-library \
    -module-cache-path "${TMPDIR:-/tmp}/swift-module-cache" \
    "$repo_root/src/AwakeStatus.swift" \
    "$repo_root/tests/swift/AwakeStatusTests.swift" \
    -o "$test_binary"
"$test_binary"
