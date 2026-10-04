"""Compare recorded production landings; never create/interpolate poses or ticks.

Usage: python -B tools/analyze_landing_real_chain.py --baseline BASE.json
       --candidate CANDIDATE.json --output COMPARISON.json
Omit --candidate for a baseline diagnostic. Thresholds are intentionally fixed.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
from statistics import median


CASES = ("walk_off", "jump_off", "air_release")
LEGS = ("thighL", "shinL", "footL", "toeL", "thighR", "shinR", "footR", "toeR")
FORMAL_FIVE = (
    "res://scripts/animation/ink_motion_matcher.gd",
    "res://scripts/animation/native_motion_matcher.gd",
    "res://data/motion_matching.json",
    "res://assets/animation/locomotion.features.bin",
    "res://assets/animation/locomotion.poses.bin",
)
ALLOWED_SOURCE_CHANGES = {
    "res://scripts/characters/ink_avatar.gd": "Candidate landing wiring/lifecycle, authorized by ROOT.",
    "res://scripts/animation/ink_landing_response.gd": "Candidate landing helper, authorized by ROOT.",
    "res://scripts/game/ink_actor.gd": "ROOT-authorized superjump reset_presentation(true) lifecycle change. Hashes cannot prove the diff is limited to that call; ROOT source review is required. Ordinary routes are checked tick by tick below.",
    "res://scripts/game/ink_player_controller.gd": "Assist uses unshaken aim_camera. The landing fixture disables assist and must retain every consumed movement/look command and physical root sample.",
    "res://scripts/game/ink_camera_rig.gd": "PC feedback separates display shake from gameplay aiming. Every recorded fixed-look command and actor root must still match the committed baseline.",
    "res://scripts/ink_game.gd": "PC hit feedback/audio routing only. This quiet, nonfiring landing fixture still requires identical source physics, commands, settings and geometry.",
    "res://tools/landing_physics_observer.gd": "Optional read-only landing helper telemetry v2, authorized by ROOT; actual inputs/ticks/geometry must still match.",
    "res://tools/verify_landing_real_chain.gd": "Source manifest/contract instrumentation v2, authorized by ROOT; control timeline must still match.",
}
NEW_V2_MANIFEST_PATHS = {"res://scripts/animation/ink_hit_recoil.gd", "res://scripts/animation/ink_motion_matcher_fast.gd"}
FROZEN_REQUIRED = FORMAL_FIVE + (
    "res://scripts/game/ink_actor_physics.gd", "res://scripts/game/ink_player_controller.gd",
    "res://scripts/animation/ink_foot_plant.gd", "res://scripts/game/ink_camera_rig.gd",
    "res://data/config.json", "res://data/tidewater.json", "res://data/actor_physics/tidewater.json",
    "res://assets/actor_physics/tidewater.bin", "res://tools/locomotion_physics_observer.gd",
    "res://tools/verify_locomotion_real_chain.gd",
)
LEG_LIMIT_DEG = 20.0
CONTACT_LIMIT_M = 0.03
ROOT_TOLERANCE_M = 1e-6
FILTER_NUMERIC_TOLERANCE_M = 2e-7  # Vector2/Vector3 float32 storage budget; not a stance-quality threshold.
FILTER_RATE_CAP_MPS = 0.6
FULL_WEIGHT = 0.999
ACTIVE_WEIGHT = 0.0001
ANCHOR_STILL_M = 1e-6


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def nonnegative_integer(value):
    return number(value) and value >= 0 and int(value) == value


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, list):
        return all(finite(v) for v in value)
    return True


def vector(value, size=3):
    return isinstance(value, list) and len(value) == size and all(number(v) for v in value)


def norm(v):
    return math.sqrt(sum(x * x for x in v))


def difference(a, b):
    return [x - y for x, y in zip(a, b)]


def distance(a, b, xz=False):
    ids = (0, 2) if xz else range(len(a))
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in ids))


def quaternion_degrees(a, b):
    if a == b:
        return 0.0
    length = norm(a) * norm(b)
    if length <= 1e-12:
        raise ValueError("Zero-norm recorded quaternion")
    cosine = abs(sum(x * y for x, y in zip(a, b)) / length)
    return math.degrees(2.0 * math.acos(min(1.0, max(-1.0, cosine))))


def direction_degrees(a, b):
    length = norm(a) * norm(b)
    if length <= 1e-12:
        return None
    cosine = sum(x * y for x, y in zip(a, b)) / length
    return math.degrees(math.acos(min(1.0, max(-1.0, cosine))))


def stats(values):
    values = sorted(float(v) for v in values)
    if not values:
        return {"status": "uncovered", "count": 0}
    q = (len(values) - 1) * 0.95
    low, high = math.floor(q), math.ceil(q)
    p95 = values[low] + (values[high] - values[low]) * (q - low)
    return {"status": "covered", "count": len(values), "minimum": values[0],
            "median": median(values), "p95": p95, "maximum": values[-1]}


class Checks:
    def __init__(self):
        self.rows = []

    def check(self, label, passed, detail=None):
        item = {"check": label, "passed": bool(passed)}
        if detail is not None:
            item["detail"] = detail
        self.rows.append(item)

    def result(self):
        failures = [r for r in self.rows if not r["passed"]]
        return {"passed": not failures, "checks": len(self.rows),
                "failure_count": len(failures), "failures": failures, "all_checks": self.rows}


def command_signature(row):
    c = row["actual_command"]
    return (tuple(c["move"]), bool(c.get("fire")), bool(c.get("jump")), bool(c.get("swim")),
            float(c.get("aim_yaw", 0.0)), float(c.get("aim_pitch", 0.0)))


def timeline_signature(report):
    hz = int(report["physics_hz"])
    return [(round(float(e["requested_t"]), 9), e["phase"], e["case"], tuple(e["keys"]),
             e.get("reset", ""), bool(e.get("next_tick_input")),
             round(float(e["applied_after_tick_t"]) * hz)) for e in report["real_input_events"]]


def control_flags(report):
    return sorted(arg for arg in report.get("user_args", []) if not arg.startswith("--landing-output="))


def row_key(row, hz):
    return (row["case"], int(row["setup_epoch"]), round(float(row["t"]) * hz))


def adjacent(previous, current):
    return (previous["case"] == current["case"] and previous["setup_epoch"] == current["setup_epoch"]
            and current["tick"] - previous["tick"] == 1
            and not current.get("first_after_setup", False) and current["t"] > previous["t"])


def genuine_land(row, spawn_y):
    previous = row.get("previous_velocity", [])
    position = row["actor_root_transform"]["position"]
    return (row.get("grounded_edge") == "land" and row["grounded"] is True
            and row.get("first_after_setup") is False and vector(previous) and previous[1] < -0.5
            and row.get("source_landed") is True and row["land_time"] <= 0.02
            and row["land_speed"] > 3.0 and position[1] <= 0.05 and position[1] < spawn_y - 2.0)


def validate_record(report, label, checks):
    checks.check(label + ": engine fixture succeeded", report.get("failure_count") == 0 and report.get("failures") == [])
    checks.check(label + ": real main scene", report.get("scene") == "res://scenes/main.tscn"
                 and report.get("current_scene_is_real_app") is True)
    checks.check(label + ": ordinary 60Hz/scale1", report.get("physics_hz") == 60 and report.get("time_scale") == 1.0)
    is_finite = finite(report)
    checks.check(label + ": all numeric observations finite", is_finite)
    if not is_finite:
        raise ValueError(label + " has non-finite observations")
    rows = report.get("physics_samples", [])
    checks.check(label + ": physical/render samples present", len(rows) > 500 and len(report.get("samples", [])) > 60)
    required = {"tick", "t", "case", "setup_epoch", "grounded", "grounded_edge", "source_landed", "source_physics_active",
                "previous_velocity", "first_after_setup", "land_time", "land_speed", "speed", "actual_command", "actor_root_transform",
                "velocity", "lower_exact_components", "hips_world", "hips_local_position", "feet", "contacts", "footplant",
                "action_active", "action_full_body", "action_filter_enabled", "motion_script", "motion_rate"}
    complete = bool(rows) and all(required <= row.keys() for row in rows)
    checks.check(label + ": required landing schema", complete)
    if not complete:
        raise ValueError(label + " has incomplete physics schema")
    checks.check(label + ": source simulation every recorded tick", all(row["source_physics_active"] is True for row in rows))
    checks.check(label + ": provider agrees with every row", bool(report.get("motion_script"))
                 and all(row["motion_script"] == report["motion_script"] for row in rows))
    checks.check(label + ": ordered consecutive physics ticks", all(b["tick"] == a["tick"] + 1 for a, b in zip(rows, rows[1:])))
    checks.check(label + ": manifest stable during recording", bool(report.get("source_before"))
                 and report.get("source_before") == report.get("source_after"))
    manifest = report.get("source_before", {})
    checks.check(label + ": all source identities well formed", bool(manifest) and all(
        path.startswith("res://") and isinstance(identity, dict) and identity.get("bytes", 0) > 0
        and isinstance(identity.get("sha256"), str) and len(identity["sha256"]) == 64
        and all(c in "0123456789abcdefABCDEF" for c in identity["sha256"])
        for path, identity in manifest.items()))
    for path in FROZEN_REQUIRED:
        identity = manifest.get(path, {})
        sha = identity.get("sha256")
        checks.check(label + ": immutable input recorded " + path, identity.get("bytes", 0) > 0
                     and isinstance(sha, str) and len(sha) == 64 and all(c in "0123456789abcdefABCDEF" for c in sha))
    checks.check(label + ": unique case/epoch/relative physics sample keys", len({row_key(row, report["physics_hz"]) for row in rows}) == len(rows))
    for case in CASES:
        case_rows = [r for r in rows if r["case"] == case]
        checks.check(label + ": one setup epoch per case " + case, len({r["setup_epoch"] for r in case_rows}) == 1)
    setups = report.get("setups", [])
    checks.check(label + ": three production spawn setups", [s.get("case") for s in setups] == list(CASES)
                 and all(s.get("grounded") is True and s.get("method") == "production spawn_at + camera follow" for s in setups))
    spawn = report["setup_geometry"]["prepared_spawn"]
    checks.check(label + ": identical source2.2m spawn", abs(spawn[1] - 2.2) < 1e-5
                 and all(distance(s["position"], spawn) <= 1e-5 for s in setups))
    events = report.get("real_input_events", [])
    checks.check(label + ": complete next-tick Input timeline", len(events) == 16 and all(e.get("next_tick_input") is True for e in events))
    checks.check(label + ": physics-quantized input timing", all(-1e-6 <= e["applied_after_tick_t"] - e["requested_t"] <= 1 / 60 + 1e-6 for e in events))
    lands = {case: [row for row in rows if row["case"] == case and genuine_land(row, spawn[1])] for case in CASES}
    for case in CASES:
        checks.check(label + ": actual descending floor land " + case, len(lands[case]) == 1)
        if len(lands[case]) == 1:
            window = [r for r in rows if r["case"] == case and -1e-7 <= r["t"] - lands[case][0]["t"] < 1.0 - 1e-7]
            checks.check(label + ": complete true-land1s physics window " + case, len(window) == report["physics_hz"])
    checks.check(label + ": at least2 genuine descending lands", sum(map(len, lands.values())) >= 2)
    jumping = [r for r in rows if r["case"] == "jump_off" and not r["grounded"] and r["actual_command"].get("jump")
               and r["velocity"][1] > 4.0 and r["actor_root_transform"]["position"][1] > spawn[1] + 0.05]
    checks.check(label + ": real active W+Space jump", bool(jumping))
    release_events = [e for e in events if e["phase"] == "air_release_no_keys" and e.get("pre_grounded") is False and e["keys"] == []]
    release_air = [r for r in rows if r["case"] == "air_release" and r["phase"] == "air_release_no_keys" and not r["grounded"]
                   and norm(r["actual_command"]["move"]) < 0.001 and not r["actual_command"].get("jump")]
    checks.check(label + ": real airborne release", len(release_events) == 1 and len(release_air) >= 3)
    stationary = [r for r in lands["air_release"] if r["speed"] <= 0.25 and norm(r["actual_command"]["move"]) < 0.001
                  and not r["actual_command"].get("jump")]
    checks.check(label + ": zero-input stationary descending land", len(stationary) == 1)
    validate_filter_record(report, label, checks)
    return lands


def contact_metrics(rows):
    errors, xz_errors, weighted_errors, partial_errors = [], [], [], []
    full_pair_speeds, active_pair_speeds, pair_steps = [], [], []
    stationary_body_speeds = []
    counts = Counter()
    episode_points = {}
    for row in rows:
        if not row["grounded"]:
            continue
        contacts = row["contacts"]
        for leg in range(2):
            active, weight = bool(contacts["contact"][leg]), float(contacts["weight"][leg])
            if not active:
                if weight >= ACTIVE_WEIGHT:
                    counts["retiring_weighted_excluded"] += 1
                continue  # Stale release anchors are never stance-error evidence.
            if weight < ACTIVE_WEIGHT:
                counts["active_subthreshold_excluded"] += 1
                continue
            counts["active_weighted_foot_samples"] += 1
            error = distance(row["feet"][leg], contacts["anchor"][leg])
            weighted_errors.append(error)
            if weight > FULL_WEIGHT:
                counts["full_weight_foot_samples"] += 1
                errors.append(error)
                xz_errors.append(distance(row["feet"][leg], contacts["anchor"][leg], xz=True))
                key = (row["case"], row["setup_epoch"], leg, contacts["episode"][leg], tuple(contacts["anchor"][leg]))
                episode_points.setdefault(key, []).append(row["feet"][leg])
            else:
                counts["acquiring_partial_foot_samples"] += 1
                partial_errors.append(error)
    for a, b in zip(rows, rows[1:]):
        if not adjacent(a, b) or not (a["grounded"] and b["grounded"]):
            continue
        dt = b["t"] - a["t"]
        ca, cb = a["contacts"], b["contacts"]
        for leg in range(2):
            if not (ca["contact"][leg] and cb["contact"][leg]):
                continue
            if min(ca["weight"][leg], cb["weight"][leg]) < ACTIVE_WEIGHT:
                continue
            if ca["episode"][leg] != cb["episode"][leg]:
                counts["episode_change_pairs_excluded"] += 1
                continue
            if distance(ca["anchor"][leg], cb["anchor"][leg]) > ANCHOR_STILL_M:
                counts["moving_anchor_pairs_excluded"] += 1
                continue
            step = distance(a["feet"][leg], b["feet"][leg], xz=True)
            active_pair_speeds.append(step / dt)
            counts["same_episode_stationary_anchor_active_pairs"] += 1
            if min(ca["weight"][leg], cb["weight"][leg]) > FULL_WEIGHT:
                full_pair_speeds.append(step / dt)
                pair_steps.append(step)
                counts["same_episode_stationary_anchor_full_pairs"] += 1
                if max(a["speed"], b["speed"]) <= 0.25:
                    stationary_body_speeds.append(step / dt)
    spans = [max(distance(a, b, xz=True) for a in points for b in points)
             for points in episode_points.values() if len(points) >= 2]
    return {"counts": dict(counts), "full_weight_world_anchor_error_m": stats(errors), "full_weight_xz_anchor_error_m": stats(xz_errors),
            "active_weighted_anchor_error_m_descriptive": stats(weighted_errors), "acquiring_partial_anchor_error_m_descriptive": stats(partial_errors),
            "same_episode_stationary_anchor_active_feet_xz_speed_mps_descriptive": stats(active_pair_speeds),
            "same_episode_stationary_anchor_full_feet_xz_speed_mps": stats(full_pair_speeds),
            "same_episode_stationary_anchor_full_feet_xz_step_m": stats(pair_steps), "full_weight_episode_xz_span_m": stats(spans),
            "stationary_actor_full_feet_xz_speed_mps": stats(stationary_body_speeds),
            "scope": "Adjacent physics ticks, same setup/episode, both contacting, unchanged world anchor. Release/stale anchors excluded; partial acquisition errors are not hard-lock errors."}


def pose_metrics(window, all_rows):
    hip_local, hip_world, hip_relative, root_step, leg_angles = [], [], [], [], []
    grounded_leg_angles, landing_edge_angles = [], []
    worst = None
    selected = {r["tick"] for r in window}
    for a, b in zip(all_rows, all_rows[1:]):
        if b["tick"] not in selected or not adjacent(a, b):
            continue
        hip_local.append(distance(a["hips_local_position"], b["hips_local_position"]))
        hip_world.append(distance(a["hips_world"], b["hips_world"]))
        pa, pb = a["actor_root_transform"]["position"], b["actor_root_transform"]["position"]
        hip_relative.append(distance(difference(a["hips_world"], pa), difference(b["hips_world"], pb)))
        root_step.append(distance(pa, pb))
        bones_a = {r["name"]: r for r in a["lower_exact_components"]}
        bones_b = {r["name"]: r for r in b["lower_exact_components"]}
        for name in LEGS:
            angle = quaternion_degrees(bones_a[name]["rotation"], bones_b[name]["rotation"])
            leg_angles.append(angle)
            if a["grounded"] and b["grounded"]:
                grounded_leg_angles.append(angle)
            if b["grounded_edge"] == "land":
                landing_edge_angles.append(angle)
            if worst is None or angle > worst["angle_deg"]:
                worst = {"angle_deg": angle, "bone": name, "t": b["t"], "case": b["case"], "tick": b["tick"],
                         "previous_grounded": a["grounded"], "grounded_edge": b["grounded_edge"], "clip": b["clip"],
                         "action_full_body": b["action_full_body"], "footplant_enabled": b["footplant"]["was_enabled"],
                         "before": pose_evidence(a, name), "after": pose_evidence(b, name)}
    return {"hips_local_position_tick_step_m": stats(hip_local), "hips_world_tick_step_m": stats(hip_world),
            "hips_relative_to_physics_root_tick_step_m": stats(hip_relative), "physics_root_tick_step_m": stats(root_step),
            "lower_rotation_tick_step_deg_including_landing_edge": stats(leg_angles),
            "consecutive_grounded_lower_rotation_tick_step_deg": stats(grounded_leg_angles), "landing_edge_lower_rotation_step_deg": stats(landing_edge_angles),
            "worst_lower_rotation": worst, "scope": "Actual final local quaternions, not raw source animation. Adjacent recorded physics ticks; setup/reset gaps excluded, phase boundaries retained. World hips steps include normal root fall/movement."}


def pose_evidence(row, bone):
    result = {key: row.get(key) for key in ("t", "tick", "grounded", "grounded_edge", "land_time", "action_full_body",
              "clip", "motion_time", "motion_rate", "matched_pose", "hips_local_position", "hips_local_rotation")}
    result["contact"] = row["contacts"]["contact"]
    result["contact_weight"] = row["contacts"]["weight"]
    result["bone_rotation"] = next(b["rotation"] for b in row["lower_exact_components"] if b["name"] == bone)
    result["raw_pre_helper_source_pose"] = "uncovered"
    if "landing_response" in row:
        result["landing_response"] = row["landing_response"]
    return result


def aim_metrics(rows):
    direction_steps, point_steps = [], []
    explicit = [r.get("aim_applied_this_tick") for r in rows if isinstance(r.get("aim_applied_this_tick"), bool)]
    for a, b in zip(rows, rows[1:]):
        if not adjacent(a, b):
            continue
        if vector(a.get("aim_dir")) and vector(b.get("aim_dir")):
            angle = direction_degrees(a["aim_dir"], b["aim_dir"])
            if angle is not None:
                direction_steps.append(angle)
        if vector(a.get("aim_point")) and vector(b.get("aim_point")):
            point_steps.append(distance(a["aim_point"], b["aim_point"]))
    return {"fullbody_guard_blocked_ticks_inferred": sum(r["action_full_body"] for r in rows),
            "aim_blend": stats([r["aim_blend"] for r in rows if number(r.get("aim_blend"))]),
            "actual_aim_direction_tick_step_deg": stats(direction_steps), "actual_aim_point_tick_step_m": stats(point_steps),
            "explicit_aim_execution": {"status": "covered" if explicit else "uncovered", "samples": len(explicit), "applied_ticks": sum(explicit)},
            "dynamic_look_or_fire_exercised": any(r["actual_command"].get("fire") for r in rows)
                or len({(r.get("aim_yaw"), r.get("aim_pitch")) for r in rows}) > 1,
            "limitation": "Full-body Action reports the existing aim early-return gate, not proof that arm aim ran. This timeline has no fire/mouse-look challenge and the base observer has no aim-applied/paused marker."}


def quality_gate(metric, limit, minimum_count=1):
    if metric["count"] < minimum_count:
        return {"status": "uncovered", "limit": limit, "observed": metric, "minimum_count": minimum_count}
    return {"status": "pass" if metric["maximum"] <= limit else "fail", "limit": limit, "observed": metric, "minimum_count": minimum_count,
            "coverage_note": "Threshold applies only to observed samples; sample/episode counts remain visible and are not a guarantee of complete stance coverage."}


def reach_observability(rows):
    lengths, zero_weight_margins = [], []
    for row in rows:
        bones = {b["name"]: b for b in row["lower_exact_components"]}
        for side in ("L", "R"):
            length = norm(bones["shin" + side]["position"]) + norm(bones["foot" + side]["position"])
            lengths.append(length)
            zero_weight_margins.append(length * (1.0 - 0.9995))
    return {"status": "uncovered", "observed_rig_space_segment_sum_m": stats(lengths),
            "source_0_9995_max_reach_shortfall_from_full_extension_m_theoretical": stats(zero_weight_margins),
            "source_formula": "(a+b)*lerp(0.9995,0.985*0.97,weight); local component norms describe authored links, not measured requested targets.",
            "no_zero_clamp_claim": True,
            "limitation": "Base landing trace lacks pre-solve weighted targets, applied/requested clamp distances and solver feasibility. Tiny .9995 reach losses can exist below the 3cm stance threshold. No raw clamp is hidden or rounded to zero; actual clamp counts cannot be recovered here."}


def toward(previous, goal, amount):
    delta = difference(goal, previous)
    length = norm(delta)
    return list(goal) if length <= amount or length <= 1e-15 else [v + d * amount / length for v, d in zip(previous, delta)]


def filtered_policy_metrics(report):
    rows = report["physics_samples"]
    required = report.get("landing_filter_schema_required") in ("pelvis-rate-v3", "pelvis-rate-v4") or report.get("contract") == "landing-real-chain-v3"
    required = required or any(r.get("landing_response", {}).get("last_filter_diagnostics", {}).get("diagnostic_version") in (3, 4) for r in rows)
    if not required:
        return {"status": "legacy_uncovered", "required": False, "passed": None,
                "limitation": "V1/V2 did not record the filtered-pelvis chain. Their helper endpoint diagnostics remain available; no filtering/rate/projection chain validation is inferred."}
    failures, counts = [], Counter()
    raw_errors, move_errors, rate_excess, continuity_errors, applied_errors = [], [], [], [], []
    filtered_write_errors, projection_errors, correction_abs, filtered_rates, corrected_rates = [], [], [], [], []
    previous_row, previous_packet = None, None

    def fail(kind, row, detail):
        counts[kind] += 1
        if len(failures) < 12:
            failures.append({"kind": kind, "tick": row["tick"], "t": row["t"], "detail": detail})

    for row in rows:
        packet = row.get("landing_response", {})
        public_vectors = ("pelvis", "lean_pitch", "head_pitch", "requested_pelvis", "filtered_pelvis", "applied_pelvis")
        public_scalars = ("age", "amplitude", "heavy_weight", "filter_count", "reset_epoch", "apply_count")
        observer_markers_valid = (isinstance(packet, dict) and isinstance(packet.get("active"), bool)
             and isinstance(packet.get("has_apply_diagnostics"), bool) and isinstance(packet.get("last_diagnostics"), dict)
             and "applied_since_previous_observation" in packet
             and (isinstance(packet["applied_since_previous_observation"], bool) or (previous_row is None and packet["applied_since_previous_observation"] is None)))
        observer_markers_valid = observer_markers_valid and all(nonnegative_integer(packet.get(k)) for k in ("filter_count", "reset_epoch", "apply_count"))
        if not isinstance(packet, dict) or packet.get("available") is not True or not observer_markers_valid or not all(vector(packet.get(k), 2) for k in public_vectors) or not all(number(packet.get(k)) for k in public_scalars) or not isinstance(packet.get("last_filter_diagnostics"), dict):
            fail("missing_v3_public_schema", row, "All V3/V4 packets must include spring/raw/filtered/applied vectors, clocks/counts/reset epoch and last_filter_diagnostics; missing is not a V2 fallback.")
            previous_row, previous_packet = row, None
            continue
        f = packet["last_filter_diagnostics"]
        active = packet.get("active") is True
        if not active and packet["filtered_pelvis"] != [0.0, 0.0]:
            fail("inactive_filter_not_reset", row, packet["filtered_pelvis"])
        if previous_packet is not None and adjacent(previous_row, row):
            if packet["filter_count"] < previous_packet["filter_count"] or packet["reset_epoch"] < previous_packet["reset_epoch"]:
                fail("filter_clock_regressed", row, [previous_packet["filter_count"], packet["filter_count"], previous_packet["reset_epoch"], packet["reset_epoch"]])
            if packet["reset_epoch"] > previous_packet["reset_epoch"] and not f:
                counts["reset_cleared_filter_ticks"] += 1
                counts["steps_unobservable_after_reset_clear"] += packet["filter_count"] - previous_packet["filter_count"]
        fresh_step = bool(f) and (previous_packet is None or packet["filter_count"] > previous_packet["filter_count"])
        fresh_apply = active and packet.get("applied_since_previous_observation") is True
        if active or fresh_step or fresh_apply:
            vector_keys = ("previous_pelvis_yz_m", "source_requested_pelvis_yz_m", "goal_pelvis_yz_m", "filtered_pelvis_yz_m", "delta_pelvis_yz_m")
            scalar_keys = ("filter_count", "reset_epoch", "dt_s", "rate_cap_mps")
            if f.get("diagnostic_version") not in (3, 4) or not all(vector(f.get(k), 2) for k in vector_keys) or not all(number(f.get(k)) for k in scalar_keys) or not all(nonnegative_integer(f.get(k)) for k in ("filter_count", "reset_epoch")) or not isinstance(f.get("source_settled"), bool):
                fail("missing_v3_filter_step_schema", row, "Every active V3/V4 sample needs its complete declared filter step, including explicit source_settled goal semantics.")
                previous_row, previous_packet = row, packet
                continue
            if f["filter_count"] != packet["filter_count"] or f["reset_epoch"] != packet["reset_epoch"]:
                fail("stale_v3_filter_step", row, [f["filter_count"], packet["filter_count"], f["reset_epoch"], packet["reset_epoch"]])
            if f["dt_s"] <= 0.0 or abs(f["rate_cap_mps"] - FILTER_RATE_CAP_MPS) > 1e-12:
                fail("wrong_filter_dt_or_rate_cap", row, [f["dt_s"], f["rate_cap_mps"]])
                previous_row, previous_packet = row, packet
                continue
            raw = [min(max(packet["pelvis"][0], -.2), .08) - abs(packet["lean_pitch"][0]) * .06 - .11 * packet["amplitude"] * packet["heavy_weight"], -.02 * packet["amplitude"] * packet["heavy_weight"]]
            raw_error = max(distance(raw, f["source_requested_pelvis_yz_m"]), distance(raw, packet["requested_pelvis"]))
            raw_errors.append(raw_error)
            source_settled = packet["age"] > .8 and packet["heavy_weight"] == 0.0 and max(norm(packet[k]) for k in ("pelvis", "lean_pitch", "head_pitch")) < .00001
            gain = .5 if f["diagnostic_version"] == 4 else 1.0
            if f["diagnostic_version"] == 4 and (not number(f.get("body_displacement_gain")) or f["body_displacement_gain"] != gain):
                fail("body_displacement_gain_changed", row, f.get("body_displacement_gain"))
            expected_goal = [0.0, 0.0] if source_settled else [v * gain for v in f["source_requested_pelvis_yz_m"]]
            if raw_error > FILTER_NUMERIC_TOLERANCE_M or f["source_settled"] != source_settled or distance(f["goal_pelvis_yz_m"], expected_goal) > FILTER_NUMERIC_TOLERANCE_M:
                fail("source_raw_or_settled_goal_changed", row, {"raw_error_m": raw_error, "expected_settled": source_settled, "reported_settled": f["source_settled"]})
            expected = toward(f["previous_pelvis_yz_m"], expected_goal, f["rate_cap_mps"] * f["dt_s"])
            step_error = distance(expected, f["filtered_pelvis_yz_m"])
            delta = difference(f["filtered_pelvis_yz_m"], f["previous_pelvis_yz_m"])
            excess = max(0.0, norm(delta) - f["rate_cap_mps"] * f["dt_s"])
            move_errors.append(step_error)
            rate_excess.append(excess)
            if step_error > FILTER_NUMERIC_TOLERANCE_M or excess > FILTER_NUMERIC_TOLERANCE_M or distance(delta, f["delta_pelvis_yz_m"]) > FILTER_NUMERIC_TOLERANCE_M or distance(packet["filtered_pelvis"], f["filtered_pelvis_yz_m"]) > FILTER_NUMERIC_TOLERANCE_M:
                fail("filtered_move_toward_or_rate_bound", row, {"expected_error_m": step_error, "rate_bound_excess_m": excess})
            if fresh_step:
                counts["fresh_filter_steps"] += 1
                filtered_rates.append(norm(delta) / f["dt_s"])
                if not number(row.get("physics_game_dt")) or row["physics_game_dt"] <= 0.0 or abs(f["dt_s"] - row["physics_game_dt"]) > 1e-9:
                    fail("filter_dt_not_actual_physics_dt", row, [f["dt_s"], row.get("physics_game_dt")])
                if previous_packet is not None and adjacent(previous_row, row) and packet["reset_epoch"] == previous_packet["reset_epoch"]:
                    continuity = distance(f["previous_pelvis_yz_m"], previous_packet["filtered_pelvis"])
                    continuity_errors.append(continuity)
                    if continuity > FILTER_NUMERIC_TOLERANCE_M or packet["filter_count"] != previous_packet["filter_count"] + 1:
                        fail("filter_previous_or_step_count_discontinuous", row, continuity)
        if fresh_apply:
            d = packet.get("last_diagnostics", {})
            hip_keys = ("initial_hip_position_m", "filtered_hip_position_m", "corrected_hip_position_m")
            body_vectors = ("requested_pelvis_yz_m", "filtered_pelvis_yz_m", "applied_pelvis_yz_m", "source_pelvis_state", "source_lean_pitch_state")
            scalar_keys = ("pelvis_correction_y_m", "correction_requested_y_m", "correction_cap_m", "body_target_rate_cap_mps", "filter_count", "reset_epoch")
            if not isinstance(d, dict) or d.get("diagnostic_version") != f.get("diagnostic_version") or not all(vector(d.get(k)) for k in hip_keys) or not all(vector(d.get(k), 2) for k in body_vectors) or not all(number(d.get(k)) for k in scalar_keys) or d.get("filter_step") != f:
                fail("missing_v3_applied_chain_schema", row, "V3/V4 actual applies must have all three Hips positions and matching source/raw/filtered/filter_step/projection fields.")
                previous_row, previous_packet = row, packet
                continue
            if d["diagnostic_version"] == 4 and d.get("body_displacement_gain") != .5:
                fail("applied_body_displacement_gain_changed", row, d.get("body_displacement_gain"))
            counts["fresh_filtered_applies"] += 1
            initial, filtered, corrected = (d[k] for k in hip_keys)
            filtered_expected = [initial[0], initial[1] + packet["filtered_pelvis"][0], initial[2] + packet["filtered_pelvis"][1]]
            projected_expected = [filtered[0], filtered[1] + d["correction_requested_y_m"], filtered[2]]
            actual_applied = [corrected[1] - initial[1], corrected[2] - initial[2]]
            write_error, projection_error = distance(filtered, filtered_expected), distance(corrected, projected_expected)
            applied_error = max(distance(actual_applied, packet["applied_pelvis"]), distance(actual_applied, d["applied_pelvis_yz_m"]))
            filtered_write_errors.append(write_error)
            projection_errors.append(projection_error)
            applied_errors.append(applied_error)
            correction_abs.append(abs(corrected[1] - filtered[1]))
            declarations_error = max(distance(packet["requested_pelvis"], f["source_requested_pelvis_yz_m"]), distance(d["requested_pelvis_yz_m"], packet["requested_pelvis"]), distance(d["filtered_pelvis_yz_m"], packet["filtered_pelvis"]), distance(d["source_pelvis_state"], packet["pelvis"]), distance(d["source_lean_pitch_state"], packet["lean_pitch"]))
            projection_y = corrected[1] - filtered[1]
            if max(write_error, projection_error, applied_error, declarations_error, abs(projection_y - packet.get("pelvis_correction_y", math.inf)), abs(projection_y - d["pelvis_correction_y_m"])) > FILTER_NUMERIC_TOLERANCE_M:
                fail("filtered_projection_actual_chain_changed", row, {"write_error_m": write_error, "projection_error_m": projection_error, "applied_error_m": applied_error, "declarations_error_m": declarations_error})
            if abs(d["correction_cap_m"] - .005) > 1e-12 or abs(d["correction_requested_y_m"]) > .005 + 1e-12 or abs(projection_y) > .005 + FILTER_NUMERIC_TOLERANCE_M or abs(d["body_target_rate_cap_mps"] - FILTER_RATE_CAP_MPS) > 1e-12 or d["filter_count"] != packet["filter_count"] or d["reset_epoch"] != packet["reset_epoch"]:
                fail("projection_cap_or_apply_identity_changed", row, {"requested_y_m": d["correction_requested_y_m"], "actual_y_m": projection_y})
        if previous_packet is not None and adjacent(previous_row, row) and packet["reset_epoch"] == previous_packet["reset_epoch"] and active and previous_packet.get("active") is True:
            corrected_rates.append(distance(packet["applied_pelvis"], previous_packet["applied_pelvis"]) / (row["t"] - previous_row["t"]))
        previous_row, previous_packet = row, packet
    if counts["fresh_filter_steps"] == 0 or counts["fresh_filtered_applies"] == 0:
        failures.append({"kind": "filtered_policy_not_exercised", "detail": dict(counts)})
    return {"status": "covered" if not failures else "failed_closed", "required": True, "passed": not failures, "counts": dict(counts), "failures": failures,
            "numeric_storage_budget_m": FILTER_NUMERIC_TOLERANCE_M, "filtered_target_rate_cap_mps": FILTER_RATE_CAP_MPS,
            "source_raw_formula_error_m": stats(raw_errors), "move_toward_reconstruction_error_m": stats(move_errors), "rate_bound_excess_m_before_projection": stats(rate_excess),
            "filter_previous_continuity_error_m": stats(continuity_errors), "filtered_hip_write_error_m": stats(filtered_write_errors), "projection_hip_write_error_m": stats(projection_errors),
            "actual_applied_reconstruction_error_m": stats(applied_errors), "actual_projection_abs_y_m": stats(correction_abs), "filtered_target_rate_mps": stats(filtered_rates),
            "corrected_applied_body_rate_mps_descriptive": stats(corrected_rates),
            "limitation": "Only the filtered Y/Z target has the .6m/s bound. Reach projection may add up to 5mm Y per tick; corrected body motion, authored animation, rotations and final world feet are independently measured and have no .6m/s guarantee. V3 missing fields fail closed; legacy V2 has no inferred chain."}


def validate_filter_record(report, label, checks):
    summary = filtered_policy_metrics(report)
    if summary["required"]:
        checks.check(label + ": complete V3/V4 source/raw/filter/projection/actual chain and rate bound", summary["passed"], {"counts": summary["counts"], "failures": summary["failures"]})


def helper_metrics(rows):
    packets = [(r, r.get("landing_response", {})) for r in rows]
    available = [(r, p) for r, p in packets if isinstance(p, dict) and p.get("available") is True]
    active = [(r, p) for r, p in available if p.get("active") is True]
    fresh = [(r, p) for r, p in active if p.get("applied_since_previous_observation") is True
             and p.get("has_apply_diagnostics") is True and isinstance(p.get("sample_stage"), str) and p["sample_stage"]]
    counts = Counter()
    foot_errors, rotation_errors, clamp_distances, baseline_clamps = [], [], [], []
    declared_error_deltas, declared_clamp_deltas, requested_yz, applied_yz, correction_y = [], [], [], [], []
    worst_error = None
    for row, packet in fresh:
        diagnostics = packet.get("last_diagnostics", {})
        if not isinstance(diagnostics, dict):
            counts["incomplete_fresh_apply_dictionaries"] += 1
            continue
        if packet.get("correction_feasible") is False:
            counts["correction_infeasible_ticks"] += 1
        if number(diagnostics.get("age")) and number(packet.get("age")) and abs(diagnostics["age"] - packet["age"]) > 1e-9:
            counts["helper_age_mismatch_ticks"] += 1
        if vector(packet.get("requested_pelvis"), 2):
            requested_yz.append(norm(packet["requested_pelvis"]))
        if vector(packet.get("applied_pelvis"), 2):
            applied_yz.append(norm(packet["applied_pelvis"]))
        if number(packet.get("pelvis_correction_y")):
            correction_y.append(packet["pelvis_correction_y"])
        legs = diagnostics.get("legs", [])
        if not isinstance(legs, list):
            counts["incomplete_fresh_leg_packets"] += 1
            continue
        if len(legs) != 2:
            counts["incomplete_fresh_leg_packets"] += 1
        for leg in legs:
            required = ("requested_distance_m", "minimum_reach_m", "reach_m", "clamp_distance_m", "foot_error_m")
            if not isinstance(leg, dict) or not vector(leg.get("target")) or not vector(leg.get("actual")) or not all(number(leg.get(key)) for key in required):
                counts["incomplete_fresh_leg_rows"] += 1
                continue
            if leg["minimum_reach_m"] <= 0.0 or leg["reach_m"] < leg["minimum_reach_m"]:
                counts["invalid_reach_intervals"] += 1
                continue
            # This is independent arithmetic on recorded helper rig-space vectors.
            # It verifies the helper-stage report; final world FK is elsewhere.
            error = distance(leg["target"], leg["actual"])
            requested = leg["requested_distance_m"]
            clamp = abs(requested - min(max(requested, leg["minimum_reach_m"]), leg["reach_m"]))
            foot_errors.append(error)
            clamp_distances.append(clamp)
            declared_error_deltas.append(abs(error - leg["foot_error_m"]))
            declared_clamp_deltas.append(abs(clamp - leg["clamp_distance_m"]))
            counts["fresh_leg_rows"] += 1
            if clamp > 0.0:
                counts["positive_clamp_leg_rows_no_epsilon_hiding"] += 1
            if number(leg.get("baseline_clamp_distance_m")):
                baseline_clamps.append(leg["baseline_clamp_distance_m"])
            if number(leg.get("rotation_error_rad")):
                rotation_errors.append(leg["rotation_error_rad"])
            if worst_error is None or error > worst_error["error_m"]:
                worst_error = {"error_m": error, "t": row["t"], "tick": row["tick"], "side": leg.get("side"),
                               "helper_age": packet.get("age"), "correction_feasible": packet.get("correction_feasible"), "leg": leg}
    return {"status": "covered" if foot_errors else "uncovered", "available_ticks": len(available), "active_ticks": len(active),
            "fresh_apply_ticks": len(fresh), "active_without_fresh_apply_ticks": len(active) - len(fresh), "counts": dict(counts),
            "helper_sample_stages": dict(Counter(p.get("sample_stage", "uncovered") for _, p in available)),
            "helper_foot_error_rig_space_m_recomputed": stats(foot_errors), "helper_foot_rotation_error_rad_declared": stats(rotation_errors),
            "helper_clamp_distance_m_recomputed": stats(clamp_distances), "baseline_clamp_distance_m_declared": stats(baseline_clamps),
            "error_declaration_disagreement_m": stats(declared_error_deltas), "clamp_declaration_disagreement_m": stats(declared_clamp_deltas),
            "requested_pelvis_yz_magnitude_m": stats(requested_yz), "applied_pelvis_yz_magnitude_m": stats(applied_yz),
            "actual_pelvis_correction_local_y_m": stats(correction_y), "worst_helper_foot_error": worst_error,
            "scope": "Optional v2 telemetry from helper apply, in primary rig space. Apply order is explicitly reported in helper_sample_stages/Avatar source hash; it may be before or after inertialization. Stale/no-apply packets excluded; missing older packets remain uncovered. Helper micrometres are not final world-FK or zero-clamp proof."}


def analyze_record(report, lands):
    rows = report["physics_samples"]
    summaries, gates = {}, {}
    for case in CASES:
        if len(lands[case]) != 1:
            summaries[case] = {"status": "uncovered", "genuine_land_count": len(lands[case])}
            gates[case] = {"status": "uncovered"}
            continue
        land = lands[case][0]
        window = [r for r in rows if r["case"] == case and -1e-7 <= r["t"] - land["t"] < 1.0 - 1e-7]
        elapsed = [r["t"] - land["t"] for r in window]
        first_contact, first_full = [], []
        for leg in range(2):
            active = [r["t"] - land["t"] for r in window if r["contacts"]["contact"][leg] and r["contacts"]["weight"][leg] >= ACTIVE_WEIGHT]
            full = [r["t"] - land["t"] for r in window if r["contacts"]["contact"][leg] and r["contacts"]["weight"][leg] > FULL_WEIGHT]
            first_contact.append(min(active) if active else None)
            first_full.append(min(full) if full else None)
        contacts = contact_metrics(window)
        poses = pose_metrics(window, rows)
        disabled = [r for r in window if not r["footplant"]["was_enabled"]]
        fullbody = [r for r in window if r["action_full_body"]]
        guarded = [r for r in window if r["action_active"] and not r["action_filter_enabled"]]
        first_enabled = [r["t"] - land["t"] for r in window if r["footplant"]["was_enabled"]]
        dt = 1.0 / report["physics_hz"]
        summaries[case] = {"status": "covered", "land_t": land["t"], "land_speed": land["land_speed"], "land_horizontal_speed": land["speed"],
                           "post_land_window_s": 1.0, "physics_ticks": len(window), "last_relative_t": max(elapsed) if elapsed else None,
                           "footplant_disabled_ticks": len(disabled), "footplant_disabled_s": len(disabled) * dt,
                           "fullbody_action_ticks": len(fullbody), "fullbody_action_s": len(fullbody) * dt,
                           "aim_fullbody_guard_blocked_s_inferred": len(guarded) * dt,
                           "first_footplant_enabled_delay_s": min(first_enabled) if first_enabled else None,
                           "first_contact_delay_s_by_leg": first_contact, "first_full_weight_contact_delay_s_by_leg": first_full,
                           "contacts": contacts, "poses": poses, "aim": aim_metrics(window), "landing_helper": helper_metrics(window)}
        gates[case] = {
            "lower_rotation_step_20deg": quality_gate(poses["lower_rotation_tick_step_deg_including_landing_edge"], LEG_LIMIT_DEG),
            "full_weight_world_anchor_error_3cm": quality_gate(contacts["full_weight_world_anchor_error_m"], CONTACT_LIMIT_M),
            "full_weight_same_episode_xz_step_3cm": quality_gate(contacts["same_episode_stationary_anchor_full_feet_xz_step_m"], CONTACT_LIMIT_M),
            "full_weight_episode_xz_span_3cm": quality_gate(contacts["full_weight_episode_xz_span_m"], CONTACT_LIMIT_M),
        }
    render = report["samples"]
    intervals = [r["wall_dt"] for r in render if number(r.get("wall_dt")) and r["wall_dt"] > 0]
    measured = len(intervals) / sum(intervals) if intervals else None
    return {"post_land_1s": summaries, "recorded_quality_gates": gates,
            "whole_record_contacts": contact_metrics(rows), "reach_observability": reach_observability(rows), "whole_record_landing_helper": helper_metrics(rows),
            "filtered_pelvis_policy": filtered_policy_metrics(report),
            "render_pacing": {"fps_limit": report["fps_limit"], "measured_wall_fps": measured, "interval_s": stats(intervals),
                              "physics_ticks_per_render": dict(Counter(r["physics_ticks_since_last_render"] for r in render)),
                              "requested_rate_reached_within10pct": measured is not None and measured >= 0.9 * report["fps_limit"],
                              "limitation": "Observed render cadence with detailed observers; neither the FPS limit nor this probe is a full-match production performance result."},
            "aim_execution_verified": False, "reach_clamps_verified": False, "accepted_for_production": False}


def compare_reports(baseline, candidate, checks):
    for field in ("scene", "physics_hz", "time_scale", "fps_limit", "quality", "renderer", "platform", "motion_script", "native_active", "presentation_mode", "pulse_s", "timeline_duration_s", "input_scheduler"):
        checks.check("paired identity " + field, baseline.get(field) == candidate.get(field), {"baseline": baseline.get(field), "candidate": candidate.get(field)})
    checks.check("paired engine version", baseline.get("engine") == candidate.get("engine"))
    checks.check("paired pointer fixture scope", baseline.get("pointer_policy") == candidate.get("pointer_policy") and baseline.get("pointer_handler_enabled") == candidate.get("pointer_handler_enabled"))
    checks.check("paired runtime control flags excluding output path", control_flags(baseline) == control_flags(candidate), {"baseline": control_flags(baseline), "candidate": control_flags(candidate)})
    checks.check("identical real Input control timeline and application ticks", timeline_signature(baseline) == timeline_signature(candidate))
    checks.check("identical prepared map geometry", baseline.get("setup_geometry") == candidate.get("setup_geometry"))
    setup_signature = lambda r: [(s["case"], round(s["t"], 9), s["position"], s["yaw"], s["method"]) for s in r["setups"]]
    checks.check("identical production spawn setup timeline", setup_signature(baseline) == setup_signature(candidate))
    source_a, source_b = baseline["source_before"], candidate["source_before"]
    allowed, frozen_mismatch, instrumentation_additions = [], [], []
    for path in sorted(source_a.keys() | source_b.keys()):
        if source_a.get(path) == source_b.get(path):
            continue
        if path in ALLOWED_SOURCE_CHANGES:
            allowed.append(path)
        elif path in NEW_V2_MANIFEST_PATHS and path not in source_a and path in source_b:
            instrumentation_additions.append(path)
        else:
            frozen_mismatch.append(path)
    checks.check("immutable inputs/old sources unchanged except explicit candidate and instrumentation allowances", not frozen_mismatch, frozen_mismatch)
    for path in FORMAL_FIVE:
        checks.check("paired formal input " + path, path in source_a and source_a.get(path) == source_b.get(path))
    hz = baseline["physics_hz"]
    rows_a = {row_key(r, hz): r for r in baseline["physics_samples"]}
    rows_b = {row_key(r, hz): r for r in candidate["physics_samples"]}
    checks.check("identical recorded physics grid; no tick resampling", rows_a.keys() == rows_b.keys())
    position_errors, velocity_errors, rotation_errors, scale_errors, land_time_errors = [], [], [], [], []
    grounded_changes, command_changes, clip_changes, reach_mode_changes = 0, 0, 0, 0
    worst_root, worst_rotation = None, None
    command_evidence = []
    for key in sorted(rows_a.keys() & rows_b.keys()):
        a, b = rows_a[key], rows_b[key]
        position_error = distance(a["actor_root_transform"]["position"], b["actor_root_transform"]["position"])
        position_errors.append(position_error)
        velocity_errors.append(distance(a["velocity"], b["velocity"]))
        rotation_errors.append(quaternion_degrees(a["actor_root_transform"]["rotation"], b["actor_root_transform"]["rotation"]))
        scale_errors.append(distance(a["actor_root_transform"]["scale"], b["actor_root_transform"]["scale"]))
        land_time_errors.append(abs(a["land_time"] - b["land_time"]))
        grounded_changes += a["grounded"] != b["grounded"]
        command_changed = command_signature(a) != command_signature(b)
        command_changes += command_changed
        if command_changed and len(command_evidence) < 8:
            command_evidence.append({"case": key[0], "relative_tick": key[2], "t": a["t"], "baseline": a["actual_command"], "candidate": b["actual_command"]})
        clip_changes += a["clip"] != b["clip"]
        reach_mode_changes += a["footplant"].get("reach_mode") != b["footplant"].get("reach_mode")
        if worst_root is None or position_error > worst_root["error_m"]:
            worst_root = {"error_m": position_error, "case": key[0], "relative_tick": key[2], "t": a["t"], "baseline": a["actor_root_transform"]["position"], "candidate": b["actor_root_transform"]["position"]}
        if worst_rotation is None or rotation_errors[-1] > worst_rotation["error_deg"]:
            worst_rotation = {"error_deg": rotation_errors[-1], "case": key[0], "relative_tick": key[2], "t": a["t"], "baseline": a["actor_root_transform"]["rotation"], "candidate": b["actor_root_transform"]["rotation"]}
    checks.check("actual consumed controller commands unchanged", command_changes == 0, {"count": command_changes, "first_differences": command_evidence})
    checks.check("actual stance provider/reach policy unchanged", reach_mode_changes == 0, reach_mode_changes)
    checks.check("physics grounded/land timing unchanged", grounded_changes == 0 and max(land_time_errors, default=math.inf) <= 1e-6)
    checks.check("physics root/velocity unchanged within1um", max(position_errors, default=math.inf) <= ROOT_TOLERANCE_M
                 and max(velocity_errors, default=math.inf) <= ROOT_TOLERANCE_M)
    checks.check("physics root rotation/scale unchanged", max(rotation_errors, default=math.inf) <= 1e-4 and max(scale_errors, default=math.inf) <= 1e-6)
    return {"aligned_physics_rows": len(position_errors), "physics_root_position_error_m": stats(position_errors),
            "physics_velocity_error_mps": stats(velocity_errors), "physics_root_rotation_error_deg": stats(rotation_errors), "physics_root_scale_error": stats(scale_errors), "land_time_error_s": stats(land_time_errors),
            "grounded_state_changes": grounded_changes, "actual_command_changes": command_changes, "motion_clip_changes_descriptive": clip_changes,
            "stance_reach_mode_changes": reach_mode_changes,
            "command_observation_scope": "Recorded move/fire/jump/swim/aim_yaw/aim_pitch are paired exactly. Older observer omits sub/special/sub_released and the full consumed command aim_dir/aim_point; this W/S/Space timeline does not exercise those actions. Dynamic aim execution remains unverified.",
            "worst_root_difference": worst_root, "worst_root_rotation_difference": worst_rotation, "first_consumed_command_differences": command_evidence,
            "allowed_source_changes": allowed, "frozen_source_mismatches": frozen_mismatch,
            "allowed_source_change_reasons": {path: ALLOWED_SOURCE_CHANGES[path] for path in allowed}, "instrumentation_manifest_additions": instrumentation_additions,
            "landing_helper_identity_in_both_manifests": "res://scripts/animation/ink_landing_response.gd" in source_a and "res://scripts/animation/ink_landing_response.gd" in source_b,
            "untracked_dependency_limitation": "Older entry records omit the new landing/recoil helper hashes. Added v2 candidate fingerprints prove stability only during that run, not the old baseline identity. Authorized Avatar/Actor/tool paths are explicit differences, not bit-identical claims; exact diff scope needs ROOT review.",
            "cross_fps_limitation": "Different requested FPS is a hard pairing failure. Metrics are still reported individually; matched physics samples do not make different render cadence a fair render comparison."}


def flattened_gate_status(summary):
    statuses = []
    for gates in summary["recorded_quality_gates"].values():
        for gate in gates.values():
            if isinstance(gate, dict):
                statuses.append(gate.get("status", "uncovered"))
            else:
                statuses.append("uncovered")
    return "fail" if "fail" in statuses else "uncovered" if "uncovered" in statuses or not statuses else "pass"


def analyze_files(baseline_path, candidate_path=None):
    checks = Checks()
    result = {"analyzer": "landing-real-chain-v4", "fixed_thresholds": {"lower_rotation_tick_step_deg": LEG_LIMIT_DEG,
              "full_weight_anchor_error_or_same_episode_drift_m": CONTACT_LIMIT_M}, "accepted_for_production": False}
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        lands = validate_record(baseline, "baseline", checks)
        result["baseline"] = {"path": str(baseline_path), "trace_sha256": hashlib.sha256(baseline_path.read_bytes()).hexdigest(), **analyze_record(baseline, lands)}
        result["baseline_recorded_quality_status"] = flattened_gate_status(result["baseline"])
        if candidate_path:
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            lands_b = validate_record(candidate, "candidate", checks)
            result["candidate"] = {"path": str(candidate_path), "trace_sha256": hashlib.sha256(candidate_path.read_bytes()).hexdigest(), **analyze_record(candidate, lands_b)}
            result["comparison"] = compare_reports(baseline, candidate, checks)
            changes = {}
            for case in CASES:
                a, b = result["baseline"]["post_land_1s"][case], result["candidate"]["post_land_1s"][case]
                if a.get("status") != "covered" or b.get("status") != "covered":
                    changes[case] = {"status": "uncovered"}
                    continue
                changes[case] = {field + "_candidate_minus_baseline": b[field] - a[field]
                                 for field in ("footplant_disabled_s", "fullbody_action_s", "aim_fullbody_guard_blocked_s_inferred")}
                changes[case]["first_contact_delay_s_baseline"] = a["first_contact_delay_s_by_leg"]
                changes[case]["first_contact_delay_s_candidate"] = b["first_contact_delay_s_by_leg"]
            result["comparison"]["post_land_gate_changes"] = changes
            result["candidate_recorded_quality_status"] = flattened_gate_status(result["candidate"])
    except (KeyError, ValueError, TypeError, OSError, IndexError, AttributeError) as error:
        checks.check("analysis schema/load/computation completed", False, str(error))
    result["validation"] = checks.result()
    result["verdict"] = ("invalid_comparison" if not result["validation"]["passed"] else
                         "baseline_diagnostic" if candidate_path is None else
                         "candidate_fails_recorded_quality_gates" if result.get("candidate_recorded_quality_status") == "fail" else
                         "candidate_contact_quality_uncovered" if result.get("candidate_recorded_quality_status") != "pass" else
                         "candidate_passes_recorded_gates_aim_and_reach_still_unverified")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = analyze_files(args.baseline, args.candidate)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False), encoding="utf-8")
    print(json.dumps({"verdict": report["verdict"], "validation": {k: v for k, v in report["validation"].items() if k != "all_checks"},
                      "baseline_recorded_quality_status": report.get("baseline_recorded_quality_status"),
                      "candidate_recorded_quality_status": report.get("candidate_recorded_quality_status"), "output": str(args.output)}, allow_nan=False))
    raise SystemExit(0 if report["validation"]["passed"] and (args.candidate is None or report.get("candidate_recorded_quality_status") == "pass") else 1)


if __name__ == "__main__":
    main()
