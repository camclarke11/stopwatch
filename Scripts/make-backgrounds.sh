#!/bin/zsh
# Regenerate the painted-*.jpg wallpapers in Source/Backgrounds. Output is deterministic.
set -euo pipefail
cd "${0:A:h:h}"
folder=$(mktemp -d)
trap 'rm -rf -- "$folder"' EXIT
./Scripts/swiftc.sh -O Scripts/make-backgrounds.swift -o "$folder/make-backgrounds"
"$folder/make-backgrounds" Source/Backgrounds "$@"
