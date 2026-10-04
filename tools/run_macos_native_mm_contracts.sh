#!/bin/bash
set -euo pipefail
task_root="${1:?dedicated Splatink PC snapshot}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
for task_test in verify_native_motion_matching verify_motion_matching verify_aiming; do
  task_log="$task_root/logs/mac-$task_test.log"
  "$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_root/stage" --script "res://tools/$task_test.gd" --log-file "$task_log" -- --native-locomotion-mm --nonpersistent --benchmark-background > "$task_log.stdout" 2>&1
  if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_log" "$task_log.stdout"; then exit 1; fi
  tail -n 2 "$task_log.stdout"
done
