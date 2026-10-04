#!/bin/bash
set -euo pipefail
task_root="${1:?Existing dedicated Mixamo QA snapshot}"
case "$task_root" in /Users/*/splatink-build/20261004-mixamo-turns) ;; *) exit 2;; esac
test -f "$task_root/stage/tools/verify_mixamo_visual.gd"
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_log="$task_root/logs/mac-mixamo-visual-native.log"
"$task_root/engine/Godot.app/Contents/MacOS/Godot" --path "$task_root/stage" --script res://tools/verify_mixamo_visual.gd --rendering-method mobile --log-file "$task_log" -- --native-locomotion-mm --nonpersistent --benchmark-background > "$task_log.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode' "$task_log" "$task_log.stdout"; then
  grep -En 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode' "$task_log" "$task_log.stdout"
  exit 1
fi
mkdir -p "$task_root/output/visual"
for task_frame in 000 025 050 075 100; do
  cp "$task_root/stage/shots/mixamo-turn-$task_frame.png" "$task_root/output/visual/"
done
tail -n 1 "$task_log.stdout"
