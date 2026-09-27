#!/bin/zsh
# Complete the one-time Stopwatch.app to Stewie.app rename after the old process exits.
set -euo pipefail
legacy=$1
destination=$2
app_pid=$3
[[ "${legacy:t}" == Stopwatch.app && "${destination:t}" == Stewie.app && "${legacy:h}" == "${destination:h}" && "$app_pid" =~ '^[0-9]+$' ]] || exit 1
[[ -d "$legacy" && -f "$legacy/Contents/Resources/GitCheckout.txt" && ! -e "$destination" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$legacy/Contents/Info.plist")" == Stewie ]] || exit 1
if [[ "${0:h:t}" == stewie-migration-* ]]; then trap 'rm -rf -- "${0:h}"' EXIT; fi
for attempt in {1..1000}; do
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then print -u2 'The old app did not quit.'; exit 1; fi
[[ ! -e "$destination" ]] || { print -u2 'Stewie.app already exists.'; exit 1; }
mv -- "$legacy" "$destination"
if [[ "${STEWIE_TEST_NO_LAUNCH:-0}" != 1 ]]; then
  if ! /usr/bin/open "$destination"; then
    mv -- "$destination" "$legacy"
    /usr/bin/open "$legacy" || true
    exit 1
  fi
fi
