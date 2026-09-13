"""Exercise SDK fallback without requiring a broken Apple toolchain."""
import os
from pathlib import Path
import subprocess
import tempfile

wrapper = Path(__file__).resolve().parents[1] / 'Scripts/swiftc.sh'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    sdk_root = root / 'SDKs'
    sdk_root.mkdir()
    for version in ('27.0', '26.5'):
        (sdk_root / f'MacOSX{version}.sdk').mkdir()
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    xcrun = bin_dir / 'xcrun'
    xcrun.write_text('''#!/bin/zsh
if [[ "$*" == *--find* ]]; then print -r -- "$FIXTURE/compiler"; else print -r -- "$FIXTURE/SDKs/MacOSX27.0.sdk"; fi
''')
    compiler = root / 'compiler'
    compiler.write_text('''#!/bin/zsh
print -r -- "$*" >> "$FIXTURE/calls"
[[ -z "${SDKROOT:-}" && -z "${TOOLCHAINS:-}" ]] || exit 8
[[ "${FAIL_ALL:-0}" != 1 && "$*" == *MacOSX26.5.sdk* ]] || exit 1
exit 0
''')
    xcrun.chmod(0o755)
    compiler.chmod(0o755)
    env = {**os.environ, 'PATH': f'{bin_dir}:' + os.environ['PATH'], 'FIXTURE': str(root), 'SDKROOT': '/bad/sdk', 'TOOLCHAINS': 'bad'}
    result = subprocess.run([str(wrapper), 'app.swift', '-o', 'app'], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    calls = (root / 'calls').read_text().splitlines()
    assert len(calls) == 3 and 'MacOSX27.0.sdk' in calls[0] and 'MacOSX26.5.sdk' in calls[-1]
    assert 'app.swift -o app' in calls[-1] and 'macosx13.0' in calls[-1]
    env['FAIL_ALL'] = '1'
    result = subprocess.run([str(wrapper), 'app.swift'], env=env, capture_output=True, text=True)
    assert result.returncode != 0 and 'No compatible Apple compiler' in result.stderr
print('PASS: incompatible default fallback, explicit target, environment isolation and clear no-compatible-SDK failure')
