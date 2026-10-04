#!/bin/bash
set -euo pipefail
task_root="${1:?dedicated Apple build directory required}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
mkdir "$task_lock" || { echo 'Splatink build engine busy'; exit 3; }
trap 'task_result=$?; rmdir "$task_lock"; if [ "$task_result" -ne 0 ]; then echo "SPLATINK_IOS_FAILED exit=$task_result"; fi' EXIT
task_stage="$task_root/stage"
task_logs="$task_root/logs"
task_out="$task_root/output/ios-project"
mkdir -p "$task_out"
python3 - "$task_stage/export_presets.cfg" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
if 'application/export_project_only=true' not in s:s=s.replace('application/signature=""','application/signature=""\napplication/export_project_only=true')
p.write_text(s)
PY
"$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_stage" --export-debug 'iOS Development' "$task_out/Splatink.zip" --log-file "$task_logs/ios-project-export.log" > "$task_logs/ios-project-export.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$task_logs/ios-project-export.log"; then echo 'IOS_PROJECT_EXPORT_FAILED'; exit 1; fi
xcodebuild -project "$task_out/Splatink.xcodeproj" -scheme Splatink -configuration Debug -sdk iphoneos -destination generic/platform=iOS -derivedDataPath "$task_root/ios-derived-data" -archivePath "$task_out/Splatink.xcarchive" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' > "$task_logs/ios-unsigned-archive.log" 2>&1
grep -q 'ARCHIVE SUCCEEDED' "$task_logs/ios-unsigned-archive.log" || exit 1
echo 'SPLATINK_IOS_UNSIGNED_ARCHIVE_OK'
python3 - "$task_out" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);(p/'export_record.json').write_text(json.dumps({'export':'passed','unsigned_archive':'passed','device_run':'pending','channel':'development'},indent=2))
PY
