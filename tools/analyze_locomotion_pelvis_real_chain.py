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


def process_metrics(report):
    rows = report.get("process_samples", [])
    if any(not finite_observation(row) for row in rows):
        raise ValueError("Nonfinite late process observation")
    wall_intervals, curve_intervals, wall_speed, curve_speed, process_delta = [], [], [], [], []
    for previous, current, dt in observation_pairs(rows):
        wall_intervals.append(dt)
        delta = np.asarray(current["shown_root"])-previous["shown_root"]
        wall_speed.append(float(np.linalg.norm(delta)/dt))
        # Tick/fraction is an Engine coordinate, never a GPU presentation time.
        curve_dt = ((current["tick"]+current["alpha"])-(previous["tick"]+previous["alpha"]))/report["physics_hz"]*report["time_scale"]
        if curve_dt > 0:
            curve_intervals.append(curve_dt)
            curve_speed.append(float(np.linalg.norm(delta)/curve_dt))
    process_delta = [r["process_game_dt_s"] for r in rows]
    post_draw = report["samples"]
    linked = [r for r in post_draw if r.get("process_packet")]
    return {"sample_count": len(rows), "status": "covered" if rows else "uncovered",
            "wall_interval_s": stats(wall_intervals), "engine_process_game_dt_s": stats(process_delta),
            "engine_tick_fraction_game_interval_s": stats(curve_intervals),
            "shown_root_velocity_process_wall_mps": stats(wall_speed),
            "shown_root_velocity_engine_game_mps": stats(curve_speed),
            "post_draw_linked_process_samples": len(linked),
            "post_draw_process_packet_age_s": stats([r["post_draw_process_packet_age_s"] for r in linked]),
            "post_draw_process_frame_offset": stats([r["process_frame"]-r["process_packet"]["process_frame"] for r in linked]),
            "post_draw_process_shown_root_difference_m": stats([float(np.linalg.norm(np.asarray(r["shown_root"])-r["process_packet"]["shown_root"])) for r in linked]),
            "actual_presentation_timestamp_status": "unknown", "gpu_display_timestamp_status": "unknown"}


def runtime_metrics(rows):
    helpers = []
    previous_key = None
    for row in rows:
        helper = row.get("runtime_helper", {})
        if not helper.get("current_render_diagnostics"):
            continue
        key = (helper.get("helper_instance_id"), helper["render_samples"])
        if key == previous_key:
            continue
        previous_key = key
        helpers.append((row, helper))
    legs = [leg for _, helper in helpers for leg in helper.get("last_leg_diagnostics", [])]
    expected_errors, actual_errors, pelvis_fields = [], [], {}
    def collect_errors(value, prefix=""):
        if isinstance(value, dict):
            for key, item in value.items():
                path = prefix+"."+key if prefix else key
                if isinstance(item, (float, int)) and not isinstance(item, bool) and (key.endswith("position_error_m") or key.endswith("basis_error") or key.endswith("rotation_error_rad") or key.endswith("trs_error")):
                    pelvis_fields.setdefault(path, []).append(item)
                else:
                    collect_errors(item, path)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                collect_errors(item, f"{prefix}[{index}]")
    for row, helper in helpers:
        expected, actual = helper.get("expected_world_feet", []), helper.get("actual_world_feet", [])
        if len(expected) == len(actual) == 2:
            expected_errors.extend(np.linalg.norm(np.asarray(row["feet"])-expected, axis=1).tolist())
            actual_errors.extend(np.linalg.norm(np.asarray(row["feet"])-actual, axis=1).tolist())
        collect_errors(helper.get("last_pelvis_diagnostics", {}))
    profile_fields = ["reach_clamps", "significant_reach_clamps", "reach_clamp_distance_m",
                      "total_reach_clamps", "total_significant_reach_clamps", "maximum_reach_clamp_distance_m",
                      "nonuniform_rig_transform", "unsupported_affine_legs", "bone_length_error_m",
                      "world_bone_length_error_m", "world_foot_rotation_error_rad", "pelvis_world_position_error_m",
                      "pelvis_world_basis_error", "pelvis_world_rotation_error_rad", "pelvis_scale_supported",
                      "upper_boundary_position_error_m", "upper_boundary_basis_error", "upper_boundary_trs_error",
                      "upper_boundary_count", "module_upper_position_error_m", "module_upper_basis_error",
                      "module_upper_trs_error", "module_missing_mapped_spine", "module_unmapped_upper_boundary_count",
                      "upper_boundary_local_translation_delta_m", "upper_boundary_local_length_delta_m",
                      "module_upper_local_translation_delta_m", "module_upper_local_length_delta_m"]
    return {"sampled_render_count": len(helpers), "status": "covered" if legs else "uncovered", "leg_observation_count": len(legs),
            "clamped_leg_observations": sum(bool(leg.get("clamped")) for leg in legs),
            "unsupported_affine_leg_observations": sum(bool(leg.get("unsupported_affine")) for leg in legs),
            "reach_clamp_distance_m": stats([leg["clamp_distance"] for leg in legs if "clamp_distance" in leg]),
            "profile_fields": {key: stats([helper["profile"][key] for _, helper in helpers if key in helper.get("profile", {})]) for key in profile_fields},
            "actual_fk_to_runtime_expected_ankle_error_m": stats(expected_errors),
            "actual_fk_to_runtime_reported_ankle_error_m": stats(actual_errors),
            "pelvis_boundary_reported_error_fields": {key: stats(values) for key, values in pelvis_fields.items()},
            "pelvis_diagnostic_status": "covered" if any(helper.get("last_pelvis_diagnostics") for _, helper in helpers) else "uncovered",
            "pelvis_render_scale_unsupported_observations": sum(helper.get("last_pelvis_diagnostics", {}).get("render_scale_supported") is False for _, helper in helpers),
            "count_scope": "Deduplicated adjacent observed helper render ids; cumulative profile counters remain separate. Unobserved renders are not inferred."}


