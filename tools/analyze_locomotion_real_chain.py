"""Summarize recorded production render frames without generating poses or frames."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import numpy as np


def stats(values):
    values = np.asarray(values, dtype=float)
    if not len(values):
        return {"count": 0, "status": "uncovered"}
    return {"count": len(values), "median": float(np.median(values)),
            "p95": float(np.quantile(values, .95)), "maximum": float(values.max()),
            "status": "covered"}


def finite_observation(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite_observation(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return all(finite_observation(v) for v in value)
    return True


def local_screen_residual(rows):
    # The observed hips include authored gait and camera perspective. This metric
    # describes their screen motion, not an isolated interpolation-error estimate.
    times = np.array([r["wall_us"] / 1e6 for r in rows])
    pixels = np.array([r["screen"] for r in rows])
    residual = []
    for i in range(4, len(rows)-4):
        ids = np.flatnonzero(np.abs(times-times[i]) <= .05)
        if len(ids) < 5 or rows[i]["speed"] < 1:
            continue
        if any(rows[j]["phase"] != rows[i]["phase"] for j in ids):
            continue
        t = times[ids]-times[i]
        design = np.column_stack([np.ones(len(t)), t, t*t])
        coefficients = np.linalg.lstsq(design, pixels[ids], rcond=None)[0]
        residual.append(float(np.linalg.norm(pixels[i]-coefficients[0])))
    return stats(residual)


def quaternion_angle(a, b):
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    norm = np.linalg.norm(a)*np.linalg.norm(b)
    if norm <= 1e-12:
        raise ValueError("Zero-norm transform quaternion")
    cosine = abs(float(np.dot(a, b)/norm))
    return 2*math.acos(float(np.clip(cosine, -1., 1.)))


def observation_pairs(rows):
    for previous, current in zip(rows, rows[1:]):
        dt = (current["wall_us"]-previous["wall_us"])/1e6
        if dt <= 0 or current.get("capture_following", False) or current["phase"] != previous["phase"]:
            continue
        yield previous, current, dt


def contact_coverage(rows):
    """Ankle contacts use existing physics labels, including retiring weights.

    A partial contact's error to its anchor is descriptive, not an assertion that
    a deliberately blended foot should already be locked to that anchor.
    """
    groups = {name: [] for name in ["moving_full", "moving_acquisition", "moving_release",
                                   "stationary_full", "all_weighted"]}
    episodes = {}
    for row in rows:
        if not row["grounded"] or row["form"] != "kid":
            continue
        moving = row["speed"] > 1
        foot = row.get("contacts")
        if foot is None:
            # Legacy rows contain only full-weight errors, never partial labels.
            for error in row["contact_error"]:
                if error >= 0:
                    groups["moving_full" if moving else "stationary_full"].append(error)
            continue
        for leg in range(2):
            weight, contact = foot["weight"][leg], foot["contact"][leg]
            if weight <= .0001:
                continue
            point, anchor = np.array(row["feet"][leg]), np.array(foot["anchor"][leg])
            error = float(np.linalg.norm(point-anchor))
            groups["all_weighted"].append(error)
            full = contact and weight > .999
            if full:
                groups["moving_full" if moving else "stationary_full"].append(error)
            elif moving:
                groups["moving_acquisition" if contact else "moving_release"].append(error)
            if moving:
                key = (leg, foot["episode"][leg])
                episodes.setdefault(key, []).append(point)
    spans = [max(float(np.linalg.norm(p-points[0])) for p in points) for points in episodes.values() if len(points) > 1]
    result = {name: stats(values) for name, values in groups.items()}
    result["moving_weighted_episode_world_span_m"] = stats(spans)
    result["moving_weighted_episodes"] = len(episodes)
    result["partial_labels_available"] = any("contacts" in row for row in rows)
    return result


def render_metrics(rows):
    root_speed, root_acceleration, root_interpolation_error, root_basis_error, root_lag = [], [], [], [], []
    root_rotation, camera_rotation, aim_camera_rotation, aim_direction = [], [], [], []
    visible_muzzle_gap, node_fk_gap, fixed_world_pixels, fixed_camera_pixels = [], [], [], []
    camera_fov_steps, aim_camera_fov_steps = [], []
    previous_velocity = None
    previous_pair_end = None
    previous_dt = None
    for previous, current, dt in observation_pairs(rows):
        velocity = (np.array(current["shown_root"])-np.array(previous["shown_root"]))/dt
        root_speed.append(float(np.linalg.norm(velocity)))
        # Do not bridge excluded capture intervals, phase boundaries or a gap.
        # Consecutive finite-difference velocities lie at interval midpoints.
        if previous_velocity is not None and previous_pair_end is previous:
            root_acceleration.append(float(np.linalg.norm(velocity-previous_velocity)/((dt+previous_dt)*.5)))
        previous_velocity = velocity
        previous_pair_end, previous_dt = current, dt
        for key, output in [("actor_root_transform", root_rotation), ("camera_transform", camera_rotation),
                            ("aim_camera_transform", aim_camera_rotation)]:
            if key in previous and key in current:
                output.append(quaternion_angle(previous[key]["rotation"], current[key]["rotation"]))
        for key, output in [("camera_fov", camera_fov_steps), ("aim_camera_fov", aim_camera_fov_steps)]:
            if key in previous and key in current:
                output.append(abs(float(current[key])-float(previous[key])))
        if "aim_dir" in previous and "aim_dir" in current:
            a, b = np.array(previous["aim_dir"]), np.array(current["aim_dir"])
            if np.linalg.norm(a) > 1e-9 and np.linalg.norm(b) > 1e-9:
                aim_direction.append(math.acos(float(np.clip(np.dot(a, b)/(np.linalg.norm(a)*np.linalg.norm(b)), -1, 1))))
        if "previous_fixed_root_in_current_camera" in current and "fixed_root_screen" in previous:
            old_current_camera = np.array(current["previous_fixed_root_in_current_camera"])
            fixed_world_pixels.append(float(np.linalg.norm(np.array(current["fixed_root_screen"])-old_current_camera)))
            fixed_camera_pixels.append(float(np.linalg.norm(old_current_camera-np.array(previous["fixed_root_screen"]))))
    for row in rows:
        root = row.get("root_observation", {})
        if root.get("interpolation_expected"):
            root_interpolation_error.append(root["expected_root_position_error_m"])
            root_basis_error.append(root["expected_root_basis_error"])
            root_lag.append(root["shown_authority_distance_m"])
        socket = row.get("muzzle_observation", {})
        if socket.get("available"):
            visible_muzzle_gap.append(socket["visible_authority_distance_m"])
            node_fk_gap.append(socket["visible_node_fk_error_m"])
    contact_matches = [r["contact_state_matches_latest_physics"] for r in rows if r.get("contact_state_matches_latest_physics") is not None]
    return {"shown_root_velocity_wall_mps": stats(root_speed), "shown_root_acceleration_wall_mps2": stats(root_acceleration),
            "expected_root_interpolation_position_error_m": stats(root_interpolation_error), "shown_authority_root_lag_m": stats(root_lag),
            "expected_root_interpolation_basis_error": stats(root_basis_error),
            "actor_authority_rotation_step_rad": stats(root_rotation), "camera_rotation_step_rad": stats(camera_rotation),
            "aim_camera_rotation_step_rad": stats(aim_camera_rotation), "actor_aim_direction_step_rad": stats(aim_direction),
            "camera_fov_step_deg": stats(camera_fov_steps), "aim_camera_fov_step_deg": stats(aim_camera_fov_steps),
            "visible_authoritative_muzzle_gap_m": stats(visible_muzzle_gap), "visible_muzzle_node_fk_gap_m": stats(node_fk_gap),
            "fixed_root_screen_world_motion_step_px": stats(fixed_world_pixels), "fixed_root_screen_camera_motion_step_px": stats(fixed_camera_pixels),
            "contact_state_authority_checks": len(contact_matches), "contact_state_authority_mismatches": sum(not match for match in contact_matches),
            "contact_state_authority_status": "covered" if contact_matches else "uncovered"}


def physics_metrics(report):
    rows = report.get("physics_samples", [])
    for row in rows:
        if not finite_observation(row):
            raise ValueError("Nonfinite physics authority observation")
    eligible = [r for r in rows if r["capture"]["eligible"]]
    mismatches = [r for r in eligible if not r["capture"]["components_exact"] or not r["capture"]["root_global_exact"]
                  or not r["capture"]["root_local_exact"] or r["capture"]["packet_rendered"]]
    return {"sample_count": len(rows), "status": "covered" if rows else "uncovered", "capture_eligible_samples": len(eligible),
            "capture_status": "covered" if eligible else "uncovered", "capture_mismatch_samples": len(mismatches),
            "capture_position_error_m": stats([r["capture"]["maximum_position_error_m"] for r in eligible]),
            "capture_quaternion_component_error": stats([r["capture"]["maximum_quaternion_component_error"] for r in eligible]),
            "capture_scale_component_error": stats([r["capture"]["maximum_scale_component_error"] for r in eligible]),
            "contact_coverage": contact_coverage(rows),
            "authoritative_visible_fk_muzzle_gap_m": stats([r["muzzle"]["visible_authority_distance_m"] for r in rows if r["muzzle"].get("available")])}


def analyze(path):
    report = json.loads(path.read_text(encoding="utf-8"))
    if report["failures"]:
        raise ValueError(f"Production observation fixture failed: {path}")
    rows = report["samples"]
    phase_rows = {}
    previous = None
    for row in rows:
        phase_rows.setdefault(row["phase"], []).append(row)
        if not finite_observation(row):
            raise ValueError(f"Nonfinite production observation: {path}:{row['t']}")
        previous = row
    summary = {k: report[k] for k in ["engine", "renderer", "fps_limit", "time_scale",
               "presentation_mode", "sample_count", "synchronous_capture_requested",
               "fully_planted_samples", "maximum_world_contact_error_m", "failures"]}
    summary["source_file"] = str(path)
    summary["extended_mouse_turns_requested"] = report.get("extended_mouse_turns_requested", False)
    summary["provider"] = report["provider"]["provider"]
    summary["native_queries"] = report["provider"].get("native_queries", 0)
    summary["motion_transitions"] = report["provider"].get("transitions", 0)
    summary["hysteresis"] = report["provider"].get("discriminative_hysteresis", {})
    summary["telemetry_version"] = report.get("telemetry_version", 1)
    summary["quality_findings"] = report.get("quality_findings", [])
    summary["physics_authority"] = physics_metrics(report)
    summary["contact_coverage"] = contact_coverage(rows)
    summary["render_metrics"] = render_metrics(rows)
    summary["phase_statistics"] = {}
    for phase, part in phase_rows.items():
        moving = [r for r in part if r["speed"] > 1 and r["grounded"] and r["form"] == "kid"]
        eligible = [r for r in part if r["grounded"] and r["form"] == "kid"
                    and r["avatar_form_time"] >= .45 and phase not in ["jump", "land"]]
        contacts = [v for r in eligible for v in r["contact_error"] if v >= 0]
        summary["phase_statistics"][phase] = {
            "render_frames": len(part), "moving_frames": len(moving),
            "same_physics_tick_moving_frames": sum(r["physics_ticks_since_last_render"] == 0 for r in moving),
            "moving_root_zero_step_frames": sum(r["shown_root_step_m"] < 1e-7 for r in moving),
            "adjacent_render_leg_step_rad": stats([r["leg_step_rad"] for r in eligible]),
            "world_contact_error_m": stats(contacts),
            "physics_ticks_since_last_render": stats([r["physics_ticks_since_last_render"] for r in part]),
            "hips_local_quadratic_screen_residual_px": local_screen_residual(part),
            "contact_coverage": contact_coverage(part),
            "render_metrics": render_metrics(part),
        }
        # Several renders can observe one physics query. Count decision changes
        # once per observed query, while the final provider counters remain the
        # authority when a slow render skips queries entirely.
        observed_queries = {}
        for r in part:
            if "motion_queries" in r:
                observed_queries[r["motion_queries"]] = r.get("hysteresis", {})
        decisions = list(observed_queries.values())
        summary["phase_statistics"][phase]["observed_hysteresis_queries"] = len(decisions)
        summary["phase_statistics"][phase]["observed_predicate_disagreements"] = sum(
            bool(d.get("decision_available")) and
            d.get("legacy_improved") != d.get("new_improved") for d in decisions)
        summary["phase_statistics"][phase]["observed_transition_disagreements"] = sum(
            bool(d.get("decision_available")) and bool(d.get("cooldown_ready")) and
            bool(d.get("distance_ready")) and
            (bool(d.get("legacy_improved")) or bool(d.get("intent_change"))) !=
            (bool(d.get("new_improved")) or bool(d.get("intent_change"))) for d in decisions)
    stable = [r for r in rows if r["grounded"] and r["form"] == "kid"
              and r["avatar_form_time"] >= .45 and r["phase"] not in ["jump", "land"]]
    worst = sorted(stable, key=lambda r: r["leg_step_rad"], reverse=True)[:6]
    summary["maximum_grounded_render_leg_step_rad"] = max((r["leg_step_rad"] for r in stable), default=0.0)
    summary["grounded_render_leg_step_coverage"] = {"count": len(stable), "status": "covered" if stable else "uncovered"}
    summary["largest_grounded_render_steps"] = [{k: r[k] for k in ["t", "phase", "tick",
               "speed", "leg_step_rad", "physics_ticks_since_last_render", "clip"]} for r in worst]
    summary["limitations"] = [
        "Measurement uses the real app and real key/mouse events, eight production actors with idle bots.",
        "Low rendering quality and quiet bots isolate locomotion; this is not an eight-active-bot performance acceptance.",
        "Original FK ankle contacts are measured only during full existing contact weight; no new contact labels.",
        "New partial/release ankle errors and same-episode spans are descriptive; they do not require an intentionally blended foot to be fully locked.",
        "A zero-sample result is uncovered, never a smoothness or authority pass. Legacy data has no physics stream or visible muzzle/FOV evidence.",
        "Render velocity/acceleration uses wall seconds; time_scale=6 moves six game seconds per wall second and is a pressure case, not normal-feel acceptance.",
        "Visible muzzle/root lag is expected during interpolation and is measured separately from authoritative socket consistency.",
        "A screen residual includes deliberate gait, camera motion and perspective, and cannot attribute a cause.",
        "Synchronous screenshot runs must not be used as timing/continuity acceptance.",
        "No exported binary or authored Motorica candidate is accepted by this diagnostic.",
    ]
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = [analyze(p) for p in args.files]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for r in result:
        print(json.dumps({k: v for k, v in r.items() if k not in ["phase_statistics", "limitations"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
