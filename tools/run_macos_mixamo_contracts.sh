#!/bin/bash
set -euo pipefail
# Only Root executes this script via SSH. All changes stay in a NEW QA snapshot.
# Args: dedicated-root delta.tar.gz expected-sha manifest.json [gpu=off] [base-root]
task_root="${1:?Dedicated Mac Mixamo QA root required}"
task_archive="${2:?Frozen PC Mixamo delta archive required}"
task_archive_sha="${3:?Expected delta SHA256 required}"
task_manifest="${4:?Frozen delta manifest.json required}"
task_gpu="${5:-off}"
task_base="${6:-/Users/ryanliu/splatink-build/20261004-zstd-lan}"
case "$task_gpu" in on|off) ;; *) printf 'gpu must be on/off\n' >&2; exit 2;; esac

# Validate both paths before copying; never remove or modify the base snapshot.
/usr/bin/python3 - "$task_root" "$task_base" <<'PY'
import os,sys
from pathlib import Path
target,source=(Path(x).absolute() for x in sys.argv[1:])
for label,p in [('target',target),('source',source)]:
    resolved=Path(os.path.realpath(p))
    parts=resolved.parts
    if len(parts)!=5 or parts[1]!='Users' or parts[3]!='splatink-build':
        raise SystemExit('Rejected '+label+' path: '+str(resolved))
    if resolved!=p:raise SystemExit('Snapshot root must not be a symlink: '+str(p))
if target==source:raise SystemExit('Target cannot be the base snapshot')
if (target/'stage').exists():raise SystemExit('Target stage already exists; choose a fresh dedicated QA root')
if not (source/'stage/project.godot').is_file():raise SystemExit('Base stage missing')
PY

test -f "$task_archive"
test -f "$task_manifest"
task_actual_sha="$(shasum -a 256 "$task_archive" | awk '{print $1}')"
if [ "$task_actual_sha" != "$task_archive_sha" ]; then printf 'Delta archive SHA mismatch\n' >&2; exit 2; fi

# Enforce the minimal overlay inventory and reject links/traversal before extract.
/usr/bin/python3 - "$task_archive" "$task_manifest" "$task_archive_sha" <<'PY'
import hashlib,json,sys,tarfile
from pathlib import PurePosixPath
archive,manifest,expected=sys.argv[1:]
record=json.load(open(manifest,encoding='utf-8'))
if record['archive_sha256']!=expected:raise SystemExit('Manifest/archive mismatch')
inventory={v['path']:v for v in record['files']}
if len(inventory)!=len(record['files']):raise SystemExit('Duplicate manifest file')
exact={'tools/.gdignore','tools/verify_mixamo_turns.gd','tools/verify_mixamo_visual.gd','tools/verify_mixamo_turn_detail.gd','scenes/experiments/mixamo_turn_preview.tscn','scripts/animation/experiments/mixamo_turn_prototype.gd','scripts/animation/experiments/mixamo_turn_prototype.gd.uid','scripts/animation/experiments/mixamo_turn_preview.gd','scripts/animation/experiments/mixamo_turn_preview.gd.uid'}
seen=set()
with tarfile.open(archive,'r:gz') as tar:
    for entry in tar.getmembers():
        name=entry.name;p=PurePosixPath(name)
        if p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name or not entry.isfile():raise SystemExit('Unsafe member '+name)
        if name in seen or name not in inventory:raise SystemExit('Unlisted/duplicate member '+name)
        if name not in exact and not (name.startswith('assets/animation/experiments/mixamo/') and len(p.parts)==5 and p.suffix in ('.tres','.json')):raise SystemExit('Outside Mixamo delta '+name)
        payload=tar.extractfile(entry).read();item=inventory[name]
        if len(payload)!=item['bytes'] or hashlib.sha256(payload).hexdigest()!=item['sha256']:raise SystemExit('Delta member checksum mismatch '+name)
        seen.add(name)
if seen!=set(inventory):raise SystemExit('Incomplete archive')
PY

