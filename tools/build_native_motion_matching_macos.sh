#!/bin/bash
set -euo pipefail
# Root runs this only in a dedicated build directory; this never runs Godot.
build_root="${1:?Dedicated /Users/*/splatink-build/* directory required}"
archive="${2:?Source archive required}"
archive_sha="${3:?Expected archive SHA-256 required}"
resolved_root="$(/usr/bin/python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$build_root")"
case "$resolved_root" in
  /Users/*/splatink-build/*) ;;
  *) printf 'Rejected build root: %s\n' "$resolved_root" >&2; exit 2 ;;
esac
if [ ! -f "$archive" ]; then printf 'Archive missing\n' >&2; exit 2; fi
actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [ "$actual_sha" != "$archive_sha" ]; then printf 'Archive SHA mismatch\n' >&2; exit 2; fi
mkdir -p "$resolved_root/logs" "$resolved_root/runtime/bin/macos"
# Refuse traversal and unrelated top-level paths before archive extraction.
tar -tzf "$archive" | /usr/bin/python3 -c 'import sys;from pathlib import PurePosixPath
for line in sys.stdin:
 p=PurePosixPath(line.strip())
 if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] not in ("source","provenance","MAC_BUILD.md"):raise SystemExit("Unsafe archive entry: "+str(p))'
tar -xzf "$archive" -C "$resolved_root"
/usr/bin/python3 -m venv "$resolved_root/venv"
"$resolved_root/venv/bin/python" -m pip install --disable-pip-version-check 'SCons==4.10.1' > "$resolved_root/logs/toolchain-install.log" 2>&1
{
  xcode-select -p
  xcrun clang --version
  "$resolved_root/venv/bin/python" --version
  "$resolved_root/venv/bin/python" -m SCons --version
  printf 'Source archive SHA256: %s\n' "$actual_sha"
} > "$resolved_root/logs/toolchain.txt" 2>&1
cd "$resolved_root/source"
for target in template_debug template_release; do
  "$resolved_root/venv/bin/python" -m SCons platform=macos arch=universal target="$target" precision=single -j6 > "$resolved_root/logs/$target.log" 2>&1
  binary="bin/macos/macos.framework/libgdmotionmatching.macos.$target"
  if [ ! -f "$binary" ]; then printf 'Missing built binary: %s\n' "$binary" >&2; exit 3; fi
  cp "$binary" "$resolved_root/runtime/bin/macos/libgdmotionmatching.macos.$target.splatlower1.dylib"
  file "$binary" >> "$resolved_root/logs/binary-inspection.txt"
  lipo -info "$binary" >> "$resolved_root/logs/binary-inspection.txt"
  otool -L "$binary" >> "$resolved_root/logs/binary-inspection.txt"
done
shasum -a 256 "$resolved_root/runtime/bin/macos/"*.dylib > "$resolved_root/logs/runtime-sha256.txt"
cp "$resolved_root/source/LICENSE.md" "$resolved_root/runtime/LICENSE.md"
cp "$resolved_root/provenance/source.json" "$resolved_root/runtime/source-provenance.json"
printf 'Native build complete in %s; no engine execution performed.\n' "$resolved_root"
