#!/bin/bash
set -euo pipefail
task_root="${1:?dedicated Splatink snapshot}"
task_verbose="${2:-off}"
task_native="${3:-on}"
task_isolation="${4:-none}"
case "$task_root" in /Users/*/splatink-build/*) ;; *) exit 2;; esac
case "$task_verbose" in on|off) ;; *) exit 2;; esac
case "$task_native" in on|off) ;; *) exit 2;; esac
case "$task_isolation" in none|audio|game) ;; *) exit 2;; esac
task_lock="$(dirname "$task_root")/engine.lock"
if ! mkdir "$task_lock" 2>/dev/null; then echo 'Another Splatink Mac probe owns the engine'; exit 3; fi
trap 'rmdir "$task_lock"' EXIT
task_label="$task_verbose"
if [ "$task_native" = off ]; then task_label="$task_verbose-mmoff"; fi
if [ "$task_isolation" != none ]; then task_label="$task_label-$task_isolation"; fi
task_log="$task_root/logs/menu-shutdown-$task_label.log"
task_args=(--headless)
if [ "$task_verbose" = on ]; then task_args+=(--verbose); fi
task_args+=(--path "$task_root/stage" --script res://tools/diagnose_menu_shutdown.gd --log-file "$task_log" -- "--output=$task_root/output/menu-shutdown-$task_label.json")
if [ "$task_native" = on ]; then task_args+=(--native-locomotion-mm); fi
if [ "$task_isolation" = audio ]; then task_args+=(--drain-audio); fi
if [ "$task_isolation" = game ]; then task_args+=(--release-game); fi
"$task_root/engine/Godot.app/Contents/MacOS/Godot" "${task_args[@]}" > "$task_log.stdout" 2>&1
grep -E 'MENU_SHUTDOWN|SCRIPT ERROR|ERROR:|WARNING:|Leaked instance:' "$task_log.stdout" || true
