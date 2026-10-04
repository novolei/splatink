#!/bin/bash
set -euo pipefail
# Root only. Fresh QA copy; the base and exported builds remain untouched.
task_root=/Users/ryanliu/splatink-build/20261004-audio-lifecycle
task_base=/Users/ryanliu/splatink-build/20261004-mixamo-turns
task_mode="${1:?prepare, normal, queue-free or pool}"
task_archive=/Users/ryanliu/splatink-build/20261004-audio-lifecycle-candidate.tar.gz
task_manifest=/Users/ryanliu/splatink-build/20261004-audio-lifecycle-candidate.json
case "$task_mode" in prepare|normal|queue-free|pool) ;; *) exit 2;; esac
task_lock=/Users/ryanliu/splatink-build/engine.lock
if ! mkdir "$task_lock" 2>/dev/null; then printf 'Mac engine already in use\n' >&2; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_scan() {
  local task_log="$1"
  if grep -En 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode' "$task_log" "$task_log.stdout"; then return 1; fi
}
if [ "$task_mode" = prepare ]; then
  /usr/bin/python3 - "$task_root" "$task_base" "$task_archive" "$task_manifest" <<'PY'
import hashlib,json,os,sys,tarfile
from pathlib import Path,PurePosixPath
target,base,archive,manifest=map(Path,sys.argv[1:])
for p in (target,base):
    if p!=Path(os.path.realpath(p)) or p.parent!=Path('/Users/ryanliu/splatink-build'):raise SystemExit('Unsafe QA root')
if (target/'stage').exists() or target==base:raise SystemExit('Target must be a fresh snapshot')
if not (base/'stage/project.godot').is_file():raise SystemExit('Missing QA base')
record=json.loads(manifest.read_text())
if hashlib.sha256(archive.read_bytes()).hexdigest()!=record['archive_sha256']:raise SystemExit('Archive SHA mismatch')
inventory={v['path']:v for v in record['files']}
allowed={'tools/.gdignore','scripts/game/ink_audio.gd','tools/verify_audio_lifecycle.gd','tools/diagnose_menu_shutdown.gd'}
if set(inventory)!=allowed:raise SystemExit('Unexpected overlay inventory')
seen=set()
with tarfile.open(archive) as tar:
    for entry in tar.getmembers():
        p=PurePosixPath(entry.name)
        if not entry.isfile() or p.is_absolute() or '..' in p.parts or entry.name not in allowed or entry.name in seen:raise SystemExit('Unsafe archive member')
        payload=tar.extractfile(entry).read();item=inventory[entry.name]
        if len(payload)!=item['bytes'] or hashlib.sha256(payload).hexdigest()!=item['sha256']:raise SystemExit('Member SHA mismatch')
        seen.add(entry.name)
if seen!=allowed:raise SystemExit('Missing overlay member')
PY
  mkdir -p "$task_root/stage" "$task_root/logs" "$task_root/output"
  rsync -a --exclude=.godot --exclude='*.import' "$task_base/stage/" "$task_root/stage/"
  ln -s "$task_base/engine" "$task_root/engine"
  tar -xzf "$task_archive" -C "$task_root/stage"
  cp "$task_manifest" "$task_root/output/candidate-manifest.json"
  for task_pass in 1 2; do
    task_log="$task_root/logs/audio-import-$task_pass.log"
    "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --editor --path "$task_root/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
    task_scan "$task_log"
  done
  printf 'Fresh audio lifecycle candidate imported\n'
  exit 0
fi
test -f "$task_root/stage/project.godot"
task_log="$task_root/logs/audio-lifecycle-$task_mode.log"
task_exit=0
"$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_root/stage" --script res://tools/verify_audio_lifecycle.gd --log-file "$task_log" -- --native-locomotion-mm "--exit-mode=$task_mode" "--output=$task_root/output/audio-lifecycle-$task_mode.json" > "$task_log.stdout" 2>&1 || task_exit=$?
grep -E 'AUDIO_LIFECYCLE_EXIT|SCRIPT ERROR|ERROR:|WARNING:' "$task_log.stdout" || true
task_scan "$task_log"
if [ "$task_exit" -ne 0 ]; then exit "$task_exit"; fi
/usr/bin/python3 - "$task_root/output/audio-lifecycle-$task_mode.json" <<'PY'
import json,sys
record=json.load(open(sys.argv[1]))
if record['failures'] or not record['playing_seen'] or not record['menu_seen']:raise SystemExit('Audio lifecycle failed')
print('MAC_AUDIO_LIFECYCLE',record['exit_mode'],record['checks'],'checks, 0 failures')
PY
