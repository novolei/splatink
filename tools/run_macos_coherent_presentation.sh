#!/bin/bash
set -euo pipefail
# Root only: isolated imported-rig contract, never an exported gameplay acceptance.
task_root=/Users/ryanliu/splatink-build/20261004-coherent-presentation-v3
task_base=/Users/ryanliu/splatink-build/20261004-mixamo-loops-refined-v2
task_archive=/Users/ryanliu/splatink-build/20261004-coherent-presentation-v3.tar.gz
task_manifest=/Users/ryanliu/splatink-build/20261004-coherent-presentation-v3.json
task_mode="${1:?prepare, contract or legacy-regression}"
case "$task_mode" in prepare|contract|legacy-regression) ;; *) exit 2 ;; esac
task_lock=/Users/ryanliu/splatink-build/engine.lock
if ! mkdir "$task_lock" 2>/dev/null; then printf 'Mac engine already in use\n' >&2; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_scan() {
  /usr/bin/python3 - "$1" "$1.stdout" <<'PY'
import re,sys
hits=[]
for name in sys.argv[1:]:
    for n,line in enumerate(open(name,errors='replace'),1):
        if re.search(r'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode parsing error',line):hits.append((name,n,line.strip()))
for item in hits[:6]:print(item)
if hits:raise SystemExit(f'{len(hits)} diagnostic lines; full logs retained')
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
if hashlib.sha256(archive.read_bytes()).hexdigest()!=record['archive_sha256']:raise SystemExit('Archive mismatch')
allowed={'tools/.gdignore','tools/verify_coherent_presentation.gd','scripts/characters/ink_avatar.gd','scripts/animation/ink_pose_presentation.gd','scripts/animation/experiments/ink_coherent_presentation.gd'}
inventory={i['path']:i for i in record['files']}
if set(inventory)!=allowed:raise SystemExit('Unexpected overlay inventory')
seen=set()
with tarfile.open(archive) as source:
    for member in source.getmembers():
        path=PurePosixPath(member.name)
        if not member.isfile() or path.is_absolute() or '..' in path.parts or member.name not in allowed or member.name in seen:raise SystemExit('Unsafe tar member')
        data=source.extractfile(member).read();item=inventory[member.name]
        if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit('Member mismatch')
        seen.add(member.name)
if seen!=allowed:raise SystemExit('Missing member')
for item in record['unchanged_base']:
    if hashlib.sha256((base/'stage'/item['path']).read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Base mismatch '+item['path'])
PY
  mkdir -p "$task_root/stage" "$task_root/logs" "$task_root/output"
  rsync -a --exclude=.godot --exclude='*.import' "$task_base/stage/" "$task_root/stage/"
  ln -s "$task_base/engine" "$task_root/engine"
  tar -xzf "$task_archive" -C "$task_root/stage"
  cp "$task_manifest" "$task_root/output/candidate-manifest.json"
  for task_pass in 1 2; do
    task_log="$task_root/logs/coherent-import-$task_pass.log"
    "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --editor --path "$task_root/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
    task_scan "$task_log"
  done
  printf 'Fresh coherent diagnostic imported\n'
  exit 0
fi
if [ "$task_mode" = legacy-regression ]; then
  task_legacy=/Users/ryanliu/splatink-build/20261004-coherent-presentation-v2/stage
  task_log="$task_root/logs/coherent-legacy-regression.log"
  task_exit=0
  "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_legacy" --script "$task_root/stage/tools/verify_coherent_presentation.gd" --log-file "$task_log" -- --native-locomotion-mm --presentation-interpolation=coherent "--coherent-output=$task_root/output/coherent-legacy-regression" > "$task_log.stdout" 2>&1 || task_exit=$?
  /usr/bin/python3 - "$task_root/output/coherent-legacy-regression.json" "$task_exit" "$task_log" "$task_log.stdout" <<'PY'
import json,re,sys
record=json.load(open(sys.argv[1]));failures=record['failures']
required={'moving teleport restores authoritative local XZ','moving teleport packets use independent authority','disable restores and invalidates packet','reenable waits for physics eligibility'}
if int(sys.argv[2])!=1 or not required.issubset(set(failures)):raise SystemExit('Legacy negative control did not reproduce the targeted defects')
for name in sys.argv[3:]:
    for line in open(name,errors='replace'):
        if re.search(r'SCRIPT ERROR|Parse Error|SHADER ERROR|WARNING:|Unicode parsing error',line) or ('ERROR:' in line and 'COHERENT_CONTRACT' not in line):raise SystemExit('Unexpected diagnostic in negative control')
print('MAC_COHERENT_LEGACY_NEGATIVE_CONTROL',len(failures),'expected failed assertions retained')
PY
  exit 0
fi
task_log="$task_root/logs/coherent-contract.log"
task_exit=0
"$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_root/stage" --script res://tools/verify_coherent_presentation.gd --log-file "$task_log" -- --native-locomotion-mm --presentation-interpolation=coherent "--coherent-output=$task_root/output/coherent-contract" > "$task_log.stdout" 2>&1 || task_exit=$?
task_scan "$task_log"
if [ "$task_exit" -ne 0 ]; then exit "$task_exit"; fi
/usr/bin/python3 - "$task_root/output/coherent-contract.json" <<'PY'
import json,sys
record=json.load(open(sys.argv[1]))
if record['failures'] or record['accepted_for_production']:raise SystemExit('Authority contract failed')
print('MAC_COHERENT_CONTRACT',record['checks'],'checks;',record['reach_clamps'],'reach clamps;',record['maximum_world_fk_interpolation_error_m'],'m FK error')
PY
