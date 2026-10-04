#!/bin/bash
set -euo pipefail
# Dedicated PC snapshot only. No iOS export/signing or external service changes.
task_root="${1:?absolute build directory required}"
task_native_mm="${2:-off}"
case "$task_native_mm" in on|off) ;; *) echo 'Native locomotion option must be on or off'; exit 2;; esac
case "$task_root" in /Users/*/splatink-build/*) ;; *) echo 'Invalid dedicated build directory'; exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac build owns the engine'; exit 3; fi
trap 'task_result=$?; rmdir "$task_lock"; if [ "$task_result" -ne 0 ]; then echo "SPLATINK_MAC_FAILED exit=$task_result"; fi' EXIT
task_stage="$task_root/stage"
task_engine_dir="$task_root/engine/Godot.app/Contents/MacOS"
task_editor_data="$task_root/engine/editor_data"
task_logs="$task_root/logs"
task_out="$task_root/output"
mkdir -p "$task_logs" "$task_out" "$task_root/engine"
ditto /Applications/Godot.app "$task_root/engine/Godot.app"
touch "$task_engine_dir/_sc_"
mkdir -p "$task_editor_data/export_templates/4.7.1.stable"
for task_template in macos.zip version.txt; do
 cp "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/$task_template" "$task_editor_data/export_templates/4.7.1.stable/$task_template"
done
task_godot="$task_engine_dir/Godot"
python3 - "$task_stage" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1]);project=p/'project.godot'
if 'export/convert_text_resources_to_binary=false' not in project.read_text():
 with project.open('a') as out:out.write('\n[editor]\nexport/convert_text_resources_to_binary=false\n')
stamp=p/'data/build_stamp.json';data=json.loads(stamp.read_text(encoding='utf-8-sig'))
data['platform']='macOS';stamp.write_text(json.dumps(data,indent=2))
PY
for task_pass in 1 2; do
 "$task_godot" --headless --path "$task_stage" --editor --import --log-file "$task_logs/import-$task_pass.log" > "$task_logs/import-$task_pass.stdout" 2>&1
 if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_logs/import-$task_pass.log" "$task_logs/import-$task_pass.stdout"; then echo 'MAC_IMPORT_FAILED'; exit 1; fi
done
"$task_godot" --headless --path "$task_stage" --export-debug 'macOS Development' "$task_out/Splatink.zip" --log-file "$task_logs/macos-export.log" > "$task_logs/macos-export.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_logs/macos-export.log" "$task_logs/macos-export.stdout"; then echo 'MAC_EXPORT_FAILED'; exit 1; fi
ditto -x -k "$task_out/Splatink.zip" "$task_out/macos"
task_app="$(find "$task_out/macos" -maxdepth 1 -name '*.app' -print -quit)"
task_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$task_app/Contents/Info.plist")"
for task_smoke in boot match; do
 "$task_app/Contents/MacOS/$task_executable" --headless --log-file "$task_logs/mac-smoke-$task_smoke.log" -- "--smoke=$task_smoke" > "$task_logs/mac-smoke-$task_smoke.stdout" 2>&1
 if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_logs/mac-smoke-$task_smoke.log" "$task_logs/mac-smoke-$task_smoke.stdout" || ! grep -q '"passed":true' "$task_logs/mac-smoke-$task_smoke.log"; then echo 'MAC_SMOKE_FAILED'; exit 1; fi
done
task_gpu_args=(--log-file "$task_logs/mac-gpu.log" -- --autostart=180 --autopilot --benchmark-background --nonpersistent --mode=boss --map=tidewater --time=dusk --profile-render "--capture=$task_out/mac-gpu.png" --capture-after=32)
if [ "$task_native_mm" = on ]; then task_gpu_args+=(--native-locomotion-mm); fi
"$task_app/Contents/MacOS/$task_executable" "${task_gpu_args[@]}" > "$task_logs/mac-gpu.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_logs/mac-gpu.log" "$task_logs/mac-gpu.stdout"; then echo 'MAC_GPU_FAILED'; exit 1; fi
python3 - "$task_out" "$task_native_mm" <<'PY'
import pathlib,json,hashlib,sys
p=pathlib.Path(sys.argv[1]);f=p/'Splatink.zip';gpu=json.loads((p/'mac-gpu.json').read_text())
assert gpu['state']=='playing' and gpu['actors']==8 and gpu['screenshot_error']==0
assert gpu['frame_samples']>100 and gpu['playing_seconds']>20 and not gpu['focus_paused']
if sys.argv[2]=='on':assert gpu.get('native_locomotion',{}).get('active_actors')==8
digest=hashlib.sha256()
with f.open('rb') as inp:
 for block in iter(lambda:inp.read(1048576),b''):digest.update(block)
(p/'build_record.json').write_text(json.dumps({'platform':'macOS','export':'passed','headless_boot_match':'passed','gpu_run':'passed','bytes':f.stat().st_size,'sha256':digest.hexdigest(),'channel':'development','gpu':gpu},indent=2))
PY
echo "SPLATINK_MAC_BUILD $task_out"
