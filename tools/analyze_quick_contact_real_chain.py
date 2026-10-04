"""Read actual physics packets; never synthesize candidate animation or contacts.

Usage: python -B tools/analyze_quick_contact_real_chain.py BASELINE.json CANDIDATE.json
The default comparison is acquisition gain 18 versus 36. JSON is printed to stdout.
An unqualified candidate returns 1; bad/missing observations return 2.
Heel/ball observations are original source-offset bone proxies, not mesh vertices.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import numpy as np


SOURCE_SHA = "388ff71fff126a79e8e1408cda610f3b3eacd965b14b2e0a41898d2f5f58f5e7"
PARENTS = {"hips": None, "thighL": "hips", "shinL": "thighL", "footL": "shinL", "toeL": "footL",
           "thighR": "hips", "shinR": "thighR", "footR": "shinR", "toeR": "footR"}
LEG_NAMES = [name for name in PARENTS if name != "hips"]
ANCHOR_EPSILON = 1e-5


def stats(values):
    a = np.asarray(values, dtype=float)
    if not a.size:
        return {"status": "uncovered", "count": 0}
    if not np.isfinite(a).all():
        raise ValueError("Nonfinite metric")
    return {"status": "covered", "count": int(a.size), "minimum": float(a.min()),
            "median": float(np.median(a)), "p95": float(np.quantile(a, .95)), "maximum": float(a.max())}


def transform(packet):
    q = np.asarray(packet["rotation"], dtype=float)
    if q.shape != (4,) or not np.isfinite(q).all() or np.linalg.norm(q) < 1e-12:
        raise ValueError("Invalid transform quaternion")
    x, y, z, w = q / np.linalg.norm(q)
    rotation = np.array([[1-2*y*y-2*z*z, 2*x*y-2*w*z, 2*x*z+2*w*y],
                         [2*x*y+2*w*z, 1-2*x*x-2*z*z, 2*y*z-2*w*x],
                         [2*x*z-2*w*y, 2*y*z+2*w*x, 1-2*x*x-2*y*y]])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(packet["scale"])
    result[:3, 3] = packet["position"]
    if not np.isfinite(result).all():
        raise ValueError("Nonfinite transform")
    return result


def angle(a, b):
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    divisor = np.linalg.norm(a)*np.linalg.norm(b)
    if divisor < 1e-12:
        raise ValueError("Zero bone quaternion")
    return 2*math.acos(min(1., abs(float(np.dot(a, b)/divisor))))


def xz_distance(a, b):
    return float(np.linalg.norm((np.asarray(a)-np.asarray(b))[[0, 2]]))


def apply_function(raw):
    found = re.search(rb"(?ms)^func apply\(.*?(?=^func |\Z)", raw)
    if found is None:
        raise ValueError("Missing apply function")
    return found.group(0)


def verify_provider():
    root = Path(__file__).resolve().parents[1]
    source = (root / "scripts/animation/ink_foot_plant.gd").read_bytes()
    candidate = (root / "scripts/animation/experiments/ink_foot_plant_quick_contact.gd").read_bytes()
    base, changed = apply_function(source), apply_function(candidate)
    if changed.count(b"exp(-dt*acquisition_rate)") != 1:
        raise ValueError("Provider must replace acquisition gain exactly once")
    normalized = changed.replace(b"exp(-dt*acquisition_rate)", b"exp(-dt*18.0)")
    sha = hashlib.sha256(source).hexdigest()
    return {"source_sha256": sha, "frozen_source_sha256": SOURCE_SHA,
            "source_hash_matches": sha == SOURCE_SHA,
            "normalized_apply_byte_equal": normalized == base,
            "apply_bytes": len(base), "candidate_sha256": hashlib.sha256(candidate).hexdigest(),
            "scope": "Only acquisition gain differs; configure/static IK are inherited."}


def lower_fk(row):
    components = {bone["name"]: bone for bone in row["lower_exact_components"]}
    if not set(PARENTS).issubset(components):
        raise ValueError("Actual raw hips plus eight leg components are required")
    rig = transform(row["rig_transform"])
    world = {}
    for name, parent in PARENTS.items():
        world[name] = (rig if parent is None else world[parent]) @ transform(components[name])
    proxy = []
    for side in "LR":
        foot = world["foot"+side]
        proxy.append({"heel": (foot @ np.array([0., -.085, -.065, 1.]))[:3],
                      "ball": (foot @ np.array([0., -.085, .11, 1.]))[:3]})
    error = max(float(np.linalg.norm(world["foot"+side][:3, 3]-row["feet"][i]))
                for i, side in enumerate("LR"))
    return components, world, proxy, error


def grounded_kid(row):
    return bool(row["grounded"]) and row["form"] == "kid"


def fresh_pair(previous, current):
    return current["tick"]-previous["tick"] == 1 and float(current["physics_game_dt"]) > 0


def summarize(path, requested_rate):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    rows = data.get("physics_samples", [])
    if len(rows) < 2:
        raise ValueError(f"{path}: at least two actual physics samples are required")
    ticks = [row["tick"] for row in rows]
    if any(b <= a for a, b in zip(ticks, ticks[1:])):
        raise ValueError("Physics packets must have unique increasing ticks")
    fk = [lower_fk(row) for row in rows]
    rendered = {}
    for row in data.get("samples", []):
        rendered[row.get("latest_physics_tick", row.get("tick"))] = row
    clip_file = Path(__file__).resolve().parents[1]/"data/motion_matching.json"
    library = json.loads(clip_file.read_text(encoding="utf-8-sig"))
    tagged_speeds = {clip["name"]: float(np.linalg.norm(clip["velocity"])) for clip in library["clips"]}
    groups = {name: [] for name in ["moving_acquisition", "moving_full", "stationary_acquisition", "stationary_full"]}
    counts = Counter()
    episodes = {}
    pairs = []
    gains = []
    all_steps, settled_steps, hips_steps, world_hips_residual = [], [], [], []
    worst_all = worst_settled = None
    anchor_changes = same_episode_releases = missing_form_clock = 0
    for j, row in enumerate(rows):
        if not grounded_kid(row):
            continue
        contact = row["contacts"]
        moving = float(row["speed"]) > .25
        for leg in range(2):
            weight = float(contact["weight"][leg])
            if not contact["contact"][leg]:
                counts["moving_release" if moving and weight > .0001 else "inactive_or_unweighted"] += 1
                continue  # Retiring anchors never enter slip/error metrics.
            group = ("moving_" if moving else "stationary_") + ("full" if weight > .999 else "acquisition")
            counts[group] += 1
            point, anchor = np.asarray(row["feet"][leg]), np.asarray(contact["anchor"][leg])
            groups[group].append({"ankle_xyz_error_m": float(np.linalg.norm(point-anchor)),
                                  "ankle_xz_error_m": xz_distance(point, anchor), "weight": weight})
            key = (leg, int(contact["episode"][leg]))
            episode = episodes.setdefault(key, {"positions": [], "times": [], "weights": [], "anchors": [], "moving": []})
            episode["positions"].append(point); episode["times"].append(float(row["t"]))
            episode["weights"].append(weight); episode["anchors"].append(anchor); episode["moving"].append(moving)
        if j == 0:
            continue
        previous = rows[j-1]
        if not fresh_pair(previous, row) or not grounded_kid(previous):
            continue
        before, after = fk[j-1][0], fk[j][0]
        hip_step = float(np.linalg.norm(np.asarray(after["hips"]["position"])-before["hips"]["position"]))
        hips_steps.append(hip_step)
        hip_world_delta = fk[j][1]["hips"][:3, 3]-fk[j-1][1]["hips"][:3, 3]
        root_delta = np.asarray(row["avatar_root_transform"]["position"])-previous["avatar_root_transform"]["position"]
        world_hips_residual.append(float(np.linalg.norm(hip_world_delta-root_delta)))
        clocks = [rendered.get(v["tick"], {}).get("avatar_form_time") for v in [previous, row]]
        settled = all(isinstance(clock, (int, float)) and clock >= .5 for clock in clocks)
        if any(clock is None for clock in clocks):
            missing_form_clock += 1
        for name in LEG_NAMES:
            step = angle(before[name]["rotation"], after[name]["rotation"])
            detail = {"radians": step, "bone": name, "tick": row["tick"], "t": row["t"], "phase": row["phase"], "clip": row["clip"]}
            all_steps.append(step)
            if worst_all is None or step > worst_all["radians"]:
                worst_all = detail
            if settled:
                settled_steps.append(step)
                if worst_settled is None or step > worst_settled["radians"]:
                    worst_settled = detail
        old, current = previous["contacts"], row["contacts"]
        for leg in range(2):
            if not (old["contact"][leg] and current["contact"][leg]):
                if old["contact"][leg] and old["episode"][leg] == current["episode"][leg]:
                    same_episode_releases += 1
                continue
            if old["episode"][leg] != current["episode"][leg]:
                continue
            anchor_delta = float(np.linalg.norm(np.asarray(current["anchor"][leg])-old["anchor"][leg]))
            if anchor_delta > ANCHOR_EPSILON:
                anchor_changes += 1
                continue
            dt = float(row["physics_game_dt"])
            old_weight, new_weight = float(old["weight"][leg]), float(current["weight"][leg])
            if 0 <= old_weight < new_weight < .999:
                gains.append(-math.log((1-new_weight)/(1-old_weight))/dt)
            if not (moving and float(previous["speed"]) > .25):
                continue
            floor = float(current["anchor"][leg][1])-.085
            item = {"tick": row["tick"], "t": row["t"], "phase": row["phase"], "clip": row["clip"],
                    "leg": "LR"[leg], "episode": current["episode"][leg], "weight": new_weight,
                    "anchor_delta_m": anchor_delta,
                    "ankle_xz_speed_mps": xz_distance(row["feet"][leg], previous["feet"][leg])/dt,
                    "ankle_xz_error_m": xz_distance(row["feet"][leg], current["anchor"][leg]),
                    "ankle_xyz_error_m": float(np.linalg.norm(np.asarray(row["feet"][leg])-current["anchor"][leg]))}
            for name in ["heel", "ball"]:
                a, b = fk[j-1][2][leg][name], fk[j][2][leg][name]
                item[name+"_height_m"] = float(b[1]-floor)
                item[name+"_xz_speed_mps"] = xz_distance(a, b)/dt
            rate = rendered.get(row["tick"], {}).get("motion_rate")
            if isinstance(rate, (float, int)):
                item["observed_clip_rate"] = rate
                tagged = tagged_speeds.get(row["clip"], 0.)
                if tagged > .1:
                    target_rate = min(1.8, max(.55, float(row["speed"])/tagged))
                    item["virtual_tagged_speed_mps"] = tagged
                    item["target_rate_from_virtual_tag"] = target_rate
                    item["observed_rate_minus_target"] = rate-target_rate
            pairs.append(item)
    episode_metrics = []
    for (leg, key), episode in episodes.items():
        if not any(episode["moving"]):
            continue
        stable = max(float(np.linalg.norm(a-episode["anchors"][0])) for a in episode["anchors"]) <= ANCHOR_EPSILON
        if not stable:
            continue
        episode_metrics.append({"leg": "LR"[leg], "episode": key, "samples": len(episode["positions"]),
                                "span_seconds": episode["times"][-1]-episode["times"][0],
                                "maximum_weight": max(episode["weights"]),
                                "ankle_xz_span_from_first_m": max(xz_distance(v, episode["positions"][0]) for v in episode["positions"]),
                                "includes_stationary_samples": not all(episode["moving"])})
    metrics = ["ankle_xz_speed_mps", "ankle_xz_error_m", "ankle_xyz_error_m", "heel_height_m", "ball_height_m", "heel_xz_speed_mps", "ball_xz_speed_mps"]
    gain_stats = stats(gains)
    observed_rate_matches = bool(gains) and max(abs(v-requested_rate) for v in gains) < .05
    contact_groups = {group: {metric: stats([item[metric] for item in items]) for metric in ["ankle_xyz_error_m", "ankle_xz_error_m", "weight"]}
                      for group, items in groups.items()}
    landing_intervals = []
    for j in range(1, len(rows)):
        if rows[j-1]["grounded"] or not grounded_kid(rows[j]):
            continue
        first = next((k for k in range(j, len(rows)) if any(rows[k]["contacts"]["contact"])), None)
        landing_intervals.append({"tick": rows[j]["tick"], "t": rows[j]["t"], "speed": rows[j]["speed"],
                                  "prelanding_vy": rows[j-1]["velocity"][1],
                                  "first_contact_delay_seconds": None if first is None else rows[first]["t"]-rows[j]["t"],
                                  "scope": "Observed contact gap; packet lacks Action state, so causality is established separately from code."})
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "physics_samples": len(rows), "native_requested": data.get("native_requested"),
            "presentation_mode": data.get("presentation_mode"), "declared_quick_contact": data.get("footplant_quick_contact"),
            "actual_input_events": data.get("real_input_events"), "requested_rate": requested_rate,
            "observed_acquisition_gain": gain_stats, "observed_gain_matches_requested": observed_rate_matches,
            "contact_coverage": dict(counts), "contact_error_by_group": contact_groups,
            "same_active_stationary_anchor_moving_pairs": len(pairs),
            "excluded_changed_anchors": anchor_changes, "excluded_release_pairs": same_episode_releases,
            "moving_pair_metrics": {metric: stats([v[metric] for v in pairs]) for metric in metrics},
            "moving_pair_playback_rate_residual": stats([v["observed_rate_minus_target"] for v in pairs if "observed_rate_minus_target" in v]),
            "virtual_speed_tag_scope": "Playback target uses frozen MM metadata velocity tags, not physical stride measured from an authored moving root. Rate agreement cannot itself prove no sliding.",
            "moving_pair_near_ground_proxy_count": sum(min(abs(v["heel_height_m"]), abs(v["ball_height_m"])) <= .03 for v in pairs),
            "worst_active_contact_pairs": sorted(pairs, key=lambda item: item["ankle_xz_speed_mps"], reverse=True)[:8],
            "moving_episodes": episode_metrics,
            "grounded_hips_local_step_m": stats(hips_steps), "grounded_world_hips_step_after_root_translation_m": stats(world_hips_residual),
            "all_grounded_kid_leg_step_rad": stats(all_steps), "all_grounded_kid_worst": worst_all,
            "settled_grounded_kid_leg_step_rad": stats(settled_steps), "settled_grounded_kid_worst": worst_settled,
            "missing_associated_form_clock_pairs": missing_form_clock,
            "fk_reconstruction_maximum_error_m": max(item[3] for item in fk), "landing_contact_gaps": landing_intervals,
            "proxy_scope": "FK foot offsets heel(0,-.085,-.065), ball(0,-.085,.11); ground=active anchor.y-.085. Bone proxies, never actual shoe mesh vertices.",
            "continuity_scope": "All grounded kid raw joints reported separately. Settled gate requires both associated render form clocks >=.5s, excluding documented kid/squid transition geometry; no phase boundary is skipped."}


def candidate_gates(baseline, candidate, integrity):
    groups = candidate["contact_error_by_group"]
    contacts = [groups[name]["ankle_xyz_error_m"] for name in ["moving_acquisition", "moving_full"]]
    covered = [value for value in contacts if value["count"] > 0]
    steps = candidate["settled_grounded_kid_leg_step_rad"]
    base_hip, new_hip = baseline["grounded_hips_local_step_m"], candidate["grounded_hips_local_step_m"]
    gates = {"provider_normalized_apply_byte_equal": integrity["normalized_apply_byte_equal"] and integrity["source_hash_matches"],
             "baseline_actual_gain_matches_requested": baseline["observed_gain_matches_requested"],
             "default_portable_and_presentation_off": all(v["native_requested"] is False and v["presentation_mode"] == "off" for v in [baseline, candidate]),
             "actual_moving_active_contact_coverage": candidate["same_active_stationary_anchor_moving_pairs"] > 0,
             "actual_gain_matches_candidate": candidate["observed_gain_matches_requested"],
             "fk_reconstruction_valid": candidate["fk_reconstruction_maximum_error_m"] <= 1e-4,
             "moving_declared_contacts_within_existing_3cm": bool(covered) and max(v["maximum"] for v in covered) <= .03,
             "settled_grounded_leg_continuity_within_existing_20degrees": steps["count"] > 0 and steps["maximum"] <= math.pi/9,
             "no_larger_grounded_local_hip_step_than_baseline": base_hip["count"] > 0 and new_hip["count"] > 0 and new_hip["maximum"] <= base_hip["maximum"]+1e-6,
             "input_timeline_equal": baseline["actual_input_events"] == candidate["actual_input_events"] and baseline["actual_input_events"] is not None}
    return gates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path, nargs="?")
    parser.add_argument("candidate", type=Path, nargs="?")
    parser.add_argument("--baseline-rate", type=float, default=18.)
    parser.add_argument("--candidate-rate", type=float, default=36.)
    parser.add_argument("--verify-provider-only", action="store_true")
    args = parser.parse_args()
    try:
        integrity = verify_provider()
        if args.verify_provider_only:
            print(json.dumps(integrity, ensure_ascii=False, indent=2))
            return 0 if integrity["source_hash_matches"] and integrity["normalized_apply_byte_equal"] else 1
        if args.baseline is None or args.candidate is None:
            parser.error("BASELINE.json and CANDIDATE.json are required")
        if not all(math.isfinite(v) and v > 0 for v in [args.baseline_rate, args.candidate_rate]):
            raise ValueError("Acquisition rates must be finite and positive")
        baseline = summarize(args.baseline, args.baseline_rate)
        candidate = summarize(args.candidate, args.candidate_rate)
        gates = candidate_gates(baseline, candidate, integrity)
        result = {"status": "observed_gates_passed" if all(gates.values()) else "rejected",
                  "accepted_for_production": False, "provider_integrity": integrity, "quality_gates": gates,
                  "baseline": baseline, "candidate": candidate,
                  "limits": ["Only actual recorded physics packets; no rerun, fabricated contacts or retiring-anchor slip.",
                             "Partial contacts are deliberately blended; their anchor error is reported, never described as full locking.",
                             "A pass is a scoped diagnostic, not proof of natural locomotion or controller integration.",
                             "Different trajectories, actions or AI/RNG prevent causal performance claims; no FPS claim is made."]}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if all(gates.values()) else 1
    except (ValueError, KeyError, OSError, TypeError) as exc:
        print(json.dumps({"status": "invalid_evidence", "accepted_for_production": False, "error": str(exc)}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    sys.exit(main())
