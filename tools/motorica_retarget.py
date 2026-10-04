"""Isolated Motorica 71 -> Splatink 87 bone candidates; never starts Godot.

Reads three original FBXs, copies them only into .tools, samples exact source
30-Hz keys, and exports complete one-shots plus honest contact diagnostics.
No contact correction, clip time warp, production database, or controller edits.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import hashlib, json, math
from pathlib import Path
import numpy as np
import mixamo_retarget as reader  # Frozen parser/GLB reader; never call its main.

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path(r"F:\Downloads\godot-motion-matching-demo-master\godot-motion-matching-demo-master\animation\motorica\running\forward")
FILES = {
    "Run_Turns_StartStop_L_variation_1.fbx": "9149f1c3d9c7e9528654b13ee30938dc870abf08ef34002cff43fcb8c7d09bab",
    "Run_Turns_L_variation_1.fbx": "9ef0639f0a3d8a188755341a8eeb366cb05b6f7ae330519b97285d1a7489019e",
    "Run_Turns_180.fbx": "49da698058455a09dc645becdbc295396eb331011dcd4f926148402f9754086d",
}
MAP = dict(reader.MAP)
MODES = ["source_path_pelvis9", "fixed_authority_leg8"]
WINDOWS = {
    "Run_Turns_StartStop_L_variation_1.fbx": [
        {"id": "first_start", "kind": "start", "start": .5, "end": 2.4},
        {"id": "first_stop", "kind": "stop", "start": 3.2, "end": 5.2},
        {"id": "second_start", "kind": "start", "start": 6.7, "end": 8.6},
    ],
    "Run_Turns_L_variation_1.fbx": [
        {"id": "running_left_90", "kind": "running_body_turn", "start": 6., "end": 8.},
        {"id": "running_left_180", "kind": "braking_body_pivot", "start": 12.3, "end": 14.5},
    ],
    "Run_Turns_180.fbx": [
        {"id": "first_left_180", "kind": "braking_body_pivot", "start": .6, "end": 2.8},
        {"id": "first_right_180", "kind": "braking_body_pivot", "start": 2.7, "end": 4.9},
    ],
}

def write(path: Path, data: str | bytes):
    path = path.resolve()
    if not path.is_relative_to(ROOT.resolve()):
        raise ValueError("Output escaped Splatink")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    if isinstance(data, bytes): temporary.write_bytes(data)
    else: temporary.write_text(data, encoding="utf-8")
    temporary.replace(path)

def values(v): return np.asarray(v).round(10).tolist()

def intervals(mask, times):
    result = []; begin = None
    for i, active in enumerate(mask):
        if active and begin is None: begin = i
        if begin is not None and (not active or i == len(mask)-1):
            end = i if active else i-1
            result.append([float(times[begin]), float(times[end])]); begin = None
    return result

def source_contact(src, side):
    names = [side+"ToeBase", side+"ToeBase_End"]
    points = np.array([[w[n][:3,3] for n in names] for w in src["frames"]])
    speed = np.linalg.norm(np.gradient(points[:,:,[0,2]], src["times"], axis=0), axis=2)
    floor = float(points[:,:,1].min())
    active = np.any((points[:,:,1] <= floor+.03) & (speed <= .25), axis=1)
    return active, floor

def contact_quality(frames, world, names, candidate, path_scale, hip_fixed):
    result = {}; anchors = {}; tags = {}; points = {}
    for side in ["L", "R"]:
        foot = "foot"+side
        proxy = np.array([reader.foot_points(w[foot]) for w in world])
        on = candidate[side]
        slips = []; current = None; point = 0; old = False
        for i, active in enumerate(on):
            if active and not old:
                point = int(proxy[i,:,1].argmin()); current = proxy[i,point].copy()
            if active: slips.append(float(np.linalg.norm(proxy[i,point]-current)))
            anchors.setdefault(side, []).append(values(current if active else [0,0,0]))
            points.setdefault(side, []).append(point)
            old = bool(active)
        result[side] = {"inferred_source_contact_frames": int(on.sum()),
            "maximum_uncorrected_proxy_slide_m": max(slips, default=0.),
            "minimum_target_proxy_y_m": float(proxy[:,:,1].min()),
            "proxy_slide_passes_3cm": max(slips, default=0.) < .03}
    for i, frame in enumerate(frames):
        frame["source_contact_candidate"] = [bool(candidate[s][i]) for s in ["L","R"]]
        frame["source_contact_span_anchor"] = [anchors[s][i] for s in ["L","R"]]
        frame["source_contact_proxy_index"] = [points[s][i] for s in ["L","R"]]
    return result

def export_clip(filename, src, target):
    times = src["times"]; frames = src["frames"]
    names = target["names"]
    ratios = {}
    for side in ["L","R"]:
        ratios[side] = {}
        for bone, child in [("thigh", "shin"), ("shin", "foot"), ("foot", "toe")]:
            source_length = np.linalg.norm(src["rest"][MAP[child+side]][:3,3] - src["rest"][MAP[bone+side]][:3,3])
            target_length = np.linalg.norm(target["local"][child+side][:3,3])
            ratios[side][bone] = float(target_length/source_length)
    leg_scale = float(np.mean([
        (np.linalg.norm(target["local"]["shin"+s][:3,3])+np.linalg.norm(target["local"]["foot"+s][:3,3])) /
        (np.linalg.norm(src["rest_local"][MAP["shin"+s]][:3,3])+np.linalg.norm(src["rest_local"][MAP["foot"+s]][:3,3]))
        for s in ["L","R"]]))
    root_positions = np.array([w["Root"][:3,3] for w in frames])
    root_positions -= root_positions[0]
    root_rotations = [reader.rotation(w["Root"]) for w in frames]
    yaw = np.unwrap([math.atan2(r[0,2], r[2,2]) for r in root_rotations])
    yaw -= yaw[0]
    velocity = np.gradient(root_positions, times, axis=0)
    source_speed = np.linalg.norm(velocity[:,[0,2]], axis=1)
    root_rest_inv = np.linalg.inv(src["rest"]["Root"])
    source_rest = {n: root_rest_inv @ src["rest"][MAP[n]] for n in names}
    candidates = {}; floors = {}
    for s, full in [("L","Left"),("R","Right")]: candidates[s], floors[s] = source_contact(src, full)
    exports = {}
    for mode in MODES:
        fixed = mode == "fixed_authority_leg8"
        output = []; world = []; previous = {}; max_step = 0.; worst = {}
        for frame, original in enumerate(frames):
            root_inv = np.linalg.inv(original["Root"])
            global_rotation = {}; target_world = {}; lower = []
            for n in names:
                source_in_root = root_inv @ original[MAP[n]]
                r = reader.rotation(source_in_root) @ reader.rotation(source_rest[n]).T @ reader.rotation(target["world"][n])
                global_rotation[n] = r
                parent = target["parents"][n]
                local_r = global_rotation[parent].T @ r if parent in global_rotation else r
                p = target["local"][n][:3,3].copy()
                if n == "hips":
                    p += (source_in_root[:3,3] - source_rest[n][:3,3])*leg_scale
                    if fixed: p = target["local"][n][:3,3].copy(); local_r = reader.rotation(target["local"][n]); global_rotation[n] = reader.rotation(target["world"][n])
                q = reader.quat(local_r)
                if n in previous:
                    if np.dot(q, previous[n]) < 0: q = -q
                    angle = 2*math.acos(float(np.clip(np.dot(q,previous[n]),-1,1)))
                    if angle > max_step: max_step = angle; worst = {"time":float(times[frame]),"bone":n}
                previous[n] = q
                lower.append({"position":values(p),"rotation":values(q),"scale":[1,1,1]})
                local = reader.transform(p,local_r)
                target_world[n] = target_world[parent] @ local if parent in target_world else local
            # Authored path is a dedicated PREVIEW root only. Fixed8 diagnostics
            # also use that path so removing it cannot manufacture planted feet.
            preview = reader.transform(root_positions[frame]*leg_scale, reader.euler([0,math.degrees(yaw[frame]),0]))
            world.append({n:preview @ w for n,w in target_world.items()})
            output.append({"time":float(times[frame]),"root_yaw":float(yaw[frame]),
                "source_root_position_m":values(root_positions[frame]),
                "source_root_rotation":values(reader.quat(root_rotations[frame])),
                "source_root_velocity_mps":values(velocity[frame]),
                "source_root_speed_mps":float(source_speed[frame]),
                "target_reference_root_position_m":values(root_positions[frame]*leg_scale),
                "target_reference_root_velocity_mps":values(velocity[frame]*leg_scale),
                "lower":lower})
        quality = contact_quality(output,world,names,candidates,leg_scale,fixed)
        exports[mode] = {"id":"motorica_"+Path(filename).stem+"_"+mode,
            "mode":mode,"duration":float(times[-1]),"writes_hips":not fixed,
            "frames":output,"quality":quality,
            "maximum_30hz_local_rotation_step_rad":max_step,
            "slerp_expected_maximum_60hz_step_rad":max_step*.5,"worst":worst,
            "contact_correction_applied":False}
    windows = []
    for annotation in WINDOWS[filename]:
        a=int(round(annotation["start"]*30)); b=int(round(annotation["end"]*30))
        windows.append({**annotation,"annotation_source":"measured raw Root curve; experimental window, not authored event markers",
            "body_root_turn_radians":float(yaw[b]-yaw[a]),
            "minimum_source_speed_mps":float(source_speed[a:b+1].min()),
            "maximum_source_speed_mps":float(source_speed[a:b+1].max()),
            "median_source_speed_mps":float(np.median(source_speed[a:b+1]))})
    return {"id":"motorica_"+Path(filename).stem,"source_file":filename,
        "duration":float(times[-1]),"sample_count":len(times),"loop":False,
        "source_bones":71,"root_tracks":[],"segment_length_ratios":ratios,
        "preview_root_scale":leg_scale,"source_root_path_m":float(np.linalg.norm(np.diff(root_positions[:,[0,2]],axis=0),axis=1).sum()),
        "source_speed_mps":{"min":float(source_speed.min()),"max":float(source_speed.max()),"median":float(np.median(source_speed))},
        "source_stationary_spans":intervals(source_speed < .15,times),
        "source_contact_floor_m":floors,"candidate_windows":windows,"variants":exports}

def main():
    if ROOT.resolve()!=Path(r"H:\GDP\inkwave\splatink").resolve(): raise ValueError("Unexpected workspace")
    cache=ROOT/".tools/motorica-locomotion"; out=ROOT/"assets/animation/experiments/motorica"
    write(cache/".gdignore", "\n")
    target=reader.target_rig(); clips=[]; origins=[]; common_rest=None
    for filename, expected in FILES.items():
        path=SOURCE/filename; before=path.stat(); raw=path.read_bytes()
        if hashlib.sha256(raw).hexdigest()!=expected: raise ValueError("Source SHA mismatch: "+filename)
        write(cache/"source"/filename,raw)
        src=reader.source_frames(raw)
        if sum(n!="Camera Switcher" for n in src["names"])!=71: raise ValueError("Unexpected raw rig")
        if common_rest is None: common_rest=src
        elif src["parents"]!=common_rest["parents"] or any(not np.array_equal(src["rest"][n],common_rest["rest"][n]) for n in src["names"]): raise ValueError("Source rig mismatch")
        clip=export_clip(filename,src,target);clip["source_sha256"]=expected;clips.append(clip)
        for variant in clip["variants"].values():write(out/(variant["id"]+".tres"),reader.animation_text(variant,target["names"]))
        after=path.stat()
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns) or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:raise ValueError("Original source changed")
        origins.append({"original":str(path),"isolated_copy":str(cache/"source"/filename),"size_bytes":len(raw),"sha256":expected,"source_unchanged":True})
    metadata={"version":1,"experimental":True,"default_enabled":False,"accepted_for_production":False,
        "source_rig_bones":71,"target_rig_bones":87,"fps":30,"target_body_sha256":target["sha256"],
        "names":target["names"],"target_indices":target["indices"],"target_parents":target["parents"],
        "target_rest":[{"position":values(target["local"][n][:3,3]),"rotation":values(reader.quat(reader.rotation(target["local"][n]))),"scale":[1,1,1]} for n in target["names"]],
        "source_rest":{n:{"parent":common_rest["parents"][n],"local_matrix":values(common_rest["rest_local"][n]),"global_matrix":values(common_rest["rest"][n])} for n in ["Root",*MAP.values()]},
        "source_axes":{"up":"+Y","forward":"+Z","side":"+X","unit_to_m":.01},
        "velocity_method":"numpy.gradient of exact 30Hz original Root XZ positions: centered difference inside, one-sided at endpoints; no interpolation/time warp",
        "source_interpolation":"varying source FBX curves carry flags 0x104 (linear); exact 30Hz source keys sampled, exported rotations quaternion slerp at playback",
        "method":"Root-separated global rest-basis deltas; retain target individual segment offsets and complete source timeline; no position normalization from Meshy; no synthesized foot correction",
        "root_policy":"original Root motion retained as metadata and optional scaled visual-path root; apply never changes owner/world root or production controller",
        "contact_labels":"inferred original ToeBase/ToeBase_End low-height+low-XZ-speed; .03m/.25mps; diagnostic only, not authored events or production FootPlant",
        "clips":clips}
    write(out/"candidates.json",json.dumps(metadata,separators=(",",":")))
    audit={k:v for k,v in metadata.items() if k!="clips"}
    audit["clips"]=[{**{k:v for k,v in c.items() if k!="variants"},"variants":{mode:{k:v for k,v in d.items() if k!="frames"} for mode,d in c["variants"].items()}} for c in clips]
    write(out/"metadata.json",json.dumps(audit,indent=2))
    provenance={"experiment_only":True,"accepted_for_production":False,"source_origins":origins,
        "body_sha256":target["sha256"],"frozen_parser_sha256":hashlib.sha256(Path(reader.__file__).read_bytes()).hexdigest(),
        "exporter_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),"godot_executed_by_exporter":False,
        "verified":"offline source/root/FK diagnostics only; actual Godot rig/upper-body/aim/contact/entry validation pending"}
    write(out/"provenance.json",json.dumps(provenance,indent=2))
    print(json.dumps({"metadata":str(out/"metadata.json"),"target_sha256":target["sha256"],"clips":[{k:c[k] for k in ["id","duration","sample_count","candidate_windows","segment_length_ratios","preview_root_scale"]} for c in clips]},indent=2))

if __name__=="__main__":main()
