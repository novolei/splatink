#!/bin/bash
set -euo pipefail
task_root="${1:?dedicated Splatink PC snapshot}"
task_role="${2:?host or guest}"
task_address="${3:?LAN host address}"
task_run="${4:?unique run identifier}"
task_native_mm="${5:-off}"
task_verbose="${6:-off}"
task_native_zstd="${7:-off}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) exit 2;; esac
case "$task_role" in host|guest) ;; *) exit 2;; esac
case "$task_run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
case "$task_native_mm" in on|off) ;; *) exit 2;; esac
case "$task_verbose" in on|off) ;; *) exit 2;; esac
case "$task_native_zstd" in on|off) ;; *) exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_log="$task_root/logs/lan-game-$task_run-$task_role.log"
task_engine_args=(--headless)
if [ "$task_verbose" = on ]; then task_engine_args+=(--verbose); fi
task_args=("${task_engine_args[@]}" --path "$task_root/stage" --script res://scripts/net/tests/lan_actual_game_contract.gd --log-file "$task_log" -- "--lan-game-role=$task_role" "--lan-game-host=$task_address" --lan-game-port=27898 "--lan-game-run=$task_run" "--lan-game-output=$task_root/output/lan-game-$task_run-$task_role.json" --nonpersistent --benchmark-background)
if [ "$task_native_mm" = on ]; then task_args+=(--native-locomotion-mm); fi
if [ "$task_native_zstd" = on ]; then task_args+=(--native-tick-zstd); fi
"$task_root/engine/Godot.app/Contents/MacOS/Godot" "${task_args[@]}" > "$task_log.stdout" 2>&1
if grep -Eq 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' "$task_log" "$task_log.stdout"; then exit 1; fi
tail -n 2 "$task_log.stdout"
