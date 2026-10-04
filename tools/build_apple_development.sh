#!/bin/bash
set -euo pipefail
# An isolated dirty development snapshot; this does not publish or alter other games.
task_root="${1:?absolute build directory required}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) echo 'Invalid dedicated build directory'; exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Apple build owns the engine'; exit 3; fi
trap 'task_result=$?; rmdir "$task_lock"; if [ "$task_result" -ne 0 ]; then echo "SPLATINK_APPLE_FAILED exit=$task_result"; fi' EXIT
task_stage="$task_root/stage"
task_engine_dir="$task_root/engine/Godot.app/Contents/MacOS"
task_editor_data="$task_root/engine/editor_data"
task_logs="$task_root/logs"
task_out="$task_root/output"
mkdir -p "$task_logs" "$task_out" "$task_root/engine"
ditto /Applications/Godot.app "$task_root/engine/Godot.app"
touch "$task_engine_dir/_sc_"
mkdir -p "$task_editor_data/export_templates/4.7.1.stable"
for task_template in macos.zip ios.zip version.txt; do
 cp "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/$task_template" "$task_editor_data/export_templates/4.7.1.stable/$task_template"
done
task_godot="$task_engine_dir/Godot"
python3 - "$task_stage" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1])
presets=p/'export_presets.cfg'
presets.write_text(presets.read_text().replace('application/app_store_team_id=""','application/app_store_team_id="94NP7XQA93"'))
project=p/'project.godot'
if 'export/convert_text_resources_to_binary=false' not in project.read_text():
 with project.open('a') as out: out.write('\n[editor]\nexport/convert_text_resources_to_binary=false\n')
stamp=p/'data/build_stamp.json'
data=json.loads(stamp.read_text(encoding='utf-8-sig'));data['platform']='macOS+iOS';stamp.write_text(json.dumps(data,indent=2))
PY
for task_pass in 1 2; do
 "$task_godot" --headless --path "$task_stage" --editor --import --log-file "$task_logs/import-$task_pass.log" > "$task_logs/import-$task_pass.stdout" 2>&1
 if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$task_logs/import-$task_pass.log"; then echo 'APPLE_IMPORT_FAILED'; exit 1; fi
done
"$task_godot" --headless --path "$task_stage" --export-debug 'macOS Development' "$task_out/Splatink.zip" --log-file "$task_logs/macos-export.log" > "$task_logs/macos-export.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$task_logs/macos-export.log"; then echo 'MAC_EXPORT_FAILED'; exit 1; fi
ditto -x -k "$task_out/Splatink.zip" "$task_out/macos"
task_app="$(find "$task_out/macos" -maxdepth 1 -name '*.app' -print -quit)"
task_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$task_app/Contents/Info.plist")"
for task_smoke in boot match; do
 "$task_app/Contents/MacOS/$task_executable" --headless --log-file "$task_logs/mac-smoke-$task_smoke.log" -- "--smoke=$task_smoke" > "$task_logs/mac-smoke-$task_smoke.stdout" 2>&1
 if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$task_logs/mac-smoke-$task_smoke.log" || ! grep -q '"passed":true' "$task_logs/mac-smoke-$task_smoke.log"; then echo 'MAC_SMOKE_FAILED'; exit 1; fi
done
echo 'SPLATINK_MAC_SMOKE_OK'
mkdir -p "$task_out/ios"
"$task_godot" --headless --path "$task_stage" --export-debug 'iOS Development' "$task_out/ios/Splatink.zip" --log-file "$task_logs/ios-export.log" > "$task_logs/ios-export.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$task_logs/ios-export.log"; then echo 'IOS_EXPORT_FAILED'; exit 1; fi
task_xcode="$(find "$task_out/ios" -maxdepth 2 -name '*.xcodeproj' -print -quit)"
if [ -z "$task_xcode" ]; then echo 'IOS_XCODE_PROJECT_MISSING'; exit 1; fi
task_scheme="$(basename "$task_xcode" .xcodeproj)"
xcodebuild -project "$task_xcode" -scheme "$task_scheme" -configuration Debug -sdk iphoneos -destination generic/platform=iOS -archivePath "$task_out/ios/Splatink.xcarchive" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' > "$task_logs/ios-archive.log" 2>&1
grep -q 'ARCHIVE SUCCEEDED' "$task_logs/ios-archive.log" || { echo 'IOS_ARCHIVE_FAILED'; exit 1; }
echo 'SPLATINK_IOS_UNSIGNED_ARCHIVE_OK'
python3 - "$task_out" <<'PY'
import pathlib,json,hashlib,sys
p=pathlib.Path(sys.argv[1]);f=p/'Splatink.zip'
digest=hashlib.sha256()
with f.open('rb') as inp:
 for block in iter(lambda:inp.read(1048576),b''):digest.update(block)
(p/'export_record.json').write_text(json.dumps({'macOS':{'export':'passed','headless_boot_match':'passed','gpu_run':'pending','bytes':f.stat().st_size,'sha256':digest.hexdigest()},'iOS':{'unsigned_archive':'passed','device_run':'pending'},'channel':'development'},indent=2))
PY
echo 'SPLATINK_APPLE_EXPORT_OK'
