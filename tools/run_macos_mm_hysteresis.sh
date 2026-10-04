#!/bin/bash
set -euo pipefail
# Root only; the existing snapshots and exported builds remain immutable.
task_root=/Users/ryanliu/splatink-build/20261004-mm-hysteresis-v3
task_base=/Users/ryanliu/splatink-build/20261004-mm-hysteresis
task_mode="${1:?prepare, portable or native}"
task_archive=/Users/ryanliu/splatink-build/20261004-mm-hysteresis-v3.tar.gz
task_manifest=/Users/ryanliu/splatink-build/20261004-mm-hysteresis-v3.json
case "$task_mode" in prepare|portable|native) ;; *) exit 2;; esac
task_lock=/Users/ryanliu/splatink-build/engine.lock
if ! mkdir "$task_lock" 2>/dev/null; then printf 'Mac engine already in use\n' >&2; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_scan() {
  local task_log="$1"
  /usr/bin/python3 - "$task_log" "$task_log.stdout" <<'PY'
import re,sys
pattern=re.compile(r'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode')
hits=[]
for name in sys.argv[1:]:
    with open(name,errors='replace') as source:
        for number,line in enumerate(source,1):
            if pattern.search(line):hits.append((name,number,line.strip()))
for name,number,line in hits[:6]:print(f'{name}:{number}: {line[:220]}')
if hits:
    print(f'Diagnostic log rejected: {len(hits)} error/warning lines; full logs retained')
    raise SystemExit(1)
PY
}
if [ "$task_mode" = prepare ]; then
  /usr/bin/python3 - "$task_root" "$task_base" "$task_archive" "$task_manifest" <<'PY'
import hashlib,json,os,sys,tarfile
from pathlib import Path,PurePosixPath
target,base,archive,manifest=map(Path,sys.argv[1:])
for p in (target,base):
    if p!=Path(os.path.realpath(p)) or p.parent!=Path('/Users/ryanliu/splatink-build'):raise SystemExit('Unsafe QA root')
if (target/'stage').exists() or target==base:raise SystemExit('Target must be fresh')
if not (base/'stage/project.godot').is_file():raise SystemExit('Missing QA base')
record=json.loads(manifest.read_text())
if hashlib.sha256(archive.read_bytes()).hexdigest()!=record['archive_sha256']:raise SystemExit('Archive SHA mismatch')
inventory={v['path']:v for v in record['files']}
allowed={'tools/.gdignore','scripts/animation/ink_motion_matcher.gd','tools/verify_mm_discriminative_hysteresis.gd','tools/mm_discriminative_hysteresis_fixture.gd'}
if set(inventory)!=allowed:raise SystemExit('Unexpected overlay inventory')
seen=set()
with tarfile.open(archive) as tar:
    for entry in tar.getmembers():
        p=PurePosixPath(entry.name)
        if not entry.isfile() or p.is_absolute() or '..' in p.parts or entry.name not in allowed or entry.name in seen:raise SystemExit('Unsafe archive member')
        data=tar.extractfile(entry).read();item=inventory[entry.name]
        if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit('Member SHA mismatch')
        seen.add(entry.name)
if seen!=allowed:raise SystemExit('Missing member')
for item in record['unchanged_base']:
    if hashlib.sha256((base/'stage'/item['path']).read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Base/native data mismatch '+item['path'])
PY
  mkdir -p "$task_root/stage" "$task_root/logs" "$task_root/output"
  rsync -a --exclude=.godot --exclude='*.import' "$task_base/stage/" "$task_root/stage/"
  ln -s "$task_base/engine" "$task_root/engine"
  tar -xzf "$task_archive" -C "$task_root/stage"
  cp "$task_manifest" "$task_root/output/candidate-manifest.json"
  for task_pass in 1 2; do
    task_log="$task_root/logs/hysteresis-import-$task_pass.log"
    "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --editor --path "$task_root/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
    task_scan "$task_log"
  done
  printf 'Fresh MM hysteresis candidate imported\n'
  exit 0
fi
test -f "$task_root/stage/project.godot"
task_log="$task_root/logs/mm-discriminative-$task_mode.log"
task_args=(--headless --path "$task_root/stage" --script res://tools/verify_mm_discriminative_hysteresis.gd --log-file "$task_log" -- "--output=$task_root/output/mm-discriminative-$task_mode.json")
if [ "$task_mode" = native ]; then task_args+=(--native-locomotion-mm --native-f32-model=arm64-fma); fi
task_exit=0
"$task_root/engine/Godot.app/Contents/MacOS/Godot" "${task_args[@]}" > "$task_log.stdout" 2>&1 || task_exit=$?
grep -E '^MM_DISCRIMINATIVE ' "$task_log.stdout" || true
task_scan "$task_log"
if [ "$task_exit" -ne 0 ]; then exit "$task_exit"; fi
/usr/bin/python3 - "$task_root/output/mm-discriminative-$task_mode.json" <<'PY'
import json,sys
record=json.load(open(sys.argv[1]))
if record['failures'] or not record['query_fixture'] or not record['diagnostic_only']:raise SystemExit('MM fixture failed')
print('MAC_MM_HYSTERESIS',record['checks'],'checks, 0 failures')
PY
