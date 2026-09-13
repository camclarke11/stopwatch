#!/bin/zsh
# Pair the selected Apple compiler with an SDK it can actually compile.
set -euo pipefail
compiler=$(env -u SDKROOT -u TOOLCHAINS xcrun --toolchain default --find swiftc)
default_sdk=$(env -u SDKROOT -u TOOLCHAINS xcrun --sdk macosx --show-sdk-path)
architecture=$(uname -m)
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { print -u2 'Unsupported Mac architecture'; exit 1; }
target="$architecture-apple-macosx13.0"
probe=$(mktemp -d "${TMPDIR:-/tmp/}stopwatch-compiler.XXXXXX")
trap 'rm -rf -- "$probe"' EXIT
cat > "$probe/check.swift" <<'SWIFT'
import Cocoa
import WebKit
import CoreText
let clock = ContinuousClock()
print(clock.now)
SWIFT
# Try the default first, then versioned SDKs from the same developer installation.
typeset -a candidates
candidates=("$default_sdk" "${default_sdk:h}"/MacOSX[0-9]*.sdk(NOn))
typeset -A seen
selected=''
for sdk in "${candidates[@]}"; do
  canonical=${sdk:A}
  [[ -z "${seen[$canonical]:-}" ]] || continue
  seen[$canonical]=1
  if env -u SDKROOT -u TOOLCHAINS "$compiler" -sdk "$sdk" -target "$target" -module-cache-path "$probe/cache" "$probe/check.swift" -o "$probe/check" > "$probe/errors" 2>&1; then
    selected=$sdk
    break
  fi
done
if [[ -z "$selected" ]]; then
  print -u2 'No compatible Apple compiler and macOS SDK were found.'
  print -u2 'Open System Settings → General → Software Update and install the Command Line Tools update, then run ./install.sh again.'
  print -u2 'If no update is offered, install a matching Command Line Tools package from https://developer.apple.com/download/all/.'
  tail -n 8 "$probe/errors" >&2
  exit 1
fi
print -u2 "Building with ${selected:t} ($architecture, macOS 13+)"
env -u SDKROOT -u TOOLCHAINS "$compiler" -sdk "$selected" -target "$target" -module-cache-path "$probe/cache" "$@"
