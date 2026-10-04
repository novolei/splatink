"""Extend frozen pelvis telemetry with separately scoped physics reach evidence."""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import numpy as np
import analyze_locomotion_pelvis_real_chain as pelvis


def numeric(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def vector(value):
    return isinstance(value, list) and len(value) == 3 and all(numeric(v) for v in value)


def distance(a, b):
    return float(np.linalg.norm(np.asarray(a, dtype=float)-np.asarray(b, dtype=float)))


def diagnostic(row):
    observed = row.get("reach_observation", {})
    data = observed.get("last_reach_diagnostics", {})
    if not observed.get("diagnostic_available") or observed.get("diagnostic_tick_matches_observation") is not True:
        return None
    return data if data.get("tick") == row.get("tick") else None


def scalar_packet(row):
    actual = row.get("actual_body_pose", {})
    observed = row.get("reach_observation", {})
    result = {}
    if numeric(actual.get("hips_local_y")):
        result["actual_hips_local_y_m"] = actual["hips_local_y"]
    if len(actual.get("hips_world_transform", [])) == 4:
        result["actual_hips_world_y_m"] = actual["hips_world_transform"][3][1]
    if observed.get("field_availability", {}).get("_hip_drop") and numeric(observed.get("_hip_drop")):
        result["actual_hip_drop_state_m"] = observed["_hip_drop"]
    data = diagnostic(row)
    if data is not None:
        for field in ["required_drop", "required_drop_unclamped", "applied_drop_requested", "applied_drop", "drop_state_previous", "drop_state_next", "post_footplant_hip_y"]:
            if numeric(data.get(field)):
                result["declared_"+field+"_m"] = data[field]
        if data.get("raw_pose_hip_y_available") and numeric(data.get("raw_pose_hip_y")):
            result["declared_raw_pose_hip_y_m"] = data["raw_pose_hip_y"]
        before = data.get("pre_footplant_hip_position")
        if vector(before):
            result["declared_pre_footplant_hip_y_m"] = before[1]
            if "actual_hips_local_y_m" in result:
                result["actual_postgame_to_declared_pre_hip_correction_m"] = before[1]-result["actual_hips_local_y_m"]
    return result


def tick_changes(rows):
    values, deltas, rates = {}, {}, {}
    for row in rows:
        for key, value in scalar_packet(row).items():
            values.setdefault(key, []).append(value)
    for previous, current in zip(rows, rows[1:]):
        # No bridge over missing ticks or phase boundaries. Units are GAME time.
        if current["tick"]-previous["tick"] != 1 or current["phase"] != previous["phase"]:
            continue
        before, after = scalar_packet(previous), scalar_packet(current)
        dt = current.get("physics_game_dt")
        for key in before.keys() & after.keys():
            delta = abs(after[key]-before[key])
            deltas.setdefault(key, []).append(delta)
            if numeric(dt) and dt > 0:
                rates.setdefault(key, []).append(delta/dt)
    keys = set(values) | set(deltas) | {"actual_hips_local_y_m", "actual_hips_world_y_m", "actual_hip_drop_state_m", "declared_required_drop_m", "declared_applied_drop_m", "declared_raw_pose_hip_y_m", "actual_postgame_to_declared_pre_hip_correction_m"}
    return {"sample_count": len(rows), "status": "covered" if values else "uncovered",
            "observed_values": {key: pelvis.stats(values.get(key, [])) for key in sorted(keys)},
            "absolute_consecutive_tick_change_m": {key: pelvis.stats(deltas.get(key, [])) for key in sorted(keys)},
            "absolute_consecutive_tick_change_per_game_second_mps": {key: pelvis.stats(rates.get(key, [])) for key in sorted(keys)},
            "pair_scope": "Adjacent physics ticks within the same phase; phase/reset gaps are not bridged. No display timestamps are used."}


def reach_metrics(rows):
    fresh = [(row, diagnostic(row)) for row in rows if diagnostic(row) is not None]
    gates = Counter(data.get("gate", "missing") for _, data in fresh)
    legs = [(row, data, leg) for row, data in fresh for leg in data.get("leg_reach", [])]
    leg_fields = ["required_contribution", "raw_required_drop", "reach", "minimum_reach", "horizontal_distance",
                  "vertical_capacity", "requested_distance", "deficit", "clamped_distance", "clamp_distance", "would_clamp_distance", "post_ik_target_error_m"]
    group_names = ["full", "acquisition", "release", "unweighted"]
    group_reported = {name: [] for name in group_names}
    group_actual = {name: [] for name in group_names}
    component_state_errors, raw_state_errors, correction_errors = [], [], []
    reset_nonzero = []
    for row, data in fresh:
        observed = row["reach_observation"]
        if numeric(observed.get("_hip_drop")) and numeric(data.get("drop_state_next")):
            component_state_errors.append(abs(observed["_hip_drop"]-data["drop_state_next"]))
        # The provider consumes its public availability token after copying it
        # into the diagnostic. The diagnostic owns per-call source availability.
        if data.get("raw_pose_hip_y_available") and numeric(observed.get("raw_pose_hip_y")) and numeric(data.get("raw_pose_hip_y")):
            raw_state_errors.append(abs(observed["raw_pose_hip_y"]-data["raw_pose_hip_y"]))
        scalars = scalar_packet(row)
        if "actual_postgame_to_declared_pre_hip_correction_m" in scalars and numeric(data.get("applied_drop")):
            correction_errors.append(abs(scalars["actual_postgame_to_declared_pre_hip_correction_m"]-data["applied_drop"]))
        if data.get("gate") in ["disabled", "teleported", "unconfigured"]:
            if any(numeric(data.get(key)) and abs(data[key]) > 1e-12 for key in ["applied_drop", "drop_state_next"]):
                reset_nonzero.append({"tick": row["tick"], "phase": row["phase"], "gate": data["gate"]})
    for row, data, leg in legs:
        weight = leg.get("weight")
        if not numeric(weight):
            continue
        group = "unweighted" if weight <= .0001 else "full" if leg.get("contact") and weight > .999 else "acquisition" if leg.get("contact") else "release"
        if leg.get("post_ik_observed") and numeric(leg.get("post_ik_target_error_m")):
            group_reported[group].append(leg["post_ik_target_error_m"])
        side = leg.get("side")
        targets, feet = data.get("weighted_world_targets", []), row.get("feet", [])
        if leg.get("post_ik_observed") and side in [0, 1] and len(targets) == len(feet) == 2 and vector(targets[side]) and vector(feet[side]):
            group_actual[group].append(distance(feet[side], targets[side]))
    observed = [row.get("reach_observation", {}) for row in rows]
    return {"physics_sample_count": len(rows), "fresh_diagnostic_samples": len(fresh),
            "status": "covered" if fresh else "uncovered", "gate_counts": dict(gates),
            "missing_diagnostic_samples": sum(not packet.get("diagnostic_available") for packet in observed),
            "stale_or_unassociated_diagnostic_samples": sum(packet.get("diagnostic_available") and packet.get("diagnostic_tick_matches_observation") is not True for packet in observed),
            "leg_diagnostic_observations": len(legs), "leg_status": "covered" if legs else "uncovered",
            "solver_leg_observations": sum(bool(leg.get("solver_invoked")) for _, _, leg in legs),
            "clamped_leg_observations": sum(bool(leg.get("clamped")) for _, _, leg in legs),
            "skipped_solver_would_clamp_observations": sum(not leg.get("solver_invoked") and bool(leg.get("would_clamp")) for _, _, leg in legs),
            "declared_leg_metrics": {key: pelvis.stats([leg[key] for _, _, leg in legs if numeric(leg.get(key)) and (key != "post_ik_target_error_m" or leg.get("post_ik_observed"))]) for key in leg_fields},
            "solver_post_ik_target_error_m": pelvis.stats([leg["post_ik_target_error_m"] for _, _, leg in legs if leg.get("solver_invoked") and leg.get("post_ik_observed") and numeric(leg.get("post_ik_target_error_m"))]),
            "declared_post_ik_target_error_by_weight_m": {key: pelvis.stats(values) for key, values in group_reported.items()},
            "actual_postgame_fk_to_declared_weighted_target_by_weight_m": {key: pelvis.stats(values) for key, values in group_actual.items()},
            "actual_hip_drop_to_declared_next_state_error_m": pelvis.stats(component_state_errors),
            "actual_raw_pose_hip_y_to_declared_error_m": pelvis.stats(raw_state_errors),
            "actual_postgame_correction_to_declared_applied_error_m": pelvis.stats(correction_errors),
            "fresh_reset_nonzero_correction_samples": reset_nonzero,
            "independent_physics_anchor_contacts": pelvis.contact_coverage(rows),
            "physics_tick_changes": tick_changes(rows)}


def body_metrics(report, rows):
    layout = {bone["index"]: bone for bone in report.get("bone_layout", [])}
    poses = [(row, row.get("actual_body_pose", {})) for row in rows if row.get("actual_body_pose", {}).get("all_local_components_recorded")]
    first, positions, scales, source_links = {}, [], [], {}
    parent_mismatches, incomplete = 0, 0
    for row, pose in poses:
        components = pose.get("local_components", [])
        if len(components) != 87 or pose.get("bone_count") != 87:
            incomplete += 1
        first_sample = len(first) == 0
        for bone in components:
            index = bone["index"]
            reference = first.setdefault(index, bone)
            if not first_sample and index != pose.get("hip_index"):
                positions.append(distance(bone["position"], reference["position"]))
            if not first_sample:scales.append(distance(bone["scale"], reference["scale"]))
        for link in pose.get("source_links", []):
            info = source_links.setdefault(link["name"], {"reference": link, "local_lengths": [], "rig_lengths": [], "world_lengths": [], "length_delta": [], "position_delta": []})
            info["local_lengths"].append(link["local_link_length_m"])
            info["rig_lengths"].append(link["rig_space_link_length_m"])
            info["world_lengths"].append(link["world_link_length_m"])
            if len(info["local_lengths"]) > 1:
                info["length_delta"].append(abs(link["local_link_length_m"]-info["reference"]["local_link_length_m"]))
                info["position_delta"].append(distance(link["local_position"], info["reference"]["local_position"]))
            if link["index"] in layout and link["parent_index"] != layout[link["index"]]["parent_index"]:
                parent_mismatches += 1
    declared_position, declared_scale, actual_position, actual_scale = [], [], [], []
    unexpected_positions, unexpected_scales = [], []
    for row in rows:
        data = diagnostic(row)
        if data is None:
            continue
        actual = {bone["index"]: bone for bone in row.get("actual_body_pose", {}).get("local_components", [])}
        for bone in data.get("local_component_rows", []):
            index = bone.get("index")
            before_p, after_p = bone.get("pre_position"), bone.get("post_position")
            before_s, after_s = bone.get("pre_scale"), bone.get("post_scale")
            if index != data.get("hip_index") and vector(before_p) and vector(after_p):
                declared_position.append(distance(before_p, after_p))
            if vector(before_s) and vector(after_s):
                declared_scale.append(distance(before_s, after_s))
            if index in actual and vector(after_p):
                actual_position.append(distance(actual[index]["position"], after_p))
            if index in actual and vector(after_s):
                actual_scale.append(distance(actual[index]["scale"], after_s))
        if numeric(data.get("unexpected_position_changes")):
            unexpected_positions.append(data["unexpected_position_changes"])
        if numeric(data.get("unexpected_scale_changes")):
            unexpected_scales.append(data["unexpected_scale_changes"])
    return {"independent_physics_pose_samples": len(poses), "status": "covered" if poses else "uncovered",
            "temporal_variation_status": "covered" if len(poses) > 1 else "uncovered",
            "incomplete_all87_samples": incomplete, "source_parent_index_mismatches": parent_mismatches,
            "actual_nonhips_local_position_delta_from_first_physics_m": pelvis.stats(positions),
            "actual_all87_local_scale_delta_from_first_physics": pelvis.stats(scales),
            "source_links": {name: {"local_length_m": pelvis.stats(info["local_lengths"]), "rig_length_m": pelvis.stats(info["rig_lengths"]),
                                    "world_length_m": pelvis.stats(info["world_lengths"]), "absolute_local_length_delta_from_first_physics_m": pelvis.stats(info["length_delta"]),
                                    "local_position_delta_from_first_physics_m": pelvis.stats(info["position_delta"])} for name, info in source_links.items()},
            "provider_declared_nonhips_pre_to_post_local_position_change_m": pelvis.stats(declared_position),
            "provider_declared_all87_pre_to_post_local_scale_change": pelvis.stats(declared_scale),
            "actual_postgame_to_provider_declared_after_position_error_m": pelvis.stats(actual_position),
            "actual_postgame_to_provider_declared_after_scale_error": pelvis.stats(actual_scale),
            "provider_declared_unexpected_position_changes": pelvis.stats(unexpected_positions),
            "provider_declared_unexpected_scale_changes": pelvis.stats(unexpected_scales),
            "scope": "First-physics-reference temporal variation is independently observed, not proof of solver causality. Provider before/after is a declared source, compared separately with actual post-game Skeleton."}


def association_metrics(report):
    physical = {row["tick"]: row for row in report.get("physics_samples", [])}
    result = {}
    for stage, rows in [("late_process", report.get("process_samples", [])), ("postdraw", report.get("samples", []))]:
        pairs, hip_errors, link_errors = [], [], []
        for row in rows:
            observation = row.get("reach_observation", {})
            current = physical.get(row.get("tick"))
            if current is not None and observation.get("diagnostic_available") and current.get("reach_observation", {}).get("diagnostic_available"):
                pairs.append((observation, current["reach_observation"]))
            if current is not None:
                actual, authority = row.get("actual_body_pose", {}), current.get("actual_body_pose", {})
                if numeric(actual.get("hips_local_y")) and numeric(authority.get("hips_local_y")):
                    hip_errors.append(abs(actual["hips_local_y"]-authority["hips_local_y"]))
                expected_links = {link["index"]: link for link in authority.get("source_links", [])}
                for link in actual.get("source_links", []):
                    if link["index"] in expected_links:
                        link_errors.append(abs(link["local_link_length_m"]-expected_links[link["index"]]["local_link_length_m"]))
        result[stage] = {"associated_physics_samples": len(pairs), "status": "covered" if pairs else "uncovered",
                         "fresh_diagnostic_samples": sum(diagnostic(row) is not None for row in rows),
                         "available_stale_diagnostic_samples": sum(row.get("reach_observation", {}).get("diagnostic_available") and diagnostic(row) is None for row in rows),
                         "apply_call_mismatches": sum(a.get("apply_calls") != b.get("apply_calls") for a, b in pairs),
                         "diagnostic_payload_mismatches": sum(a.get("last_reach_diagnostics") != b.get("last_reach_diagnostics") for a, b in pairs),
                         "actual_hips_local_y_to_same_tick_physics_error_m": pelvis.stats(hip_errors),
                         "actual_source_link_length_to_same_tick_physics_error_m": pelvis.stats(link_errors),
                         "scope": "Same-tick CPU observation association, including separately counted stale declarations; not proof of GPU presentation."}
    return result


def policy_metrics(report):
    packets = [packet for row in report.get("physics_samples", []) for packet in row.get("actor_reach_policies", [])]
    return {"actor_observations": len(packets), "status": "covered" if packets else "uncovered",
            "mode_counts": dict(Counter(str(packet.get("footplant_reach_mode")) for packet in packets)),
            "nonlocal_continuous_observations": sum(not packet["is_local_player"] and packet.get("continuous_reach") is True for packet in packets),
            "local_continuous_observations": sum(packet["is_local_player"] and packet.get("continuous_reach") is True for packet in packets),
            "nonlocal_continuous_diagnostic_observations": sum(not packet["is_local_player"] and packet.get("diagnostic_continuous_reach") is True for packet in packets),
            "nonoff_render_observations": sum(packet.get("presentation_mode") != "off" or packet.get("presentation_active") is True for packet in packets)}


def analyze(path):
    summary = pelvis.analyze(path)
    report = json.loads(path.read_text(encoding="utf-8"))
    physical = report.get("physics_samples", [])
    summary["diagnostic_version"] = report.get("diagnostic_version", report.get("telemetry_version", 1))
    summary["reach_requested"] = {key: report.get(key, False) for key in ["footplant_reach_trace_requested", "footplant_continuous_reach_requested"]}
    summary["actual_footplant_reach_mode"] = report.get("actual_footplant_reach_mode", "unknown")
    summary["physics_reach"] = reach_metrics(physical)
    summary["physics_body_components"] = body_metrics(report, physical)
    summary["reach_stage_association"] = association_metrics(report)
    summary["actor_reach_policy"] = policy_metrics(report)
    summary["native_clock_query_observation"] = {"status": "recorded" if physical else "uncovered",
        "first": {key: physical[0].get(key) for key in ["native_queries", "motion_queries", "motion_transitions", "motion_time", "clip"]} if physical else {},
        "last": {key: physical[-1].get(key) for key in ["native_queries", "motion_queries", "motion_transitions", "motion_time", "clip"]} if physical else {},
        "scope": "Recorded only; cross-run query/clock equivalence is not asserted by this analyzer."}
    for phase, part in summary["phase_statistics"].items():
        phase_physics = [row for row in physical if row["phase"] == phase]
        part["physics_reach"] = reach_metrics(phase_physics)
        part["physics_body_components"] = body_metrics(report, phase_physics)
    summary["limitations"].extend([
        "Reach diagnostics are included only when their tick equals the independently observed physics tick; stale/reset-missing rows remain uncovered.",
        "Provider declared before/after local components are not an independent pre-FootPlant observer; actual post-game local components are measured separately.",
        "Actual local-position/scale variation relative to the first physics sample includes authored animation and later game systems. It is not automatically a FootPlant modification.",
        "PostIK errors distinguish provider-reported errors from actual Skeleton FK to provider-declared targets, and from independently observed full/partial stance-anchor errors.",
        "Hip correction compares declared pre-FootPlant Y with actual post-game Y; raw AnimationTree hip Y precedes inertialization and is a separate signal.",
        "The provider consumes raw_pose_hip_y_available after each call. Diagnostic token availability describes that call; the false public token after apply is not missing raw-source coverage.",
        "Render remains OFF; this diagnostic does not accept a presentation interpolation algorithm or establish GPU/display frame timing.",
        "Native clocks/queries and all actor policy flags are observed only. Matching counters alone does not prove native matcher or solver arithmetic equivalence.",
    ])
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = [analyze(path) for path in args.files]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for summary in result:
        print(json.dumps({key: value for key, value in summary.items() if key not in ["phase_statistics", "limitations"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
