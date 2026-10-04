#!/bin/bash
set -euo pipefail
# Disposable local QA copy. Never edits the source snapshot or production service.
task_source="/Users/ryanliu/splatink-build/20261003180842-pc"
task_target="/Users/ryanliu/splatink-build/20261004-shutdown-noextension"
task_lock="/Users/ryanliu/splatink-build/engine.lock"
test -d "$task_source/stage"
test ! -e "$task_target"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
mkdir -p "$task_target/stage" "$task_target/logs" "$task_target/output"
rsync -a --exclude=.godot --exclude='*.import' --exclude=addons/motion_matching/gdmotionmatching.gdextension "$task_source/stage/" "$task_target/stage/"
ln -s "$task_source/engine" "$task_target/engine"
touch "$task_target/stage/tools/.gdignore" "$task_target/stage/addons/motion_matching/.gdignore"
cp "$task_source/run_macos_menu_shutdown.sh" "$task_target/run_macos_menu_shutdown.sh"
for task_pass in 1 2; do
  task_log="$task_target/logs/import-$task_pass.log"
  "$task_target/engine/Godot.app/Contents/MacOS/Godot" --headless --editor --path "$task_target/stage" --import --quit --log-file "$task_log" > "$task_log.stdout" 2>&1
  if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode parsing error' "$task_log" "$task_log.stdout"; then
    grep -En 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode parsing error' "$task_log" "$task_log.stdout"
    exit 1
  fi
done
echo "QA no-extension snapshot imported: $task_target"
