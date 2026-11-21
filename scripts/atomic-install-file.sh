#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: atomic-install-file.sh SOURCE DESTINATION MODE" >&2
    exit 2
fi

source_file=$1
destination=$2
mode=$3
destination_dir=$(dirname "$destination")
destination_name=$(basename "$destination")

if [[ ! -f "$source_file" || -d "$destination" || ! "$mode" =~ ^0?[0-7]{3}$ ]]; then
    echo "ERROR: source, destination, or mode is invalid" >&2
    exit 2
fi

mkdir -p "$destination_dir"
temporary_dir=$(mktemp -d "${destination_dir}/.awake-install.XXXXXX")
temporary_file="${temporary_dir}/${destination_name}"
cleanup() {
    if [[ -d "$temporary_dir" && ! -e "$temporary_file" ]]; then
        rmdir "$temporary_dir" 2>/dev/null || true
    fi
}
trap cleanup EXIT

install -m "$mode" "$source_file" "$temporary_file"
mv -f "$temporary_file" "$destination"
rmdir "$temporary_dir"
temporary_dir=""
trap - EXIT