task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then printf 'Another Splatink Mac probe owns the engine\n' >&2; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
mkdir -p "$task_root/stage" "$task_root/logs" "$task_root/output"
rsync -a --exclude=.godot --exclude='*.import' "$task_base/stage/" "$task_root/stage/"
ln -s "$task_base/engine" "$task_root/engine"
tar -xzf "$task_archive" -C "$task_root/stage"
cp "$task_manifest" "$task_root/output/pc-candidate-manifest.json"
printf '%s  %s\n' "$task_actual_sha" "$(basename "$task_archive")" > "$task_root/output/pc-candidate.tar.gz.sha256"
mkdir -p "$task_root/stage/shots"
task_engine="$task_root/engine/Godot.app/Contents/MacOS/Godot"
test -x "$task_engine"

task_scan() {
  local task_log="$1"
  test -f "$task_log"
  test -f "$task_log.stdout"
  if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode' "$task_log" "$task_log.stdout"; then
    grep -En 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode' "$task_log" "$task_log.stdout" >&2
    return 1
  fi
}

# Two imports on the freshly copied, cache-free stage also verify clean shutdown.
for task_pass in 1 2; do
  task_log="$task_root/logs/mac-mixamo-import-$task_pass.log"
  "$task_engine" --headless --editor --path "$task_root/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
  task_scan "$task_log"
done

for task_mode in portable native; do
  task_log="$task_root/logs/mac-mixamo-turn-$task_mode.log"
  task_args=(--headless --path "$task_root/stage" --script res://tools/verify_mixamo_turns.gd --log-file "$task_log" -- --nonpersistent --benchmark-background)
  if [ "$task_mode" = native ]; then task_args+=(--native-locomotion-mm); fi
  # Remove only this disposable stage's previous result, avoiding stale success
  # if a parser/runtime failure occurs before the frozen script writes JSON.
  rm -f "$task_root/stage/shots/mixamo-turn-contract.json"
  task_exit=0
  "$task_engine" "${task_args[@]}" > "$task_log.stdout" 2>&1 || task_exit=$?
  # The frozen script writes a shared path. Save it before running another mode.
  if [ -f "$task_root/stage/shots/mixamo-turn-contract.json" ]; then
    cp "$task_root/stage/shots/mixamo-turn-contract.json" "$task_root/output/mac-mixamo-turn-$task_mode.json"
  fi
  task_scan "$task_log"
  if [ "$task_exit" -ne 0 ]; then printf 'Engine contract exit %s\n' "$task_exit" >&2; exit "$task_exit"; fi
  /usr/bin/python3 - "$task_root/output/mac-mixamo-turn-$task_mode.json" "$task_mode" <<'PY'
import json,sys
record=json.load(open(sys.argv[1],encoding='utf-8'));native=sys.argv[2]=='native'
if record['failures']!=0 or record['accepted_for_production'] is not False:raise SystemExit('Failed or incorrectly promoted experiment')
if record['native_requested']!=native:raise SystemExit('Native CLI mode was not observed')
families={'shooter','roller','charger','blaster','dualies','slosher','splatling'}
if set(record['native_providers'])!=families:raise SystemExit('Missing weapon family evidence')
if native:
    for name,item in record['native_providers'].items():
        if item['provider']!='native MMAnimationLibrary exact contiguous search' or item['query_count']<=0 or item['pose_bucket']!=234 or item['native_error']:
            raise SystemExit('Missing actual native query evidence '+name)
if len(record['cases'])!=56:raise SystemExit('Expected seven weapons x four turns x two modes')
print('MAC_MIXAMO',sys.argv[2],record['checks'],'checks, 0 failures; actual FK contacts',record['actual_fk_contacts'])
PY
  tail -n 1 "$task_log.stdout"
done

if [ "$task_gpu" = on ]; then
  task_log="$task_root/logs/mac-mixamo-visual-native.log"
  "$task_engine" --path "$task_root/stage" --script res://tools/verify_mixamo_visual.gd --rendering-method mobile --log-file "$task_log" -- --native-locomotion-mm --nonpersistent --benchmark-background > "$task_log.stdout" 2>&1
  task_scan "$task_log"
  mkdir -p "$task_root/output/visual"
  for task_frame in 000 025 050 075 100; do cp "$task_root/stage/shots/mixamo-turn-$task_frame.png" "$task_root/output/visual/"; done
fi
printf 'Mac Mixamo contracts complete. Experimental only; no production integration.\n'
