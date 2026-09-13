#!/bin/zsh
# Called by the installed app. Never modifies the user's checkout or local tags.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15'
operation=$1
checkout=$2
[[ -d "$checkout/.git" ]] || { print -u2 'The original Git checkout has moved. Run install.sh again from its new location.'; exit 1; }
cd "$checkout"
case "$operation" in
  check)
    git fetch --quiet --no-tags origin '+refs/tags/v*:refs/stopwatch-releases/v*'
    git for-each-ref --sort=-version:refname --format='%(refname:strip=2)' refs/stopwatch-releases | while read -r tag; do
      if [[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
        print -r -- "$tag"
        git rev-parse --verify "refs/stopwatch-releases/$tag^{commit}"
        break
      fi
    done
    ;;
  build)
    commit=$3
    [[ "$commit" =~ '^[0-9a-f]{40,64}$' ]] || exit 1
    stage=$(mktemp -d "${TMPDIR:-/tmp/}stopwatch-update.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    git archive "$commit" | tar -x -C "$stage"
    [[ -f "$stage/build.sh" && -f "$stage/VERSION" ]] || { print -u2 'Release is missing the app source.'; exit 1; }
    [[ "$(cat "$stage/VERSION")" == "$4" ]] || { print -u2 "Release tag and VERSION disagree."; exit 1; }
    STOPWATCH_CHECKOUT="$checkout" /bin/zsh "$stage/build.sh" >&2
    /usr/bin/codesign --verify --deep --strict "$stage/Stopwatch.app"
    print -r -- "$stage/Stopwatch.app"
    trap - EXIT
    ;;
  *) exit 2 ;;
esac
