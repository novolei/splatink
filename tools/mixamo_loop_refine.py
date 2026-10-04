"""Offline, default-off target-space refinement of frozen Mixamo loop curves.

Reads only the frozen source9 retimed six-metre/second candidates. No engine,
Blender, SSH, gameplay root, target bone length, source ZIP, or production database
is changed. All declared variants and diagnostic failures are exported.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import numpy as np
import mixamo_retarget as m
import mixamo_loop_retarget as frozen

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "assets/animation/experiments/mixamo_loops/loops.json"
OUTPUT = ROOT / "assets/animation/experiments/mixamo_loops_refined"
CACHE = ROOT / ".tools/mixamo-loop-refined"
SPEED = 6.0
BAKE_HZ = 240
PELVIS_LIMIT_M = .04
REACH_MARGIN_M = .00001
CONTACT_RAMP_S = .020
ANTICIPATORY_RAMP_S = .035
SOURCES = ["running.fbx", "left strafe.fbx", "right strafe.fbx"]
VARIANTS = [("raw_dense", 0., False), ("smooth20", .020, False),
            ("smooth35", .035, False), ("smooth20_contact", .020, True),
            ("smooth35_contact", .035, True),
            ("smooth20_anticipatory_roll_contact", .020, "anticipatory_roll"),
            ("smooth35_anticipatory_roll_contact", .035, "anticipatory_roll")]
FPS = [60, 30, 144]
ROT_LIMIT = {60: .35, 30: .7}
SLIDE_LIMIT = .03
SOLE = np.array([[0., -.085, -.065], [0., -.085, .11]])


def provenance(path):
    s = path.stat()
    return {"path": str(path), "size_bytes": s.st_size, "mtime_ns": s.st_mtime_ns,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def write(path, payload):
    if not any(path.resolve().is_relative_to(p.resolve()) for p in [OUTPUT, CACHE]):
        raise ValueError("Refined experiment output escaped its owned directories")
    if path.is_symlink():
        raise ValueError("Refusing a symlink output")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(payload, encoding="utf-8", newline="\n")
    temporary.replace(path)


def dump(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n"


def pose_copy(p):
    return [{k: list(v) for k, v in b.items()} for b in p]


def sample_frames(frames, duration, time, preserve_end=False):
    if preserve_end and abs(time-duration) < 1e-10:
        return pose_copy(frames[-1]["lower"])
    phase = time % duration
    times = np.array([f["time"] for f in frames])
    high = min(int(np.searchsorted(times, phase, side="right")), len(frames)-1)
    low = max(0, high-1)
    weight = (phase-times[low]) / (times[high]-times[low])
    result = []
    for a, b in zip(frames[low]["lower"], frames[high]["lower"]):
        result.append({"position": (np.array(a["position"])*(1-weight)+np.array(b["position"])*weight).tolist(),
                       "rotation": frozen.slerp(a["rotation"], b["rotation"], weight).tolist(),
                       "scale": [1, 1, 1]})
    return result


def periodic_filter(values, sigma_s, step_s, quaternions=False):
    """Gaussian circular convolution; sigma and four-sigma support are explicit."""
    values = np.asarray(values)
    if sigma_s == 0:
        return values.copy(), {"sigma_s": 0., "support_half_width_s": 0., "kernel_samples": 1}
    half = int(math.ceil(4*sigma_s/step_s))
    offsets = np.arange(-half, half+1)
    kernel = np.exp(-.5*(offsets*step_s/sigma_s)**2)
    kernel /= kernel.sum()
    result = np.zeros_like(values)
    for i in range(len(values)):
        neighborhood = values[(i+offsets) % len(values)].copy()
        if quaternions:
            neighborhood[np.sum(neighborhood*values[i], axis=1) < 0] *= -1
        result[i] = np.tensordot(kernel, neighborhood, axes=1)
        if quaternions:
            result[i] /= np.linalg.norm(result[i])
    return result, {"sigma_s": sigma_s, "support_half_width_s": half*step_s,
                    "kernel_samples": len(kernel), "kernel": kernel.tolist(),
                    "phase_delay_s": 0., "boundary": "circular, no period extension"}


def sample_array(values, duration, time, quaternions=False):
    position = time % duration / duration * len(values)
    low = int(math.floor(position))
    high = (low+1) % len(values)
    fraction = position-low
    return frozen.slerp(values[low], values[high], fraction) if quaternions else values[low]*(1-fraction)+values[high]*fraction


def contact_windows(source, clip, raw_world):
    """Nearest-source-key contact labels, including a single wrap-spanning run."""
    duration = clip["duration"]
    n = len(clip["frames"])-1
    key_step = duration/n
    result = []
    for side_index, side in enumerate(["L", "R"]):
        mask = np.array([f["source_contact_candidate"][side_index] for f in clip["frames"][:-1]])
        if not mask.any() or mask.all():
            raise ValueError("Expected inferred source stance and swing intervals")
        starts = [i for i in range(n) if mask[i] and not mask[(i-1) % n]]
        for start in starts:
            count = 1
            while mask[(start+count) % n]:
                count += 1
            begin = (start-.5)*key_step
            if begin < 0:
                begin += duration
            end = begin + count*key_step
            pose = sample_frames(clip["frames"], duration, begin)
            world = frozen.fk(pose, source["target"])
            points = m.foot_points(world["foot"+side])
            point = int(points[:, 1].argmin())
            result.append({"window_id": len(result), "leg": side_index, "side": side,
                           "start_s": begin, "end_s": end, "crosses_cycle_wrap": end > duration,
                           "duration_s": end-begin, "sole_point": point,
                           "source_key_count": count, "source_key_start": start,
                           "acquisition_s": CONTACT_RAMP_S, "release_s": CONTACT_RAMP_S,
                           "full_weight_duration_s": max(0., end-begin-2*CONTACT_RAMP_S)})
    return result


def window_at(windows, side, phase, duration):
    for window in windows:
        if window["leg"] != side:
            continue
        t = phase
        cycle = 0
        if t < window["start_s"]:
            t += duration
            cycle = -1
        if window["start_s"] <= t < window["end_s"]:
            ramp = min((t-window["start_s"])/CONTACT_RAMP_S, (window["end_s"]-t)/CONTACT_RAMP_S, 1.)
            weight = max(0., ramp)**2 * (3-2*max(0., ramp))
            return window, t, cycle, weight
    return None, phase, 0, 0.


def anticipatory_window_at(windows, side, phase, duration):
    """Acquire in preceding swing; every original inferred stance is full weight."""
    for window in windows:
        if window["leg"] != side:
            continue
        for shift in [0, 1, -1]:
            t = phase+shift*duration
            if window["start_s"]-ANTICIPATORY_RAMP_S <= t < window["end_s"]+ANTICIPATORY_RAMP_S:
                ramp = min((t-window["start_s"]+ANTICIPATORY_RAMP_S)/ANTICIPATORY_RAMP_S,
                           (window["end_s"]+ANTICIPATORY_RAMP_S-t)/ANTICIPATORY_RAMP_S, 1.)
                weight = max(0., ramp)**2*(3-2*max(0., ramp))
                return window, t, -shift, weight
    return None, phase, 0, 0.


def make_geometry(raw_poses, raw_world, duration, sigma):
    step = duration/len(raw_poses)
    endpoints, orientations, toes = {}, {}, {}
    policies = {}
    for side in ["L", "R"]:
        endpoints[side], policies["ankle_position"] = periodic_filter(
            [w["foot"+side][:3, 3] for w in raw_world], sigma, step)
        orientations[side], policies["foot_world_rotation"] = periodic_filter(
            [m.quat(w["foot"+side][:3, :3]) for w in raw_world], sigma, step, True)
        index = 4 if side == "L" else 8
        toes[side], policies["toe_local_rotation"] = periodic_filter(
            [p[index]["rotation"] for p in raw_poses], sigma, step, True)
    return endpoints, orientations, toes, policies


def prepare_anchors(windows, endpoints, orientations, duration, direction):
    result = []
    for window in windows:
        item = dict(window)
        side, start, point = item["side"], item["start_s"], item["sole_point"]
        endpoint = sample_array(endpoints[side], duration, start)
        q = sample_array(orientations[side], duration, start, True)
        p = endpoint + m.qmatrix(q) @ SOLE[point] + SPEED*start*direction
        item["unconstrained_anchor_world_m"] = p.tolist()
        p[1] = 0.
        item["anchor_world_at_start_m"] = p.tolist()
        item["anchor_foot_world_rotation"] = q.tolist()
        item["ground_policy"] = "explicit offline flat ground y=0, not a runtime terrain query"
        result.append(item)
    return result


def pelvis_adjustment(raw_world, endpoints, target):
    """Minimal iterative sphere projections; bounded displacement, no stretching."""
    displacement = np.zeros(3)
    requested = np.zeros(3)
    for _ in range(10):
        prior = requested.copy()
        for side in ["L", "R"]:
            origin = raw_world["thigh"+side][:3, 3] + requested
            vector = endpoints[side]-origin
            reach = sum(np.linalg.norm(target["local"][part+side][:3, 3]) for part in ["shin", "foot"]) - REACH_MARGIN_M
            distance = np.linalg.norm(vector)
            if distance > reach:
                requested += vector/distance*(distance-reach)
        if np.linalg.norm(requested-prior) < 1e-10:
            break
    displacement = requested.copy()
    length = np.linalg.norm(displacement)
    if length > PELVIS_LIMIT_M:
        displacement *= PELVIS_LIMIT_M/length
    return displacement, requested


def solve_pose(raw_pose, target, endpoints, orientations, toe_rotations):
    """Transport the signed raw knee plane; shortest swings retain axial twist."""
    world = frozen.fk(raw_pose, target)
    pose = pose_copy(raw_pose)
    pelvis, requested_pelvis = pelvis_adjustment(world, endpoints, target)
    pose[0]["position"] = (np.array(pose[0]["position"])+pelvis).tolist()
    indices = {n: i for i, n in enumerate(target["names"])}
    records = []
    for side in ["L", "R"]:
        thigh, shin, foot = [p+side for p in ["thigh", "shin", "foot"]]
        raw_a, raw_k, raw_e = [world[n][:3, 3] for n in [thigh, shin, foot]]
        origin = raw_a+pelvis
        vector = endpoints[side]-origin
        distance = float(np.linalg.norm(vector))
        direction = vector/distance
        a, b = [float(np.linalg.norm(target["local"][n][:3, 3])) for n in [shin, foot]]
        clamped = float(np.clip(distance, abs(a-b)+REACH_MARGIN_M, a+b-REACH_MARGIN_M))
        old_direction = raw_e-raw_a
        old_direction /= np.linalg.norm(old_direction)
        plane = raw_k-raw_a
        plane -= old_direction*np.dot(plane, old_direction)
        if np.linalg.norm(plane) < 1e-9:
            raise ValueError("Degenerate raw signed knee bend plane")
        plane /= np.linalg.norm(plane)
        plane = frozen.shortest_swing(old_direction, direction, plane) @ plane
        plane -= direction*np.dot(plane, direction)
        plane /= np.linalg.norm(plane)
        cosine = float(np.clip((a*a+clamped*clamped-b*b)/(2*a*clamped), -1, 1))
        knee = origin+direction*a*cosine+plane*a*math.sqrt(max(0., 1-cosine*cosine))
        endpoint = origin+direction*clamped
        up = frozen.shortest_swing(raw_k-raw_a, knee-origin, plane) @ world[thigh][:3, :3]
        low = frozen.shortest_swing(raw_e-raw_k, endpoint-knee, plane) @ world[shin][:3, :3]
        foot_basis = m.qmatrix(orientations[side])
        pose[indices[thigh]]["rotation"] = m.quat(world["hips"][:3, :3].T @ up).tolist()
        pose[indices[shin]]["rotation"] = m.quat(up.T @ low).tolist()
        pose[indices[foot]]["rotation"] = m.quat(low.T @ foot_basis).tolist()
        pose[indices["toe"+side]]["rotation"] = np.asarray(toe_rotations[side]).tolist()
        records.append({"side": side, "requested_ankle_distance_m": distance,
                        "minimum_reach_m": abs(a-b), "maximum_reach_m": a+b,
                        "reach_clamp_m": abs(distance-clamped), "signed_knee_plane": plane.tolist(),
                        "desired_ankle_m": endpoints[side].tolist(),
                        "raw_ankle_m": raw_e.tolist(), "desired_foot_world_rotation": orientations[side].tolist(),
                        "axial_twist_policy": "left-multiply raw global segment basis by shortest endpoint swing"})
    actual = frozen.fk(pose, target)
    for record in records:
        side = record["side"]
        origin = actual["thigh"+side][:3, 3]
        direction = actual["foot"+side][:3, 3]-origin
        direction /= np.linalg.norm(direction)
        plane = actual["shin"+side][:3, 3]-origin
        plane -= direction*np.dot(plane, direction)
        plane /= np.linalg.norm(plane)
        record["transported_signed_knee_plane_error_rad"] = math.acos(float(np.clip(np.dot(plane, record["signed_knee_plane"]), -1, 1)))
        record["ankle_endpoint_error_m"] = float(np.linalg.norm(actual["foot"+side][:3, 3]-record["desired_ankle_m"]))
        record["foot_world_rotation_error_rad"] = frozen.angle(m.quat(actual["foot"+side][:3, :3]), record["desired_foot_world_rotation"])
    return pose, actual, {"pelvis_adjustment_m": pelvis.tolist(), "requested_pelvis_adjustment_m": requested_pelvis.tolist(),
                           "pelvis_limit_clamp_m": max(0., float(np.linalg.norm(requested_pelvis))-PELVIS_LIMIT_M), "legs": records}


def qproduct(a, b):
    av, bv = np.array(a[:3]), np.array(b[:3])
    return np.r_[a[3]*bv+b[3]*av+np.cross(av, bv), a[3]*b[3]-np.dot(av, bv)]


def angular_vector(a, b):
    delta = qproduct(b, np.r_[-np.array(a[:3]), a[3]])
    if delta[3] < 0:
        delta = -delta
    length = np.linalg.norm(delta[:3])
    return delta[:3] * (2*math.atan2(length, delta[3])/length) if length > 1e-12 else np.zeros(3)


def stats(values):
    values = np.array(values, dtype=float)
    if len(values) == 0:
        return None
    return {"median": float(np.median(values)), "p95": float(np.percentile(values, 95)), "max": float(values.max())}


def quality(clip, target, direction, windows, fps):
    duration = clip["duration"]
    max_step, worst = 0., {}
    bone_speeds, bone_accel, ankle_speeds, ankle_accel = [], [], [], []
    feet = [{"side": side, "full_errors": [], "all_errors": [], "span": [], "full_speeds": [], "full_accel": [],
             "sole_min_y_m": math.inf, "full_selected_y": [], "full_other_y": []} for side in ["L", "R"]]
    count = 0
    for offset in [0., .25/fps, .5/fps, .75/fps]:
        times = np.arange(offset, 3*duration+offset, 1/fps)
        poses = [sample_frames(clip["frames"], duration, float(t)) for t in times]
        worlds = [frozen.fk(p, target) for p in poses]
        angular = np.array([[angular_vector(a["rotation"], b["rotation"])*fps for a, b in zip(poses[i-1], poses[i])] for i in range(1, len(poses))])
        bone_speeds.extend(np.linalg.norm(angular, axis=2).ravel())
        bone_accel.extend(np.linalg.norm(np.diff(angular, axis=0)*fps, axis=2).ravel())
        for i in range(1, len(poses)):
            for bone in range(9):
                value = frozen.angle(poses[i-1][bone]["rotation"], poses[i][bone]["rotation"])
                if value > max_step:
                    max_step, worst = value, {"time_s": float(times[i]), "bone": target["names"][bone], "phase_offset_s": offset,
                                             "crosses_cycle_wrap": bool(times[i] % duration < times[i-1] % duration)}
        count += len(times)
        translation = SPEED*times[:, None]*direction
        for side_index, side in enumerate(["L", "R"]):
            foot = feet[side_index]
            sole = np.array([m.foot_points(w["foot"+side]) for w in worlds])+translation[:, None, :]
            ankle = np.array([w["foot"+side][:3, 3] for w in worlds])+translation
            velocity = np.gradient(sole, times, axis=0)
            acceleration = np.gradient(velocity, times, axis=0)
            ankle_velocity = np.gradient(ankle, times, axis=0)
            ankle_speeds.extend(np.linalg.norm(ankle_velocity, axis=1))
            ankle_accel.extend(np.linalg.norm(np.gradient(ankle_velocity, times, axis=0), axis=1))
            previous_window, span_anchor = None, None
            for i, time in enumerate(times):
                phase = float(time % duration)
                window, _, cycle, weight = window_at(windows, side_index, phase, duration)
                if window and clip.get("contact_policy") == "anticipatory_roll":
                    weight = 1.
                foot["sole_min_y_m"] = min(foot["sole_min_y_m"], float(sole[i, :, 1].min()))
                if window is None:
                    previous_window = None
                    continue
                total_cycle = math.floor(time/duration)+cycle
                key = (window["window_id"], total_cycle)
                point = window["sole_point"]
                if key != previous_window:
                    span_anchor = sole[i, point].copy()
                previous_window = key
                anchor = np.array(window["anchor_world_at_start_m"])+SPEED*duration*total_cycle*direction
                if duration <= time < 2*duration:
                    error = float(np.linalg.norm(sole[i, point]-anchor))
                    foot["all_errors"].append(error)
                    foot["span"].append(float(np.linalg.norm(sole[i, point]-span_anchor)))
                    if weight >= .999:
                        foot["full_errors"].append(error)
                        foot["full_speeds"].append(float(np.linalg.norm(velocity[i, point])))
                        foot["full_accel"].append(float(np.linalg.norm(acceleration[i, point])))
                        foot["full_selected_y"].append(float(sole[i, point, 1]))
                        foot["full_other_y"].append(float(sole[i, 1-point, 1]))
    result_feet = []
    for foot in feet:
        result_feet.append({"side": foot["side"], "full_contact_samples": len(foot["full_errors"]),
                           "maximum_contact_span_sole_displacement_m": max(foot["span"], default=None),
                           "maximum_all_inferred_contact_anchor_error_m": max(foot["all_errors"], default=None),
                           "maximum_full_contact_anchor_error_m": max(foot["full_errors"], default=None),
                           "full_contact_world_sole_speed_mps": stats(foot["full_speeds"]),
                           "full_contact_world_sole_acceleration_mps2": stats(foot["full_accel"]),
                           "sole_min_y_m": foot["sole_min_y_m"],
                           "minimum_selected_point_y_during_full_contact_m": min(foot["full_selected_y"], default=None),
                           "minimum_other_point_y_during_full_contact_m": min(foot["full_other_y"], default=None),
                           "maximum_proxy_ground_penetration_m": max(0., -foot["sole_min_y_m"])})
    return {"fps": fps, "sample_count": count, "cycles_per_phase_offset": 3,
            "phase_offsets_s": [0., .25/fps, .5/fps, .75/fps], "period_s": duration,
            "synthetic_actor_speed_mps": SPEED, "synthetic_actor_direction": direction.tolist(),
            "maximum_local_rotation_step_rad": max_step, "worst_local_rotation_step": worst,
            "local_bone_angular_speed_radps": stats(bone_speeds), "local_bone_angular_acceleration_radps2": stats(bone_accel),
            "ankle_world_speed_mps": stats(ankle_speeds), "ankle_world_acceleration_mps2": stats(ankle_accel), "feet": result_feet}


def contract(clip, target):
    max_length_error, max_nonhips_position_error, max_norm_error = 0., 0., 0.
    finite = True
    for frame in clip["frames"]:
        pose, world = frame["lower"], frozen.fk(frame["lower"], target)
        for name, bone in zip(target["names"], pose):
            finite &= bool(np.isfinite(bone["position"]+bone["rotation"]+bone["scale"]).all())
            max_norm_error = max(max_norm_error, abs(float(np.linalg.norm(bone["rotation"]))-1))
            if bone["scale"] != [1, 1, 1]:
                raise ValueError("Bone scale changed")
            if name != "hips":
                max_nonhips_position_error = max(max_nonhips_position_error, float(np.linalg.norm(np.array(bone["position"])-target["local"][name][:3, 3])))
        for side in ["L", "R"]:
            for parent, child in [("thigh", "shin"), ("shin", "foot"), ("foot", "toe")]:
                length = np.linalg.norm(world[child+side][:3, 3]-world[parent+side][:3, 3])
                max_length_error = max(max_length_error, abs(float(length-np.linalg.norm(target["local"][child+side][:3, 3]))))
    return {"finite": finite, "max_quaternion_norm_error": max_norm_error,
            "maximum_nonhips_local_translation_error_m": max_nonhips_position_error,
            "maximum_fk_leg_segment_length_error_m": max_length_error, "joint_count": 87,
            "track_count": 10, "writes_hips": True, "root_tracks": [], "upper_tracks": [],
            "runtime_upper_boundary_compensation_required": True}


def main():
    watched = [frozen.ARCHIVE, frozen.TARGET, INPUT, ROOT/"tools/mixamo_retarget.py",
               ROOT/"tools/mixamo_contact_correct.py", ROOT/"tools/mixamo_loop_retarget.py",
               ROOT/"tools/motorica_retarget.py", ROOT/"tools/freeze_mixamo_loops.py",
               ROOT/"assets/animation/locomotion.features.bin", ROOT/"assets/animation/locomotion.poses.bin",
               ROOT/"data/motion_matching.json", ROOT/"data/config.json", ROOT/"data/player_controller.json",
               ROOT/"scripts/animation/ink_motion_matcher.gd"]
    for folder in [ROOT/"assets/animation/experiments/mixamo", ROOT/"assets/animation/experiments/motorica",
                   ROOT/"assets/animation/experiments/mixamo_loops", ROOT/".tools/mixamo-loop-prototype"]:
        watched.extend(p for p in folder.rglob("*") if p.is_file())
    watched = sorted(set(watched))
    before = {str(p): provenance(p) for p in watched}
    source_data = json.loads(INPUT.read_text(encoding="utf-8"))
    if before[str(frozen.ARCHIVE)]["sha256"] != frozen.ARCHIVE_SHA or before[str(frozen.TARGET)]["sha256"] != frozen.TARGET_SHA:
        raise ValueError("Frozen archive or target rig hash mismatch")
    target = m.target_rig()
    clips, reports, original_references = [], [], []
    for source_name in SOURCES:
        original = next(c for c in source_data["clips"] if c["source_file"] == source_name and c["spatial_mode"] == "source9_baseline" and c["time_mode"] == "leg_reference_retime6")
        source = next(s for s in source_data["source_evidence"] if s["file"] == source_name)
        duration = original["duration"]
        original_intervals = len(original["frames"])-1
        n = math.ceil(duration*BAKE_HZ/original_intervals)*original_intervals
        times = np.arange(n)*duration/n
        direction = np.array(source["source_net_hips_planar_delta_m"])
        direction /= np.linalg.norm(direction)
        raw_poses = [sample_frames(original["frames"], duration, float(t)) for t in times]
        raw_world = [frozen.fk(p, target) for p in raw_poses]
        windows = contact_windows({"target": target}, original, raw_world)
        original_seam = {"local_rotation_max_rad": max(frozen.angle(a["rotation"], b["rotation"]) for a, b in zip(original["frames"][0]["lower"], original["frames"][-1]["lower"])),
                         "local_position_max_m": max(float(np.linalg.norm(np.array(a["position"])-b["position"])) for a, b in zip(original["frames"][0]["lower"], original["frames"][-1]["lower"]))}
        unfiltered_geometry = make_geometry(raw_poses, raw_world, duration, 0.)
        original_anchors = prepare_anchors(windows, unfiltered_geometry[0], unfiltered_geometry[1], duration, direction)
        original_references.append({"id": original["id"], "source_file": source_name,
                                    "method": "Direct frozen original key interpolation; no dense export, IK, smoothing or contact correction",
                                    "endpoint_seam": original_seam,
                                    "quality_at6": [quality(original, target, direction, original_anchors, fps) for fps in FPS]})
        for variant, sigma, contact in VARIANTS:
            endpoints, rotations, toes, filters = make_geometry(raw_poses, raw_world, duration, sigma)
            anchors = prepare_anchors(windows, endpoints, rotations, duration, direction)
            frames, diagnostics = [], []
            for i, time in enumerate(times):
                raw, world = raw_poses[i], raw_world[i]
                desired, foot_q, toe_q = {}, {}, {}
                weights, candidates, window_ids, points, frame_anchors = [], [], [], [], []
                for side_index, side in enumerate(["L", "R"]):
                    desired[side] = endpoints[side][i].copy()
                    foot_q[side] = rotations[side][i].copy()
                    toe_q[side] = toes[side][i].copy()
                    source_window, _, _, _ = window_at(anchors, side_index, float(time), duration)
                    window, _, cycle, weight = anticipatory_window_at(anchors, side_index, float(time), duration) if contact == "anticipatory_roll" else window_at(anchors, side_index, float(time), duration)
                    candidates.append(source_window is not None)
                    weights.append(weight)
                    window_ids.append(window["window_id"] if window else -1)
                    points.append(window["sole_point"] if window else 0)
                    anchor = np.array(window["anchor_world_at_start_m"])+SPEED*duration*cycle*direction if window else np.zeros(3)
                    frame_anchors.append(anchor.tolist())
                    if contact and window:
                        if contact != "anticipatory_roll":
                            foot_q[side] = frozen.slerp(foot_q[side], window["anchor_foot_world_rotation"], weight)
                        local_ankle = anchor-SPEED*time*direction-m.qmatrix(foot_q[side])@SOLE[window["sole_point"]]
                        desired[side] = desired[side]*(1-weight)+local_ankle*weight
                if variant == "raw_dense":
                    pose, actual, diagnostic = pose_copy(raw), world, {"pelvis_adjustment_m": [0., 0., 0.], "requested_pelvis_adjustment_m": [0., 0., 0.], "pelvis_limit_clamp_m": 0., "legs": []}
                else:
                    pose, actual, diagnostic = solve_pose(raw, target, desired, foot_q, toe_q)
                diagnostic["maximum_ankle_path_change_from_raw_m"] = max(float(np.linalg.norm(actual["foot"+s][:3, 3]-world["foot"+s][:3, 3])) for s in ["L", "R"])
                diagnostic["maximum_sole_path_change_from_raw_m"] = max(float(np.linalg.norm(m.foot_points(actual["foot"+s])-m.foot_points(world["foot"+s]), axis=1).max()) for s in ["L", "R"])
                diagnostic["maximum_foot_world_rotation_change_from_raw_rad"] = max(frozen.angle(m.quat(actual["foot"+s][:3, :3]), m.quat(world["foot"+s][:3, :3])) for s in ["L", "R"])
                frame = {"time": float(time), "source_time": float(time*original["playback_rate_from_original"]),
                         "lower": [{k: m.round_list(v) for k, v in p.items()} for p in pose],
                         "source_contact_candidate": candidates, "contact_weight": weights,
                         "contact_window_id": window_ids, "sole_point": points, "sole_anchor_world_m": frame_anchors,
                         "synthetic_root_translation_m": (SPEED*time*direction).tolist(), "diagnostics": diagnostic}
                frames.append(frame)
                diagnostics.append(diagnostic)
            # The Gaussian curves are periodic. Raw original Hips is retained;
            # closing only its tiny source seam is explicit and measured below.
            last = json.loads(json.dumps(frames[0]))
            last["time"], last["source_time"] = duration, original["source_duration"]
            last["synthetic_root_translation_m"] = (SPEED*duration*direction).tolist()
            last["sole_anchor_world_m"] = [(np.array(a)+SPEED*duration*direction).tolist() if last["source_contact_candidate"][j] else a for j, a in enumerate(last["sole_anchor_world_m"])]
            if variant == "raw_dense":
                last["lower"] = pose_copy(original["frames"][-1]["lower"])
            frames.append(last)
            id = "mixamo_loop_refined_"+Path(source_name).stem.replace(" ", "_")+"_"+variant
            clip = {"id": id, "source_file": source_name, "variant": variant, "loop": True,
                    "duration": duration, "source_duration": original["source_duration"],
                    "playback_rate_from_original": original["playback_rate_from_original"],
                    "writes_hips": True, "root_tracks": [], "upper_tracks": [],
                    "source_trajectory_is_metadata_only": True, "world_foot_lock_applied": bool(contact),
                    "contact_policy": "anticipatory_roll" if contact == "anticipatory_roll" else "inside_window_frozen_foot" if contact else "none",
                    "bake_sample_rate_hz": n/duration, "bake_sample_count": len(frames),
                    "filter_policy": filters, "pelvis_maximum_adjustment_m": PELVIS_LIMIT_M,
                    "contact_acquisition_release_s": ANTICIPATORY_RAMP_S if contact == "anticipatory_roll" else CONTACT_RAMP_S,
                    "windows": anchors, "frames": frames}
            structural = contract(clip, target)
            if not structural["finite"] or structural["max_quaternion_norm_error"] > 1e-8 or structural["maximum_nonhips_local_translation_error_m"] > 1e-9 or structural["maximum_fk_leg_segment_length_error_m"] > 1e-8:
                raise ValueError("Refined structural invariant failed")
            qualities = [quality(clip, target, direction, anchors, fps) for fps in FPS]
            issues = []
            for q in qualities:
                if q["fps"] in ROT_LIMIT and q["maximum_local_rotation_step_rad"] > ROT_LIMIT[q["fps"]]:
                    issues.append(f'{q["fps"]} Hz local rotation step exceeds unchanged {ROT_LIMIT[q["fps"]]} rad limit')
                for foot in q["feet"]:
                    error = foot["maximum_contact_span_sole_displacement_m"]
                    if error is None or error > SLIDE_LIMIT:
                        issues.append(f'{q["fps"]} Hz {foot["side"]}: inferred-contact span displacement exceeds unchanged .03 m limit or no evidence')
                    if contact and (foot["maximum_full_contact_anchor_error_m"] is None or foot["maximum_full_contact_anchor_error_m"] > SLIDE_LIMIT):
                        issues.append(f'{q["fps"]} Hz {foot["side"]}: full-weight anchor error exceeds unchanged .03 m limit or no evidence')
                    if foot["sole_min_y_m"] < 0:
                        issues.append(f'{q["fps"]} Hz {foot["side"]}: one or both heel/ball proxies pass below explicit offline floor Y=0; locked-point error alone does not prove whole-foot ground clearance')
            legs = [r for d in diagnostics for r in d["legs"]]
            if max((r["reach_clamp_m"] for r in legs), default=0.) > 1e-5:
                issues.append("One or more requested ankle targets are unreachable within unchanged 1e-5 m endpoint diagnostic tolerance")
            if max(d["pelvis_limit_clamp_m"] for d in diagnostics) > 0:
                issues.append("Requested internal pelvis displacement exceeds declared .04 m synthesis bound")
            record = {"id": id, "source_file": source_name, "variant": variant, "period_s": duration,
                      "resource_contract": structural, "frozen_original_endpoint_seam": original_seam,
                      "refined_endpoint_seam": {"local_rotation_max_rad": max(frozen.angle(a["rotation"], b["rotation"]) for a, b in zip(frames[0]["lower"], frames[-1]["lower"])),
                                               "local_position_max_m": max(float(np.linalg.norm(np.array(a["position"])-b["position"])) for a, b in zip(frames[0]["lower"], frames[-1]["lower"]))},
                      "filter_policy": filters, "quality_at6": qualities,
                      "maximum_reach_clamp_m": max((r["reach_clamp_m"] for r in legs), default=0.),
                      "maximum_pelvis_adjustment_m": max(float(np.linalg.norm(d["pelvis_adjustment_m"])) for d in diagnostics),
                      "maximum_pelvis_limit_clamp_m": max(d["pelvis_limit_clamp_m"] for d in diagnostics),
                      "maximum_signed_knee_plane_error_rad": max((r["transported_signed_knee_plane_error_rad"] for r in legs), default=0.),
                      "maximum_ankle_path_change_from_raw_m": max(d["maximum_ankle_path_change_from_raw_m"] for d in diagnostics),
                      "maximum_sole_path_change_from_raw_m": max(d["maximum_sole_path_change_from_raw_m"] for d in diagnostics),
                      "maximum_foot_world_rotation_change_from_raw_rad": max(d["maximum_foot_world_rotation_change_from_raw_rad"] for d in diagnostics),
                      "maximum_proxy_ground_penetration_m": max(f["maximum_proxy_ground_penetration_m"] for q in qualities for f in q["feet"]),
                      "quality_issues": issues, "production_accepted": False}
            original_key_differences = []
            for original_frame in original["frames"]:
                sampled = sample_frames(frames, duration, original_frame["time"], preserve_end=True)
                reference = original_frame["lower"]
                sample_world, reference_world = frozen.fk(sampled, target), frozen.fk(reference, target)
                original_key_differences.append({"time_s": original_frame["time"],
                                                 "maximum_lower_local_rotation_difference_rad": max(frozen.angle(a["rotation"], b["rotation"]) for a, b in zip(sampled, reference)),
                                                 "maximum_sole_path_difference_m": max(float(np.linalg.norm(m.foot_points(sample_world["foot"+s])-m.foot_points(reference_world["foot"+s]), axis=1).max()) for s in ["L", "R"])})
            record["original_key_comparison"] = original_key_differences
            record["maximum_original_key_local_rotation_difference_rad"] = max(r["maximum_lower_local_rotation_difference_rad"] for r in original_key_differences)
            record["maximum_original_key_sole_path_difference_m"] = max(r["maximum_sole_path_difference_m"] for r in original_key_differences)
            text = frozen.animation_text(clip, target["names"])
            if text.count('/type =') != 10:
                raise ValueError("Unexpected serialized track count")
            write(OUTPUT/(id+".tres"), text)
            clips.append(clip)
            reports.append(record)
    after = {str(p): provenance(p) for p in watched}
    changed = [p for p in before if before[p] != after[p]]
    if changed:
        raise ValueError("Read-only input changed during refinement: "+", ".join(changed))
    write(CACHE/".gdignore", "\n")
    output_data = {"version": 1, "experimental": True, "default_enabled": False, "production_accepted": False,
                   "names": source_data["names"], "target_indices": source_data["target_indices"],
                   "target_parents": source_data["target_parents"], "target_rest": source_data["target_rest"],
                   "original_target_rig_joints": 87, "archive_sha256": frozen.ARCHIVE_SHA,
                   "target_body_sha256": frozen.TARGET_SHA, "source_evidence": source_data["source_evidence"], "clips": clips}
    write(OUTPUT/"loops.json", dump(output_data))
    report = {"version": 1, "experimental": True, "default_enabled": False, "production_accepted": False,
              "engine_invoked": False, "actual_avatar_input_acceptance": False, "production_database_changed": False,
              "dry_kid_speed_mps": SPEED, "bake_minimum_hz": BAKE_HZ,
              "diagnostic_quality_limits": {"contact_span_sole_displacement_m": SLIDE_LIMIT, "local_rotation_60hz_rad": .35, "local_rotation_30hz_rad": .7},
              "contact_evidence_thresholds": {"source_toe_height_above_clip_floor_m": .03, "source_toe_world_xz_speed_mps": .25},
              "sole_proxy_contract": {"parent_bones": ["footL", "footR"], "heel_local_m": SOLE[0].tolist(), "ball_local_m": SOLE[1].tolist(),
                                      "point_indices": {"0": "heel", "1": "ball"}, "toe_bones_are_not_proxy_parents": True},
              "anchor_sampling": "One sample of unconstrained candidate curve at inferred-window start. Raw original pose chooses lower heel/ball at this start; selected point is shared by variants. Candidate foot-world rotation and ankle position interpolate at the same start. Add 6*start*normalized source travel to its XZ; explicit y=0 ground calibration. Each repeated window uses only the same anchor plus 6*cycle*period*direction, never frame-by-frame re-anchoring.",
              "ground_quality": "Every candidate measures BOTH heel/ball proxy Y, including the unlocked point during full-weight contact. Any below-Y=0 observation is reported as an offline proxy ground-clearance failure. Submillimetre locked-point anchor error cannot certify whole-foot ground clearance. This is mathematical-proxy evidence; actual shoe mesh, terrain and imported-Skeleton validation remain required.",
              "actor_root_displacement": "Exactly linear synthetic metadata 6*time_s*normalized source Hips planar delta. Running is approximately +Z, left strafe approximately +X, right approximately -X. Source direction signs are preserved rather than inferred from filenames. No exported root track or gameplay actor movement write.",
              "uniform_bake_policy": "Choose ceil(period*240/source_intervals)*source_intervals unique intervals, then exact endpoint. Every original source key lies on the uniform grid; actual bake rate is at least 240 Hz. Fixed cycle duration never increases.",
              "method": "Read frozen source9 retimed loops; circular target ankle/world-foot/toe-local Gaussian curve filtering; unchanged cyclic periods and Hips yaw; bounded internal pelvis displacement; transported signed raw knee plane and shortest-swing segment basis retain axial twist; periodic world anchor translation follows explicit six-metre/second Actor proxy.",
              "variant_declarations": [{"variant": v, "gaussian_sigma_s": s, "contact_policy": "anticipatory_roll" if c == "anticipatory_roll" else "inside_window_frozen_foot" if c else "none"} for v, s, c in VARIANTS],
              "development_history": [{"revision": "v1", "outcome": "Generated 15 resources but report serialization failed on numpy bool; no readonly input writes; explicit bool conversion repaired it"},
                                      {"revision": "v2", "outcome": "15 declared resources generated, 0 structural failures, all 15 quality-failing; retained unchanged in final resource set"},
                                      {"revision": "v3", "outcome": "Added six anticipated-acquisition natural-roll comparisons; all 21 have quality failures, no accepted production candidate"},
                                      {"revision": "v4", "outcome": "Metadata and reach/pelvis failures explicitly recorded. Archived full 21 resource set, loop JSON and report under unaligned-v4 before uniform original-key aligned rebake"},
                                      {"revision": "v5", "outcome": "Uniform grid interval count rounded to original interval multiple, preserving exact original key locations; every variant and all failed constraints retained"},
                                      {"revision": "v6", "outcome": "Reporting-only addition: both heel/ball ground penetration, including unlocked point during full contact, explicitly measured and quality-failing. No new curve variants or curve changes"}],
              "limitations": "Source contacts are nearest-key inferred labels, not authored contacts. Heel/ball points are runtime mathematical proxies, not shoe-mesh contacts. Gaussian averaging changes motion amplitude; all errors and failed variants are reported. Raw Hips remains piecewise source interpolation except explicit tiny endpoint closure in synthesized variants. No new actual input, runtime transition, terrain, aim, GPU footage, packaged build or feel acceptance.",
              "unconstrained_frozen_original_references": original_references,
              "candidate_reports": reports, "structural_contract_failures": 0,
              "quality_failing_candidate_count": sum(bool(r["quality_issues"]) for r in reports),
              "read_only_inputs_unchanged": True, "inputs_before": list(before.values()), "inputs_after": list(after.values())}
    write(CACHE/"report.json", dump(report))
    manifest = {"generator": provenance(Path(__file__)), "inputs_before": list(before.values()), "inputs_after": list(after.values()),
                "read_only_inputs_unchanged": True, "outputs": [provenance(p) for p in sorted(OUTPUT.glob("*")) if p.is_file() and p.name != "provenance.json"],
                "report": provenance(CACHE/"report.json"), "resource_count": len(clips), "production_accepted": False}
    write(OUTPUT/"provenance.json", dump(manifest))
    print(dump({"resources": len(clips), "structural_failures": 0, "quality_failing_candidates": report["quality_failing_candidate_count"], "read_only_inputs_unchanged": True, "production_accepted": False, "report": str(CACHE/"report.json")}).strip())


if __name__ == "__main__":
    main()