def pelvis_metrics(report, rows):
    physical = report.get("physics_samples", [])
    lookup = {p["tick"]: i for i, p in enumerate(physical)}
    hips_errors, boundary_position, boundary_basis, hips_step = [], [], [], []
    boundary_checks, boundary_missing, unmatched_authority, expected_boundary_counts = 0, 0, 0, []
    for previous, current, _ in observation_pairs(rows):
        if "pose_observation" in previous and "pose_observation" in current:
            hips_step.append(float(np.linalg.norm(np.asarray(current["pose_observation"]["hips_world_transform"][3])-previous["pose_observation"]["hips_world_transform"][3])))
    for row in rows:
        index = lookup.get(row.get("latest_physics_tick"), -1)
        if row.get("latest_physics_tick") != row["tick"]:
            unmatched_authority += 1
            continue
        if index < 0 or "pose_observation" not in row:
            continue
        current = physical[index]
        target = current.get("pose_observation")
        if target is None:
            continue
        # Upper boundary targets stay in current authoritative RIG space.
        # Root translation lag is deliberately excluded from this comparison.
        actual_by_id = {b["index"]: b for b in row["pose_observation"]["upper_boundary"]}
        expected_boundary_counts.append(len(target["upper_boundary"]))
        for boundary in target["upper_boundary"]:
            actual = actual_by_id.get(boundary["index"])
            if actual is None:
                boundary_missing += 1
                continue
            a, b = np.asarray(actual["rig_space_transform"]), np.asarray(boundary["rig_space_transform"])
            boundary_position.append(float(np.linalg.norm(a[3]-b[3])))
            boundary_basis.append(float(np.max(np.linalg.norm(a[:3]-b[:3], axis=1))))
            boundary_checks += 1
        if report["presentation_mode"] != "coherent-pelvis" or not row["root_observation"]["interpolation_expected"]:
            continue
        if not current["capture"]["eligible"]:
            continue
        if current.get("helper_capture_reset") == 1:
            previous = current
        elif index > 0 and physical[index-1]["capture"]["eligible"]:
            previous = physical[index-1]
            if np.linalg.norm(np.asarray(current["capture"]["packet_previous_root"]["position"])-previous["avatar_root_transform"]["position"]) > 1e-5:
                continue
        else:
            continue
        if "pose_observation" not in previous:
            continue
        alpha = float(np.clip(row["alpha"], 0., 1.))
        expected = np.asarray(previous["pose_observation"]["hips_world_transform"][3])*(1-alpha)+np.asarray(target["hips_world_transform"][3])*alpha
        hips_errors.append(float(np.linalg.norm(np.asarray(row["pose_observation"]["hips_world_transform"][3])-expected)))
    return {"actual_world_hips_step_m": stats(hips_step), "independent_world_hips_linear_target_error_m": stats(hips_errors),
            "upper_boundary_rig_space_position_error_m": stats(boundary_position), "upper_boundary_rig_space_basis_error": stats(boundary_basis),
            "upper_boundary_checks": boundary_checks, "upper_boundary_missing": boundary_missing,
            "unmatched_authority_tick_samples": unmatched_authority,
            "upper_boundary_status": "covered" if boundary_checks else "uncovered", "expected_upper_boundary_count": stats(expected_boundary_counts)}


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
    summary["process_timing"] = process_metrics(report)
    summary["runtime_helper_metrics"] = runtime_metrics(rows)
    summary["pelvis_metrics"] = pelvis_metrics(report, rows)
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
            "runtime_helper_metrics": runtime_metrics(part),
            "pelvis_metrics": pelvis_metrics(report, part),
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
        "Late readonly process timestamps are observed after Avatar.present/game/camera, not at the presentation call. GPU/display presentation timestamps remain unknown.",
        "Engine tick+fraction velocity is an interpolation-coordinate diagnostic. It cannot replace wall cadence or prove display smoothness.",
        "Runtime FK/clamp/profile metrics cover sampled helper render ids only; no metrics from missing or stale helper diagnostics are treated as passing.",
        "Upper boundary rig-space preservation counter-translates child joints under the interpolated Hips. Small global FK errors do not prove original Hips-to-upper parent-link lengths, local positions or skin deformation are preserved.",
        "Upper/module local translation and parent-link length deltas are separate quality risks; they cannot be masked by exact physics restoration, zero leg clamps or accurate ankle/pelvis targets.",
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
