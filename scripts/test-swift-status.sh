#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/awake-status-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT

swiftc -parse-as-library \
    "$repo_root/src/AwakeStatus.swift" \
    "$repo_root/tests/swift/AwakeStatusTests.swift" \
    -o "$test_binary"
"$test_binary"
