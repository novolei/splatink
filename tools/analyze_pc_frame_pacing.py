"""Compare controlled real-match captures, retaining timing limitations."""
import argparse
import json
from pathlib import Path


def summarize(report):
    rows = [row for row in report["samples"] if row["phase"] == "warm"]
    intervals = [row["wall_interval_ms"] for row in rows]
    total_ms = sum(intervals)
    return {
        "checks": report["checks"],
        "failures": report["failures"],
        "warm_samples": len(rows),
        "observed_render_callbacks_per_second": len(rows) * 1000 / total_ms,
        "wall_interval_ms": report["warm_metrics"]["wall_interval_ms"],
        "long_frame_counts": {
            str(limit): sum(value > limit for value in intervals)
            for limit in (16.667, 25, 33.333, 50)
        },
        "multiple_physics_tick_render_frames": sum(row["physics_ticks"] > 1 for row in rows),
        "main_gpu_ms": report["warm_metrics"]["main_gpu_ms"],
        "per_actor_matcher_cpu_ms": report["game_profile"].get("avatar_matcher_cpu_ms"),
        "per_actor_total_cpu_ms": report["game_profile"].get("avatar_total_cpu_ms"),
        "actor_and_ai_cpu_ms": report["game_profile"].get("game_actor_and_ai_cpu_ms"),
        "projectile_cpu_ms": report["game_profile"].get("game_projectiles_cpu_ms"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    reports = [json.loads(path.read_text(encoding="utf-8")) for path in (args.before, args.after)]
    settings = [
        "scene", "renderer", "quality", "window", "render_scale", "fps_limit",
        "vsync", "physics_hz", "seed", "actors", "bot_policy",
    ]
    mismatches = {key: [report[key] for report in reports] for key in settings
                  if reports[0][key] != reports[1][key]}
    if mismatches:
        raise ValueError(f"Unmatched comparison settings: {mismatches}")
    if any(report["failures"] for report in reports):
        raise ValueError("Cannot accept reports containing failed checks")
    result = {
        "before_path": str(args.before.resolve()),
        "after_path": str(args.after.resolve()),
        "same_settings": {key: reports[0][key] for key in settings},
        "before": summarize(reports[0]),
        "after": summarize(reports[1]),
        "limitations": [
            "One seeded autonomous match per source; simulation and random event schedules can diverge with timing.",
            "Profiling enabled in both runs adds CPU overhead. Callback rate is not actual display presentation rate.",
            "Main-view GPU timing excludes some auxiliary viewport work.",
            "Performance.TIME_PROCESS and TIME_PHYSICS_PROCESS are periodically refreshed engine monitors, not per-frame causal timings.",
            "Changed feedback and renderer caching are combined changes; this comparison does not isolate each effect.",
            "Animation cost equivalence must be validated separately; faster searching alone does not remove foot sliding.",
        ],
    }
    result["wall_interval_delta_ms"] = {
        key: result["after"]["wall_interval_ms"][key] - result["before"]["wall_interval_ms"][key]
        for key in ("median", "p95", "p99", "max")
    }
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
