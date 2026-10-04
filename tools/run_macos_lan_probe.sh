#!/bin/bash
set -euo pipefail
task_root="${1:?dedicated Splatink build directory}"
task_role="${2:?host or guest}"
task_address="${3:?LAN host address}"
task_run="${4:?unique probe id}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) exit 2;; esac
case "$task_role" in host|guest) ;; *) exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_log="$task_root/logs/lan-$task_run-$task_role.log"
"$task_root/engine/Godot.app/Contents/MacOS/Godot" --headless --path "$task_root/stage" --script res://scripts/net/tests/lan_process_contract.gd --log-file "$task_log" -- "--lan-probe-role=$task_role" "--lan-probe-host=$task_address" --lan-probe-port=27897 "--lan-probe-run=$task_run" "--lan-probe-output=$task_root/output/lan-$task_run-$task_role.json"
if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_log"; then exit 1; fi
