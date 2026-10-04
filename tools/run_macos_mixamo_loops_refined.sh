#!/bin/bash
set -euo pipefail
# Root only; copy a frozen QA stage, never alter a reference or exported build.
task_root=/Users/ryanliu/splatink-build/20261004-mixamo-loops-refined-v2
task_base=/Users/ryanliu/splatink-build/20261004-mm-hysteresis-v3
task_archive=/Users/ryanliu/splatink-build/20261004-mixamo-loops-refined-v2.tar.gz
task_manifest=/Users/ryanliu/splatink-build/20261004-mixamo-loops-refined-v2.json
task_mode="${1:?prepare, native or portable}"
case "$task_mode" in prepare|native|portable) ;; *) exit 2 ;; esac
task_lock=/Users/ryanliu/splatink-build/engine.lock
if ! mkdir "$task_lock" 2>/dev/null; then printf 'Mac engine already in use\n' >&2; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_scan() {
  /usr/bin/python3 - "$1" "$1.stdout" <<'PY'
import re,sys
pattern=re.compile(r'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode')
hits=[]
for name in sys.argv[1:]:
    for number,line in enumerate(open(name,errors='replace'),1):
        if pattern.search(line):hits.append((name,number,line.strip()))
for name,number,line in hits[:6]:print(f'{name}:{number}: {line[:220]}')
if hits:raise SystemExit(f'Full diagnostic logs retained; {len(hits)} rejected lines')
PY
}
if [ "$task_mode" = prepare ]; then
  /usr/bin/python3 - "$task_root" "$task_base" "$task_archive" "$task_manifest" <<'PY'
import hashlib,json,os,sys,tarfile
from pathlib import Path,PurePosixPath
target,base,archive,manifest=map(Path,sys.argv[1:])
for path in (target,base):
    if path!=Path(os.path.realpath(path)) or path.parent!=Path('/Users/ryanliu/splatink-build'):raise SystemExit('Unsafe QA path')
if target.exists() or target==base:raise SystemExit('Target must be fresh')
if not (base/'stage/project.godot').is_file():raise SystemExit('Missing base')
record=json.loads(manifest.read_text())
if hashlib.sha256(archive.read_bytes()).hexdigest()!=record['archive_sha256']:raise SystemExit('Archive SHA mismatch')
inventory={item['path']:item for item in record['files']}
allowed={'tools/.gdignore','tools/mixamo_loop_refine.py','tools/verify_mixamo_loops_refined.gd','tools/mixamo_loop_refined_fixture.gd','scripts/animation/experiments/mixamo_loop_refined_prototype.gd','assets/animation/experiments/mixamo_loops_refined/loops.json','assets/animation/experiments/mixamo_loops_refined/provenance.json','.tools/mixamo-loop-refined/report.json','.tools/mixamo-loop-refined/.gdignore'}
for item in inventory:
    path=PurePosixPath(item)
    if path.parent==PurePosixPath('assets/animation/experiments/mixamo_loops_refined') and path.name.startswith('mixamo_loop_') and path.suffix=='.tres':allowed.add(item)
if set(inventory)!=allowed or len(allowed)!=30:raise SystemExit('Unexpected overlay inventory')
seen=set()
with tarfile.open(archive) as source:
    for member in source.getmembers():
        path=PurePosixPath(member.name)
        if not member.isfile() or path.is_absolute() or '..' in path.parts or member.name not in allowed or member.name in seen:raise SystemExit('Unsafe tar member')
        data=source.extractfile(member).read();item=inventory[member.name]
        if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit('Member SHA mismatch')
        seen.add(member.name)
if seen!=allowed:raise SystemExit('Missing member')
for item in record['unchanged_base']:
    if hashlib.sha256((base/'stage'/item['path']).read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Base provenance mismatch '+item['path'])
PY
  mkdir -p "$task_root/stage" "$task_root/logs" "$task_root/output"
  rsync -a --exclude=.godot --exclude='*.import' "$task_base/stage/" "$task_root/stage/"
  ln -s "$task_base/engine" "$task_root/engine"
  tar -xzf "$task_archive" -C "$task_root/stage"
  cp "$task_manifest" "$task_root/output/candidate-manifest.json"
  for task_pass in 1 2; do
    task_log="$task_root/logs/loop-import-$task_pass.log"
    "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --editor --path "$task_root/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
    task_scan "$task_log"
  done
  printf 'Fresh Mixamo loop diagnostic imported\n'
  exit 0
fi
task_log="$task_root/logs/mixamo-loop-refined-$task_mode.log"
task_args=(--headless --path "$task_root/stage" --script res://tools/verify_mixamo_loops_refined.gd --log-file "$task_log" -- "--loop-output=$task_root/output/mixamo-loop-refined-$task_mode.json")
if [ "$task_mode" = native ]; then task_args+=(--native-locomotion-mm); fi
task_exit=0
"$task_root/engine/Godot.app/Contents/MacOS/Godot" "${task_args[@]}" > "$task_log.stdout" 2>&1 || task_exit=$?
grep -E '^MIXAMO_REFINED_LOOPS ' "$task_log.stdout" || true
task_scan "$task_log"
if [ "$task_exit" -ne 0 ]; then exit "$task_exit"; fi
/usr/bin/python3 - "$task_root/output/mixamo-loop-refined-$task_mode.json" <<'PY'
import json,sys
record=json.load(open(sys.argv[1]))
if record['structural_failures'] or record['production_accepted'] or not record['diagnostic_only']:raise SystemExit('Imported resource contract failed')
print('MAC_MIXAMO_REFINED_LOOPS',record['checks'],'checks;',len(record['quality_failures']),'quality failures retained')
PY
