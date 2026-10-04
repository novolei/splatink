"""Experimental Mixamo traveling loops on the original Splatink 87-joint rig.

Reads the original ZIP directly. Imports only frozen parser/math definitions;
never invokes its main, contact corrector, Godot, Blender, or SSH. Writes only
new mixamo_loops resources and .tools/mixamo-loop-prototype diagnostics.
This offline FK/translation proxy is not actual Avatar/input acceptance.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import struct
import zipfile
import numpy as np
import mixamo_retarget as m  # Definitions only; neither main nor correct is used.

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE = Path(r"E:\backup\Locomotion Pack.zip")
ARCHIVE_SHA = "e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86"
TARGET = ROOT / "assets/characters/body.glb"
TARGET_SHA = "ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3"
OUTPUT = ROOT / "assets/animation/experiments/mixamo_loops"
CACHE = ROOT / ".tools/mixamo-loop-prototype"
FILES = ["running.fbx", "left strafe.fbx", "right strafe.fbx"]
SPATIAL_MODES = ["source9_baseline", "fixed8_uncorrected", "fixed8_endpoint_reprojected"]
TIME_MODES = ["original_time", "leg_reference_retime6"]
DRY_KID_SPEED = 6.0
CONTACT_HEIGHT = .03
CONTACT_SPEED = .25
SLIDE_THRESHOLD = .03
ROTATION_60HZ_THRESHOLD = .35


def provenance(path):
    stat = path.stat()
    return {"path": str(path), "size_bytes": stat.st_size, "mtime_ns": stat.st_mtime_ns,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def write(path, value):
    allowed = (OUTPUT.resolve(), CACHE.resolve())
    resolved = path.resolve()
    if not any(resolved.is_relative_to(parent) for parent in allowed):
        raise ValueError("Output escaped the two experimental directories")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError("Refusing symlink output")
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(value, encoding="utf-8", newline="\n")
    temporary.replace(path)


def json_text(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n"


def angle(a, b):
    a, b = np.asarray(a), np.asarray(b)
    dot = abs(float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))))
    return 2 * math.acos(float(np.clip(dot, -1, 1)))


def fk(pose, target):
    world = {}
    for name, value in zip(target["names"], pose):
        local = m.transform(value["position"], m.qmatrix(value["rotation"]))
        parent = target["parents"][name]
        world[name] = world[parent] @ local if parent in world else local
    return world


def pose_value(position, rotation):
    return {"position": m.round_list(position), "rotation": m.round_list(m.quat(rotation)),
            "scale": [1, 1, 1]}


def shortest_swing(before, after, antiparallel_axis):
    """Left-multiply the existing basis; do not rebuild or discard axial twist."""
    a = np.asarray(before) / np.linalg.norm(before)
    b = np.asarray(after) / np.linalg.norm(after)
    cross = np.cross(a, b)
    cosine = float(np.clip(np.dot(a, b), -1, 1))
    if cosine > 1 - 1e-13:
        return np.eye(3)
    if cosine < -1 + 1e-10:
        axis = np.asarray(antiparallel_axis) - a * np.dot(antiparallel_axis, a)
        if np.linalg.norm(axis) < 1e-9:
            axis = np.eye(3)[int(np.argmin(np.abs(a)))]
            axis -= a * np.dot(axis, a)
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    x, y, z = cross
    skew = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) + skew + (skew @ skew) / (1 + cosine)


def reproject_fixed_hips(raw_pose, target):
    """Attempt the original target ankle path with fixed Hips, without foot locks.

    Transport the raw signed knee plane by shortest endpoint swing. Solve the
    original two fixed-length segments; independently swing each raw segment
    basis to its solved endpoint, retaining its existing axial twist. Foot world
    rotation is retained. Clamp unreachable ankle targets and report the error.
    """
    raw_world = fk(raw_pose, target)
    pose = json.loads(json.dumps(raw_pose))
    pose[0] = pose_value(target["local"]["hips"][:3, 3], m.rotation(target["local"]["hips"]))
    fixed_world = fk(pose, target)
    indices = {name: i for i, name in enumerate(target["names"])}
    records = []
    for side in ["L", "R"]:
        thigh, shin, foot = [part + side for part in ["thigh", "shin", "foot"]]
        raw_a, raw_k, raw_e = [raw_world[name][:3, 3] for name in [thigh, shin, foot]]
        origin = fixed_world[thigh][:3, 3]
        vector = raw_e - origin
        distance = float(np.linalg.norm(vector))
        if distance < 1e-10:
            raise ValueError("Undefined reprojected endpoint direction")
        direction = vector / distance
        a = float(np.linalg.norm(target["local"][shin][:3, 3]))
        b = float(np.linalg.norm(target["local"][foot][:3, 3]))
        low, high = abs(a - b) + 1e-8, a + b - 1e-8
        clamped_distance = float(np.clip(distance, low, high))
        old_direction = raw_e - raw_a
        old_direction /= np.linalg.norm(old_direction)
        old_plane = raw_k - raw_a
        old_plane -= old_direction * np.dot(old_plane, old_direction)
        if np.linalg.norm(old_plane) < 1e-9:
            raise ValueError("Source target knee plane is degenerate")
        old_plane /= np.linalg.norm(old_plane)
        transport = shortest_swing(old_direction, direction, old_plane)
        plane = transport @ old_plane
        plane -= direction * np.dot(plane, direction)
        plane /= np.linalg.norm(plane)
        cosine = float(np.clip((a*a + clamped_distance**2 - b*b) / (2*a*clamped_distance), -1, 1))
        knee = origin + direction * a * cosine + plane * a * math.sqrt(max(0, 1-cosine*cosine))
        endpoint = origin + direction * clamped_distance
        up_swing = shortest_swing(raw_k-raw_a, knee-origin, plane)
        shin_swing = shortest_swing(raw_e-raw_k, endpoint-knee, plane)
        up_rotation = up_swing @ raw_world[thigh][:3, :3]
        shin_rotation = shin_swing @ raw_world[shin][:3, :3]
        foot_rotation = raw_world[foot][:3, :3]
        parent_rotation = fixed_world["hips"][:3, :3]
        pose[indices[thigh]]["rotation"] = m.round_list(m.quat(parent_rotation.T @ up_rotation))
        pose[indices[shin]]["rotation"] = m.round_list(m.quat(up_rotation.T @ shin_rotation))
        pose[indices[foot]]["rotation"] = m.round_list(m.quat(shin_rotation.T @ foot_rotation))
        actual = fk(pose, target)
        actual_knee = actual[shin][:3, 3] - origin
        signed = actual_knee - direction * np.dot(actual_knee, direction)
        signed /= np.linalg.norm(signed)
        plane_error = math.acos(float(np.clip(np.dot(signed, plane), -1, 1)))
        records.append({"side": side, "requested_ankle_distance_m": distance,
                        "minimum_reach_m": abs(a-b), "maximum_reach_m": a+b,
                        "reach_clamp_m": abs(distance-clamped_distance),
                        "ankle_endpoint_error_m": float(np.linalg.norm(actual[foot][:3, 3]-raw_e)),
                        "transported_signed_knee_plane_error_rad": plane_error,
                        "foot_world_rotation_error_rad": angle(m.quat(actual[foot][:3, :3]), m.quat(foot_rotation)),
                        "axial_twist_policy": "left-multiply original global segment basis by shortest endpoint swing"})
    return pose, records


def source_contacts(src):
    result, masks = [], {}
    times = src["times"]
    for side, full in [("L", "Left"), ("R", "Right")]:
        points = np.array([[frame["mixamorig:"+full+part][:3, 3]
                            for part in ["ToeBase", "Toe_End"]] for frame in src["frames"]])
        speed = np.linalg.norm(np.gradient(points[:, :, [0, 2]], times, axis=0), axis=2)
        floor = float(points[:, :, 1].min())
        candidate_points = (points[:, :, 1] <= floor + CONTACT_HEIGHT) & (speed <= CONTACT_SPEED)
        masks[side] = candidate_points.any(axis=1)
        result.append({"side": side, "floor_m": floor, "candidate_indices": np.flatnonzero(masks[side]).tolist(),
                       "samples": int(masks[side].sum()), "point_names": [full+"ToeBase", full+"Toe_End"],
                       "world_positions_m": m.round_list(points), "world_xz_speed_mps": m.round_list(speed),
                       "point_candidate_mask": candidate_points.tolist()})
    return result, masks


def baseline(src, target):
    times = src["times"]
    hips = np.array([world["mixamorig:Hips"][:3, 3] for world in src["frames"]])
    planar_delta = hips[-1] - hips[0]
    planar_delta[1] = 0
    planar_velocity = planar_delta / times[-1]
    ratios = []
    for side in ["L", "R"]:
        source = [src["rest"]["mixamorig:"+m.MAP[part+side]][:3, 3] for part in ["thigh", "shin", "foot"]]
        source_length = sum(np.linalg.norm(source[i+1]-source[i]) for i in range(2))
        target_length = sum(np.linalg.norm(target["local"][part+side][:3, 3]) for part in ["shin", "foot"])
        ratios.append(float(target_length/source_length))
    scale = float(np.mean(ratios))
    frames = []
    previous = {}
    for i, original in enumerate(src["frames"]):
        global_rotation, pose = {}, []
        for name in target["names"]:
            source_name = "mixamorig:" + m.MAP[name]
            r = m.rotation(original[source_name]) @ m.rotation(src["rest"][source_name]).T @ m.rotation(target["world"][name])
            global_rotation[name] = r
            parent = target["parents"][name]
            local_r = global_rotation[parent].T @ r if parent in global_rotation else r
            p = target["local"][name][:3, 3].copy()
            if name == "hips":
                p += scale * (hips[i]-src["rest"]["mixamorig:Hips"][:3, 3]-planar_velocity*times[i])
            value = pose_value(p, local_r)
            q = np.array(value["rotation"])
            if name in previous and np.dot(q, previous[name]) < 0:
                value["rotation"] = m.round_list(-q)
            previous[name] = np.array(value["rotation"])
            pose.append(value)
        frames.append({"source_time": float(times[i]), "lower": pose})
    return frames, hips, planar_delta, ratios, scale


def slerp(a, b, weight):
    a, b = np.array(a), np.array(b)
    a /= np.linalg.norm(a)
    b /= np.linalg.norm(b)
    dot = float(np.dot(a, b))
    if dot < 0:
        dot, b = -dot, -b
    if dot > .9995:
        out = a*(1-weight) + b*weight
        return out/np.linalg.norm(out)
    theta = math.acos(float(np.clip(dot, -1, 1)))
    return (math.sin((1-weight)*theta)*a + math.sin(weight*theta)*b) / math.sin(theta)


def sample_pose(frames, original_duration, source_time):
    position = source_time / original_duration * (len(frames)-1)
    index = min(int(math.floor(position)), len(frames)-2)
    weight = position-index
    pose = []
    for a, b in zip(frames[index]["lower"], frames[index+1]["lower"]):
        pose.append({"position": (np.array(a["position"])*(1-weight) + np.array(b["position"])*weight).tolist(),
                     "rotation": slerp(a["rotation"], b["rotation"], weight).tolist(), "scale": [1, 1, 1]})
    return pose


def all_target_world():
    raw = TARGET.read_bytes()
    count = struct.unpack_from("<I", raw, 12)[0]
    gltf = json.loads(raw[20:20+count])
    nodes = gltf["nodes"]
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}
    world = {}
    def get(i):
        if i in world:
            return world[i]
        node = nodes[i]
        local = m.transform(node.get("translation", [0, 0, 0]),
                            m.qmatrix(node.get("rotation", [0, 0, 0, 1])) @ np.diag(node.get("scale", [1, 1, 1])))
        world[i] = get(parents[i]) @ local if i in parents else local
        return world[i]
    return {nodes[i]["name"]: get(i) for i in gltf["skins"][0]["joints"]}


def summary(values):
    if not len(values):
        return None
    return {"median": float(np.median(values)), "p95": float(np.percentile(values, 95)), "max": float(np.max(values))}


def temporal_quality(frames, target, upper_rest, masks, original_duration, speed, direction, rate, fps, writes_hips):
    duration = original_duration/rate
    # Three cycles expose wrap contacts; measure rotation everywhere and contacts
    # in the middle cycle to avoid manufactured startup/ending gradient evidence.
    times = np.arange(0, 3*duration + 1e-10, 1/fps)
    phase = np.mod(times, duration) * rate
    poses = [sample_pose(frames, original_duration, float(t)) for t in phase]
    worlds = [fk(pose, target) for pose in poses]
    step, worst = 0., {}
    begin_bone = 0 if writes_hips else 1
    for i in range(1, len(poses)):
        for bone in range(begin_bone, len(target["names"])):
            value = angle(poses[i-1][bone]["rotation"], poses[i][bone]["rotation"])
            if value > step:
                step, worst = value, {"time_s": float(times[i]), "bone": target["names"][bone],
                                     "crosses_cycle_wrap": bool(phase[i] < phase[i-1])}
    mid = (times >= duration) & (times < 2*duration)
    foot_results = []
    nearest = np.rint(phase/original_duration*(len(frames)-1)).astype(int)
    translation = speed * times[:, None] * direction[None, :]
    for side in ["L", "R"]:
        sole = np.array([m.foot_points(w["foot"+side]) for w in worlds])
        sole += translation[:, None, :]
        velocity = np.gradient(sole, times, axis=0)
        active = masks[side][nearest]
        point_indices = np.zeros(len(times), dtype=int)
        anchor_errors = np.zeros(len(times))
        anchor_xz_errors = np.zeros(len(times))
        anchor, point, previous = None, 0, False
        for i, on in enumerate(active):
            if on and not previous:
                point = int(sole[i, :, 1].argmin())
                anchor = sole[i, point].copy()
            point_indices[i] = point
            if on:
                displacement = sole[i, point]-anchor
                anchor_errors[i] = np.linalg.norm(displacement)
                anchor_xz_errors[i] = np.linalg.norm(displacement[[0, 2]])
            previous = bool(on)
        evidence = mid & active
        samples = np.flatnonzero(evidence)
        fixed_velocity = velocity[np.arange(len(times)), point_indices]
        foot_results.append({"side": side, "source_contact_resampled_samples": int(evidence.sum()),
                             "source_contact_resampling": "nearest original 30-Hz inferred source-key label; not newly authored contact",
                             "sole_world_speed_xz_mps": summary(np.linalg.norm(fixed_velocity[evidence][:, [0, 2]], axis=1)),
                             "sole_world_speed_3d_mps": summary(np.linalg.norm(fixed_velocity[evidence], axis=1)),
                             "maximum_contact_span_sole_displacement_m": float(anchor_errors[evidence].max()) if evidence.any() else None,
                             "maximum_contact_span_sole_xz_displacement_m": float(anchor_xz_errors[evidence].max()) if evidence.any() else None,
                             "sole_min_y_m": float(sole[mid, :, 1].min()),
                             "contact_samples": [{"time_s": float(times[i]), "source_phase_s": float(phase[i]),
                                                  "sole_point": int(point_indices[i]),
                                                  "world_speed_xz_mps": float(np.linalg.norm(fixed_velocity[i, [0, 2]])),
                                                  "span_displacement_m": float(anchor_errors[i])} for i in samples]})
    # Original upper joints are held at their original rest local transforms.
    # A nine-bone Hips track still moves those joints globally; expose this.
    upper_position, upper_rotation = 0., 0.
    hip_inverse = np.linalg.inv(target["world"]["hips"])
    upper_points = np.array([rest[:3, 3] for name, rest in upper_rest.items() if name not in target["names"]])
    for world in worlds:
        delta = world["hips"] @ hip_inverse
        displaced = upper_points @ delta[:3, :3].T + delta[:3, 3]
        upper_position = max(upper_position, float(np.linalg.norm(displaced-upper_points, axis=1).max()))
        upper_rotation = max(upper_rotation, angle(m.quat(m.rotation(delta)), [0, 0, 0, 1]))
    return {"fps": fps, "cycles": 3, "sample_count": len(times), "duration_s": duration,
            "playback_rate_from_original": rate, "synthetic_actor_translation_speed_mps": speed,
            "synthetic_actor_translation_direction": m.round_list(direction),
            "maximum_local_rotation_step_rad": step, "worst_local_rotation_step": worst,
            "maximum_held_upper_global_position_change_m": upper_position,
            "maximum_held_upper_global_rotation_change_rad": upper_rotation,
            "feet": foot_results}


def animation_text(clip, names):
    # Reuse the frozen writer's flat Godot 4.7 3-D key format, then set the
    # explicit cyclic policy. No production resource/library is touched.
    return m.animation_text(clip, names).replace("loop_mode = 0", "loop_mode = 1").replace("loop_wrap = false", "loop_wrap = true")


def main():
    if ROOT.resolve() != Path(r"H:\GDP\inkwave\splatink").resolve():
        raise ValueError("Unexpected workspace")
    watched = [ARCHIVE, TARGET, ROOT/"tools/mixamo_retarget.py", ROOT/"tools/mixamo_contact_correct.py",
               ROOT/"tools/motorica_retarget.py", ROOT/"data/motion_matching.json", ROOT/"data/config.json",
               ROOT/"data/player_controller.json", ROOT/"scripts/animation/ink_motion_matcher.gd",
               ROOT/"assets/animation/locomotion.features.bin", ROOT/"assets/animation/locomotion.poses.bin"]
    for folder in [ROOT/"assets/animation/experiments/mixamo", ROOT/"assets/animation/experiments/motorica"]:
        watched.extend(sorted(path for path in folder.rglob("*") if path.is_file()))
    before = {str(path): provenance(path) for path in watched}
    if before[str(ARCHIVE)]["sha256"] != ARCHIVE_SHA or before[str(TARGET)]["sha256"] != TARGET_SHA:
        raise ValueError("Original source or target hash mismatch")
    target = m.target_rig()
    upper_rest = all_target_world()
    if len(upper_rest) != 87:
        raise ValueError("Target 87-joint contract failed")
    write(CACHE/".gdignore", "\n")
    clips, reports, source_evidence, failures = [], [], [], []
    with zipfile.ZipFile(ARCHIVE) as archive:
        for name in FILES:
            member = PurePosixPath(name)
            if member.is_absolute() or ".." in member.parts or ":" in name:
                raise ValueError("Unsafe ZIP member")
            raw = archive.read(name)
            src = m.source_frames(raw)
            base, hips, planar_delta, ratios, scale = baseline(src, target)
            evidence, masks = source_contacts(src)
            original_duration = float(src["times"][-1])
            reference_speed = float(np.linalg.norm(planar_delta[[0, 2]]) / original_duration * scale)
            direction = planar_delta / np.linalg.norm(planar_delta)
            retime = DRY_KID_SPEED / reference_speed
            source_evidence.append({"file": name, "source_entry_sha256": hashlib.sha256(raw).hexdigest(),
                                    "source_entry_size_bytes": len(raw), "source_bones": len(src["names"]),
                                    "source_unit_to_m": src["unit"], "source_parent": src["parents"]["mixamorig:Hips"],
                                    "separate_root_exists": "Root" in src["names"], "duration_s": original_duration,
                                    "source_times_s": src["times"].tolist(), "source_hips_position_m": m.round_list(hips),
                                    "source_net_hips_planar_delta_m": m.round_list(planar_delta),
                                    "source_net_planar_trajectory_m": m.round_list(np.outer(src["times"]/original_duration, planar_delta)),
                                    "target_leg_ratios": ratios, "mean_target_leg_ratio": scale,
                                    "leg_scaled_reference_speed_mps": reference_speed,
                                    "retime_factor_for6": retime, "retimed_duration_s": original_duration/retime,
                                    "source_contact_evidence": evidence})
            variants = {"source9_baseline": base}
            fixed = json.loads(json.dumps(base))
            for frame in fixed:
                frame["lower"][0] = pose_value(target["local"]["hips"][:3, 3], m.rotation(target["local"]["hips"]))
            variants["fixed8_uncorrected"] = fixed
            corrected, clamp_records = [], []
            for frame in base:
                pose, records = reproject_fixed_hips(frame["lower"], target)
                corrected.append({"source_time": frame["source_time"], "lower": pose})
                clamp_records.append({"source_time": frame["source_time"], "legs": records})
            variants["fixed8_endpoint_reprojected"] = corrected
            for spatial_mode, frames in variants.items():
                writes_hips = spatial_mode == "source9_baseline"
                # Align quaternion signs independently after IK; no pose change.
                for bone in range(9):
                    previous = None
                    for frame in frames:
                        q = np.array(frame["lower"][bone]["rotation"])
                        if previous is not None and np.dot(q, previous) < 0:
                            q = -q
                        frame["lower"][bone]["rotation"] = m.round_list(q)
                        previous = q
                seam = {"local_rotation_max_rad": max(angle(a["rotation"], b["rotation"])
                            for a, b in zip(frames[0]["lower"], frames[-1]["lower"])),
                        "local_position_max_m": max(float(np.linalg.norm(np.array(a["position"])-b["position"]))
                            for a, b in zip(frames[0]["lower"], frames[-1]["lower"]))}
                contract = {"finite": True, "normalized_quaternions": True,
                            "all_nonhips_target_local_translations_preserved": True,
                            "all_target_scales_preserved": True, "fixed8_hips_held_at_original_rest": True,
                            "actor_root_tracks": [], "upper_tracks": [], "writes_hips": writes_hips,
                            "track_count": 10 if writes_hips else 8, "target_joint_count": 87,
                            "maximum_fk_leg_segment_length_error_m": 0.}
                for frame in frames:
                    actual_world = fk(frame["lower"], target)
                    for bone, value in zip(target["names"], frame["lower"]):
                        arr = np.array(value["position"]+value["rotation"]+value["scale"])
                        contract["finite"] &= bool(np.isfinite(arr).all())
                        contract["normalized_quaternions"] &= bool(abs(np.linalg.norm(value["rotation"])-1) < 1e-8)
                        if bone != "hips":
                            contract["all_nonhips_target_local_translations_preserved"] &= bool(np.allclose(value["position"], target["local"][bone][:3, 3], rtol=0, atol=1e-9))
                        contract["all_target_scales_preserved"] &= value["scale"] == [1, 1, 1]
                    for side in ["L", "R"]:
                        for parent_part, child_part in [("thigh", "shin"), ("shin", "foot"), ("foot", "toe")]:
                            parent_name, child_name = parent_part+side, child_part+side
                            actual_length = np.linalg.norm(actual_world[child_name][:3, 3]-actual_world[parent_name][:3, 3])
                            rest_length = np.linalg.norm(target["local"][child_name][:3, 3])
                            contract["maximum_fk_leg_segment_length_error_m"] = max(contract["maximum_fk_leg_segment_length_error_m"], float(abs(actual_length-rest_length)))
                    if not writes_hips:
                        contract["fixed8_hips_held_at_original_rest"] &= bool(np.allclose(frame["lower"][0]["position"], target["local"]["hips"][:3, 3], rtol=0, atol=1e-9))
                        contract["fixed8_hips_held_at_original_rest"] &= angle(frame["lower"][0]["rotation"], m.quat(m.rotation(target["local"]["hips"]))) < 1e-7
                if not all(contract[key] for key in ["finite", "normalized_quaternions", "all_nonhips_target_local_translations_preserved", "all_target_scales_preserved", "fixed8_hips_held_at_original_rest"]) or contract["maximum_fk_leg_segment_length_error_m"] > 1e-8:
                    raise ValueError("Structural resource contract failed")
                for time_mode in TIME_MODES:
                    rate = 1. if time_mode == "original_time" else retime
                    clip_id = "mixamo_loop_"+Path(name).stem.replace(" ", "_")+"_"+spatial_mode+"_"+time_mode
                    exported = [{**frame, "time": frame["source_time"]/rate,
                                 "source_contact_candidate": [bool(masks[s][i]) for s in ["L", "R"]]}
                                for i, frame in enumerate(frames)]
                    clip = {"id": clip_id, "source_file": name, "spatial_mode": spatial_mode, "time_mode": time_mode,
                            "loop": True, "duration": original_duration/rate, "source_duration": original_duration,
                            "playback_rate_from_original": rate, "writes_hips": writes_hips, "root_tracks": [],
                            "upper_tracks": [], "source_trajectory_is_metadata_only": True,
                            "world_foot_lock_applied": False, "frames": exported}
                    text = animation_text(clip, target["names"])
                    if 'NodePath("Skeleton3D:hips")' in text and not writes_hips:
                        raise ValueError("Unexpected fixed8 Hips track")
                    if text.count('/type =') != contract["track_count"] or 'loop_mode = 1' not in text:
                        raise ValueError("Serialized track/loop contract failed")
                    write(OUTPUT/(clip_id+".tres"), text)
                    clips.append(clip)
                    at_six = [temporal_quality(frames, target, upper_rest, masks, original_duration,
                                               DRY_KID_SPEED, direction, rate, fps, writes_hips) for fps in [60, 30]]
                    matching_reference = temporal_quality(frames, target, upper_rest, masks, original_duration,
                                                          reference_speed*rate, direction, rate, 60, writes_hips)
                    issues = []
                    for quality in at_six:
                        if quality["fps"] == 60 and quality["maximum_local_rotation_step_rad"] > ROTATION_60HZ_THRESHOLD:
                            issues.append("60-Hz local rotation step exceeds declared 0.35-rad diagnostic limit")
                        for foot in quality["feet"]:
                            error = foot["maximum_contact_span_sole_displacement_m"]
                            if error is None:
                                issues.append(f'{quality["fps"]}Hz {foot["side"]}: no inferred-source contact samples')
                            elif error > SLIDE_THRESHOLD:
                                issues.append(f'{quality["fps"]}Hz {foot["side"]}: proxy contact span displacement exceeds declared 0.03m limit')
                    if spatial_mode == "fixed8_endpoint_reprojected":
                        maximum_clamp = max(record["reach_clamp_m"] for frame in clamp_records for record in frame["legs"])
                        if maximum_clamp > 1e-5:
                            issues.append("Fixed Hips cannot reach one or more baseline ankle targets within 1e-5m")
                    if issues:
                        failures.append({"id": clip_id, "issues": issues})
                    reports.append({"id": clip_id, "resource_contract": contract, "loop_endpoint_seam": seam,
                                    "actual_time_mode_quality_at6": at_six,
                                    "matching_scaled_source_speed_quality_60hz": matching_reference,
                                    "reprojection_records": clamp_records if spatial_mode == "fixed8_endpoint_reprojected" else [],
                                    "quality_issues": issues, "production_accepted": False})
    after = {str(path): provenance(path) for path in watched}
    changed = [path for path in before if before[path] != after[path]]
    if changed:
        raise ValueError("Read-only input changed during generation: "+", ".join(changed))
    data = {"version": 1, "experimental": True, "default_enabled": False, "production_accepted": False,
            "original_target_rig_joints": 87, "names": target["names"], "target_indices": target["indices"],
            "target_parents": target["parents"], "target_rest": [pose_value(target["local"][n][:3, 3], m.rotation(target["local"][n])) for n in target["names"]],
            "archive_sha256": ARCHIVE_SHA, "target_body_sha256": TARGET_SHA,
            "source_evidence": source_evidence, "clips": clips}
    write(OUTPUT/"loops.json", json_text(data))
    report = {"version": 1, "experimental": True, "default_enabled": False, "production_accepted": False,
              "actual_avatar_input_acceptance": False, "engine_invoked": False,
              "source_correction_invoked": False, "production_database_changed": False,
              "method": "Frozen parser/global rest-basis FK. Remove only cumulative linear Hips XZ travel; retain nonlinear XZ sway and source rest-relative Y. Fixed8 holds original target Hips. Optional two-segment endpoint reprojection transports signed knee plane and retains raw axial twist by shortest swing; no contact/world-foot lock.",
              "dry_kid_speed_mps": DRY_KID_SPEED,
              "contact_evidence_thresholds": {"source_toe_height_above_clip_floor_m": CONTACT_HEIGHT, "source_toe_world_xz_speed_mps": CONTACT_SPEED},
              "diagnostic_quality_limits": {"contact_span_sole_displacement_m": SLIDE_THRESHOLD, "local_rotation_step_at60hz_rad": ROTATION_60HZ_THRESHOLD, "reprojection_endpoint_error_m": 1e-5},
              "contact_and_ground_limits": "Original source toe candidates only. Nearest original-key masks are resampled for target diagnostics. Synthetic constant Actor translation is a measurement proxy, never an exported root track. Sole=original runtime heel/ball proxy, not shoe mesh. No target ground calibration, terrain query, foot lock, real Avatar, captured input, rendered footage, transition or export acceptance.",
              "source_evidence": source_evidence, "candidate_reports": reports,
              "structural_contract_failures": 0, "quality_failing_candidate_count": len(failures),
              "quality_failures": failures, "read_only_inputs_unchanged": True,
              "inputs_before": list(before.values()), "inputs_after": list(after.values())}
    write(CACHE/"report.json", json_text(report))
    output_records = [provenance(path) for path in sorted(OUTPUT.glob("*")) if path.is_file() and path.name != "provenance.json"]
    manifest = {"generator": provenance(Path(__file__)), "inputs_before": list(before.values()), "inputs_after": list(after.values()),
                "read_only_inputs_unchanged": True, "outputs": output_records,
                "report": provenance(CACHE/"report.json"), "resource_count": len(clips), "structural_contract_failures": 0,
                "quality_failing_candidate_count": len(failures), "production_accepted": False}
    write(OUTPUT/"provenance.json", json_text(manifest))
    print(json.dumps({"resources": len(clips), "structural_failures": 0, "quality_failing_candidates": len(failures),
                      "original_inputs_unchanged": True, "production_accepted": False,
                      "report": str(CACHE/"report.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
