#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
project=$PWD
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
git clone --quiet "$project" "$fixture/publisher"
cd "$fixture/publisher"
git config user.name "Update Test"
git config user.email "test@example.invalid"
parts=( ${(s:.:)$(cat VERSION)} )
next_version="$parts[1].$parts[2].$((parts[3]+1))"
print -r -- "$next_version" > VERSION
git add VERSION
git commit --quiet -m "Test release"
git tag v$next_version
git tag v99.0.0-beta
git clone --quiet "$fixture/publisher" "$fixture/recipient"
cd "$fixture/recipient"
git checkout --quiet v1.0.0
print "local edit" > personal.txt
before=$(git rev-parse HEAD)
result=$(/bin/zsh "$project/Scripts/git-update.sh" check "$PWD")
tag=$(print -r -- "$result" | head -1)
commit=$(print -r -- "$result" | tail -1)
[[ "$tag" == v$next_version ]]
[[ "$(git rev-parse HEAD)" == "$before" && -f personal.txt ]]
if /bin/zsh "$project/Scripts/git-update.sh" build "$PWD" "$commit" 9.9.9; then exit 1; fi
built=$(/bin/zsh "$project/Scripts/git-update.sh" build "$PWD" "$commit" "$next_version")
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$built/Contents/Info.plist")" == "$next_version" ]]
mkdir "$fixture/installed"
/usr/bin/ditto "$project/Stopwatch.app" "$fixture/installed/Stopwatch.app"
STOPWATCH_TEST_NO_LAUNCH=1 /bin/zsh "$project/Scripts/replace-app.sh" "$built" "$fixture/installed/Stopwatch.app" 999999
[[ -d "$fixture/installed/Stopwatch Previous.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$fixture/installed/Stopwatch.app/Contents/Info.plist")" == "$next_version" ]]
/usr/bin/codesign --verify --deep --strict "$fixture/installed/Stopwatch.app"
rm -rf -- "${built:h}"
print 'PASS: stable tag selection, checkout preservation, tag/version mismatch rejection, release compilation, verified replacement and backup.'
