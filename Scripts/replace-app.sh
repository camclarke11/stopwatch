#!/bin/zsh
# Run outside the app being replaced, after a successful build.
set -euo pipefail
incoming=$1
destination=$2
app_pid=$3
[[ "$destination" == *.app && -d "$incoming" && "$app_pid" =~ '^[0-9]+$' ]] || exit 1
parent=${destination:h}
replacement=$(mktemp -d "$parent/.stopwatch-install.XXXXXX")
backup="$parent/Stopwatch Previous.app"
trap 'rm -rf -- "$replacement"' EXIT
/usr/bin/ditto "$incoming" "$replacement/Stopwatch.app"
/usr/bin/codesign --verify --deep --strict "$replacement/Stopwatch.app"
# Only remove backups created by this installer, never an unrelated app.
if [[ -e "$backup" ]]; then
  [[ -f "$backup/Contents/Resources/GitCheckout.txt" ]] || { print -u2 'Backup name already in use.'; exit 1; }

fi
# Signal readiness only after copying, verification and preflight have succeeded.
if [[ -n "${4:-}" ]]; then touch "$4"; fi
for attempt in {1..1000}; do
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
  print -u2 'The app did not quit. The original app is unchanged.'
  rm -rf -- "$replacement"
  exit 1
fi
[[ ! -e "$backup" ]] || rm -rf -- "$backup"
if [[ -e "$destination" ]]; then mv -- "$destination" "$backup"; fi
if ! mv -- "$replacement/Stopwatch.app" "$destination"; then
  [[ ! -e "$backup" ]] || mv -- "$backup" "$destination"
  exit 1
fi
rmdir "$replacement"
# Tests can verify replacement without launching UI.
if [[ "${STOPWATCH_TEST_NO_LAUNCH:-0}" != 1 ]]; then
  if ! /usr/bin/open "$destination"; then
    rm -rf -- "$destination"
    [[ ! -e "$backup" ]] || mv -- "$backup" "$destination"
    /usr/bin/open "$destination"
    exit 1
  fi
fi

# Remove the helper's own staging directory after launch.
if [[ "${incoming:h:t}" == stopwatch-restart-* ]]; then rm -rf -- "${incoming:h}"; fi
