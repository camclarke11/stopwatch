#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
folder=$(mktemp -d)
trap 'rm -rf -- "$folder"' EXIT
./Scripts/swiftc.sh Source/TimerState.swift Tests/main.swift -o "$folder/tests"
"$folder/tests"
/bin/zsh -n build.sh install.sh Scripts/git-update.sh Scripts/replace-app.sh
if command -v node >/dev/null; then node Tests/pixel-cat.cjs; fi
