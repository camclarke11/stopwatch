#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
folder=$(mktemp -d)
trap 'rm -rf -- "$folder"' EXIT
xcrun swiftc Source/TimerState.swift Tests/main.swift -o "$folder/tests" -module-cache-path /tmp/stopwatch-module-cache
"$folder/tests"
/bin/zsh -n build.sh install.sh Scripts/git-update.sh Scripts/replace-app.sh
