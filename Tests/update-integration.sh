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
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$built/Contents/Info.plist")" == Stewie ]]
mkdir "$fixture/installed"
/usr/bin/ditto "$project/Stewie.app" "$fixture/installed/Stewie.app"
STOPWATCH_TEST_NO_LAUNCH=1 /bin/zsh "$project/Scripts/replace-app.sh" "$built" "$fixture/installed/Stewie.app" 999999
[[ -d "$fixture/installed/Stewie Previous.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$fixture/installed/Stewie.app/Contents/Info.plist")" == "$next_version" ]]
/usr/bin/codesign --verify --deep --strict "$fixture/installed/Stewie.app"
rm -rf -- "${built:h}"

# A v1.0.7 app uses its bundled updater, which still expects Stopwatch.app.
git checkout --quiet v1.0.7
legacy_built=$(/bin/zsh "$PWD/Scripts/git-update.sh" build "$PWD" "$commit" "$next_version")
[[ "${legacy_built:t}" == Stopwatch.app ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$legacy_built/Contents/Info.plist")" == Stewie ]]
mkdir -p "$fixture/old-source" "$fixture/legacy-installed"
git archive v1.0.7 | tar -x -C "$fixture/old-source"
STOPWATCH_CHECKOUT="$PWD" /bin/zsh "$fixture/old-source/build.sh"
/usr/bin/ditto "$fixture/old-source/Stopwatch.app" "$fixture/legacy-installed/Stopwatch.app"
STOPWATCH_TEST_NO_LAUNCH=1 /bin/zsh "$fixture/old-source/Scripts/replace-app.sh" "$legacy_built" "$fixture/legacy-installed/Stopwatch.app" 999999
[[ -d "$fixture/legacy-installed/Stopwatch Previous.app" ]]
STEWIE_TEST_NO_LAUNCH=1 /bin/zsh "$project/Scripts/migrate-app.sh" "$fixture/legacy-installed/Stopwatch.app" "$fixture/legacy-installed/Stewie.app" 999999
[[ ! -e "$fixture/legacy-installed/Stopwatch.app" && -d "$fixture/legacy-installed/Stewie.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$fixture/legacy-installed/Stewie.app/Contents/Info.plist")" == "$next_version" ]]
/usr/bin/codesign --verify --deep --strict "$fixture/legacy-installed/Stewie.app"
rm -rf -- "${legacy_built:h}"
print 'PASS: stable tag selection, checkout preservation, release compilation, Stewie replacement, legacy updater compatibility, app rename and backups.'
