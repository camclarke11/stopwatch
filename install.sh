#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
checkout=$PWD
xcrun --find swiftc >/dev/null 2>&1 || { print 'Install Apple Command Line Tools with: xcode-select --install'; exit 1; }
[[ -d .git ]] || { print 'Clone the Git repository first, rather than downloading a source ZIP.'; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { print 'This checkout needs an origin remote for updates.'; exit 1; }
if pgrep -x Stopwatch >/dev/null; then print 'Quit Stopwatch before installing.'; exit 1; fi
STOPWATCH_CHECKOUT="$checkout" /bin/zsh ./build.sh
mkdir -p "$HOME/Applications"
# PID 0 would refer to a process group. Find a PID that is not in use.
unused_pid=999999
while kill -0 "$unused_pid" 2>/dev/null; do unused_pid=$((unused_pid+1)); done
/bin/zsh Scripts/replace-app.sh "$checkout/Stopwatch.app" "$HOME/Applications/Stopwatch.app" "$unused_pid"
print 'Installed. Use Stopwatch → Check for Updates… for future tagged releases.'
