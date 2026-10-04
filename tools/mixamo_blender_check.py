"""Export an independent Blender FK reference for the four Mixamo turns.

Run with a fresh, offline Blender process; never pass a .blend file:
  blender --background --factory-startup --python-exit-code 1 \
    --python tools/mixamo_blender_check.py

Only the selected FBX fixtures and JSON reference files beneath
.tools/mixamo-turn-prototype/{source,blender} are written. The original ZIP
is opened read-only, checked against its approved SHA-256, and checked again
after export. Blender's own importer, evaluator, and FBX metadata parser are
used for reference export. Optional comparisons read raw_source.json and can
execute only the converter's source_frames() to obtain rest matrices. The
converter's main(), target retargeting, and asset writes are never invoked.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile

ARCHIVE_SHA256 = "e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86"
SELECTED = (
    ("left_turn", "left turn.fbx"),
    ("right_turn", "right turn.fbx"),
    ("left_turn_90", "left turn 90.fbx"),
    ("right_turn_90", "right turn 90.fbx"),
)
FBX_TICKS_PER_SECOND = 46186158000
SAMPLE_HZ = 30
REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def reject_reparse_components(path):
    """Inspect lexical ancestors before resolving; reject junctions as well as links."""
    lexical = Path(os.path.abspath(path))
    for component in reversed((lexical, *lexical.parents)):
        try:
            info = component.lstat()
        except FileNotFoundError:
            continue
        if component.is_symlink() or getattr(info, "st_file_attributes", 0) & REPARSE_POINT:
            raise ValueError(f"Reparse point is not permitted: {component}")
    return lexical


def checked_path(path, allowed_root):
    lexical = reject_reparse_components(path)
    resolved = lexical.resolve()
    root = reject_reparse_components(allowed_root).resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(f"Output escapes allowed directory {root}: {resolved}")
    return resolved


def ensure_directory(path, allowed_root):
    target = checked_path(path, allowed_root)
    target.mkdir(parents=True, exist_ok=True)
    return checked_path(target, allowed_root)


def write_json(path, payload, allowed_root):
    target = checked_path(path, allowed_root)
    temporary = checked_path(target.with_name(target.name + ".tmp"), allowed_root)
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(payload, stream, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write("\n")
    # Both names have been checked and belong to this helper's output directory.
    os.replace(temporary, target)


def archive_snapshot(path):
    info = path.stat()
    return {"path": str(path), "size_bytes": info.st_size,
            "mtime_ns": info.st_mtime_ns, "sha256": digest(path)}


def extract_four(archive, destination):
    result = []
    with zipfile.ZipFile(archive, "r") as pack:
        members = pack.infolist()
        for entry in members:
            member = PurePosixPath(entry.filename.replace("\\", "/"))
            mode = (entry.external_attr >> 16) & 0xFFFF
            if (member.is_absolute() or ".." in member.parts or ":" in entry.filename
                    or stat.S_ISLNK(mode) or "\x00" in entry.filename):
                raise ValueError(f"Unsafe ZIP member: {entry.filename!r}")
        for clip_id, filename in SELECTED:
            matching = [entry for entry in members if entry.filename == filename]
            if len(matching) != 1:
                raise ValueError(f"Expected exactly one archive entry for {filename!r}")
            entry = matching[0]
            if entry.is_dir():
                raise ValueError(f"Selected member is not a file: {filename}")
            content = pack.read(entry)
            target = checked_path(destination / filename, destination)
            if target.exists():
                if target.read_bytes() != content:
                    raise ValueError(f"Existing fixture differs from approved archive: {target}")
            else:
                with target.open("xb") as stream:
                    stream.write(content)
            result.append({"id": clip_id, "archive_member": filename,
                           "source_file": str(target), "size_bytes": len(content),
                           "sha256": hashlib.sha256(content).hexdigest(),
                           "zip_crc32": f"{entry.CRC:08x}"})
    return result


def child(element, name):
    return next((item for item in element.elems if item.id == name), None)


def properties(element):
    entries = child(element, b"Properties70")
    if entries is None:
        return {}
    result = {}
    for entry in entries.elems:
        if entry.id != b"P":
            continue
        key = entry.props[0].decode("utf-8")
        values = [value.decode("utf-8") if isinstance(value, bytes) else value
                  for value in entry.props[4:]]
        result[key] = values[0] if len(values) == 1 else list(values)
    return result


def fbx_metadata(path):
    # This is Blender's official binary parser, independent of audit_pack.py.
    from io_scene_fbx import parse_fbx
    root, version = parse_fbx.parse(str(path))
    globals_ = properties(child(root, b"GlobalSettings"))
    objects = child(root, b"Objects")
    curves = [obj for obj in objects.elems if obj.id == b"AnimationCurve"]
    key_times = [child(curve, b"KeyTime").props[0] for curve in curves]
    first = min(int(times[0]) for times in key_times) / FBX_TICKS_PER_SECOND
    last = max(int(times[-1]) for times in key_times) / FBX_TICKS_PER_SECOND
    bones = [obj for obj in objects.elems
             if obj.id == b"Model" and obj.props[2] == b"LimbNode"]
    names = [obj.props[1].split(b"\x00", 1)[0].decode("utf-8") for obj in bones]
    return {"fbx_version": version, "global_settings": globals_,
            "source_first_key_s": first, "source_last_key_s": last,
            "source_bone_names": names}


def matrix_rows(matrix):
    return [[float(matrix[row][column]) for column in range(4)] for row in range(4)]


def position(matrix):
    return [float(matrix[row][3]) for row in range(3)]


def canonical_world(matrix, unit_scale_m, canonical_rotation):
    """Source Y-up basis with meter translations and dimensionless bone axes.

    Importer puts the centimeter conversion in armature.matrix_world. Divide
    only its 3x3 basis by that uniform factor, preserving authored bone scale.
    Local bone axes are preserved by primary Y / secondary X and auto=False;
    therefore this is C @ world, not C @ world @ C^-1.
    """
    result = canonical_rotation @ matrix
    for row in range(3):
        for column in range(3):
            result[row][column] /= unit_scale_m
    return result


IMPORT_OPTIONS = {
    "use_manual_orientation": False,
    "global_scale": 1.0,
    "bake_space_transform": False,
    "use_anim": True,
    "anim_offset": 0.0,
    "ignore_leaf_bones": False,
    "force_connect_children": False,
    "automatic_bone_orientation": False,
    "primary_bone_axis": "Y",
    "secondary_bone_axis": "X",
    "use_prepost_rot": True,
    "use_image_search": False,
}


def export_clip(source, output_dir):
    import bpy
    from mathutils import Matrix
    metadata = fbx_metadata(Path(source["source_file"]))
    globals_ = metadata["global_settings"]
    axes = tuple(globals_.get(key) for key in
                 ("UpAxis", "UpAxisSign", "FrontAxis", "FrontAxisSign", "CoordAxis", "CoordAxisSign"))
    if axes != (1, 1, 2, 1, 0, 1):
        raise ValueError(f"Source orientation differs from approved Y-up Mixamo FBX: {axes}")
    unit_scale_m = float(globals_.get("UnitScaleFactor", 1.0)) / 100.0
    if len(metadata["source_bone_names"]) != 65:
        raise ValueError("Approved source must contain its original 65 LimbNode bones")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    status = bpy.ops.import_scene.fbx(filepath=source["source_file"], **IMPORT_OPTIONS)
    if status != {"FINISHED"}:
        raise RuntimeError(f"Blender FBX import failed: {status}")
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise ValueError(f"Expected one imported armature, found {len(armatures)}")
    armature = armatures[0]
    bone_names = metadata["source_bone_names"]
    if set(armature.data.bones.keys()) != set(bone_names):
        raise ValueError("Blender changed the source bone membership")
    if not armature.animation_data or not armature.animation_data.action:
        raise ValueError("No active action was imported for the source armature")
    action = armature.animation_data.action
    first = metadata["source_first_key_s"]
    last = metadata["source_last_key_s"]
    duration = last - first
    frame_count = round(duration * SAMPLE_HZ) + 1
    if abs((frame_count - 1) / SAMPLE_HZ - duration) > 1e-7:
        raise ValueError("Source endpoints do not lie on the expected 30 Hz sample grid")
    canonical_rotation = Matrix.Rotation(-math.pi / 2.0, 4, "X")
    fps = scene.render.fps / scene.render.fps_base
    bones = []
    for name in bone_names:
        bone = armature.data.bones[name]
        native = armature.matrix_world @ bone.matrix_local
        world = canonical_world(native, unit_scale_m, canonical_rotation)
        bones.append({"name": name, "parent": bone.parent.name if bone.parent else None,
                      "rest_world_matrix": matrix_rows(world),
                      "rest_world_position_m": position(world),
                      "rest_blender_world_matrix": matrix_rows(native),
                      "rest_armature_matrix": matrix_rows(bone.matrix_local)})
    frames = []
    for index in range(frame_count):
        time = index / SAMPLE_HZ
        source_time = first + time
        if index == frame_count - 1:
            source_time = last
        frame = source_time * fps + IMPORT_OPTIONS["anim_offset"]
        integer = math.floor(frame)
        scene.frame_set(integer, subframe=frame - integer)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = armature.evaluated_get(depsgraph)
        native_matrices = [evaluated.matrix_world @ evaluated.pose.bones[name].matrix
                           for name in bone_names]
        matrices = [canonical_world(matrix, unit_scale_m, canonical_rotation)
                    for matrix in native_matrices]
        frames.append({"time_s": time, "source_time_s": source_time,
                       "blender_frame": frame,
                       "world_matrices": [matrix_rows(matrix) for matrix in matrices],
                       "world_positions_m": [position(matrix) for matrix in matrices],
                       "blender_world_matrices": [matrix_rows(matrix) for matrix in native_matrices]})
    payload = {"schema": "mixamo_blender_reference_v1", **source, **metadata,
               "sample_hz": SAMPLE_HZ, "duration_s": duration,
               "frame_count": frame_count, "bone_count": len(bones),
               "bone_order": bone_names,
               "import_options": IMPORT_OPTIONS,
               "blender_action": action.name,
               "blender_action_frame_range": list(action.frame_range),
               "blender_fps": fps,
               "blender_armature_world_matrix": matrix_rows(armature.matrix_world),
               "coordinate_space": {
                   "canonical": "source FBX +Y-up/+Z-front, source X side-axis unchanged; translations in meters",
                   "blender": "imported Blender Z-up world; translations in meters",
                   "matrix_layout": "4x4 row-major arrays; column-vector multiplication",
                   "matrix_semantics": "canonical bone-local to source-world; dimensionless 3x3 basis",
                   "canonical_rotation_from_blender": matrix_rows(canonical_rotation),
                   "source_unit_to_meter": unit_scale_m,
                   "basis_normalization": "canonical 3x3 = (C @ Blender world) 3x3 / source_unit_to_meter",
                   "bone_orientation_correction": "identity: auto=False, primary Y, secondary X",
                   "array_order": "every frame array follows bone_order and bones[]"},
               "bones": bones, "frames": frames}
    destination = output_dir / (source["id"] + ".json")
    write_json(destination, payload, output_dir)
    return {"id": source["id"], "reference_file": str(destination),
            "source_file": source["source_file"], "source_sha256": source["sha256"],
            "bone_count": len(bones), "frame_count": frame_count,
            "duration_s": duration, "blender_action": action.name,
            "action_frame_range": list(action.frame_range)}


def raw_rest_reference(sampler_path, sources, output_dir):
    """Evaluate the sibling converter's read-only source_frames entry point.

    Executing a named namespace rather than importing prevents __pycache__
    writes in the converter's directory and does not invoke its main guard.
    This supplies comparison data; Blender export above remains independent.
    """
    sampler_path = reject_reparse_components(sampler_path).resolve(strict=True)
    expected = Path(__file__).resolve().with_name("mixamo_retarget.py")
    if sampler_path != expected:
        raise ValueError(f"Only the sibling approved source sampler may be used: {expected}")
    code = sampler_path.read_bytes()
    namespace = {"__file__": str(sampler_path), "__name__": "mixamo_readonly_rest_reference"}
    previous_path = sys.path[:]
    previous_bytecode_setting = sys.dont_write_bytecode
    try:
        # Converter revisions may have harmless top-level sibling imports.
        # Resolve them from tools, but never create or update their __pycache__.
        sys.path.insert(0, str(sampler_path.parent))
        sys.dont_write_bytecode = True
        exec(compile(code, str(sampler_path), "exec"), namespace)
    finally:
        sys.path[:] = previous_path
        sys.dont_write_bytecode = previous_bytecode_setting
    sample = namespace.get("source_frames")
    if not callable(sample):
        raise ValueError("Raw sampler does not expose source_frames(data)")
    result = {"schema": "mixamo_raw_rest_reference_v1",
              "sampler": str(sampler_path), "sampler_sha256": hashlib.sha256(code).hexdigest(),
              "method": "Call only source_frames(data); converter main()/target_rig()/generate() never called",
              "clips": []}
    for source in sources:
        content = Path(source["source_file"]).read_bytes()
        if hashlib.sha256(content).hexdigest() != source["sha256"]:
            raise ValueError("Extracted fixture changed before raw rest sampling")
        raw = sample(content)
        result["clips"].append({"source_file": source["archive_member"],
                                "source_sha256": source["sha256"],
                                "rest_world_matrices": {name: matrix.tolist()
                                                        for name, matrix in raw["rest"].items()}})
    if digest(sampler_path) != result["sampler_sha256"]:
        raise RuntimeError("Raw sampler changed during read-only rest evaluation")
    write_json(output_dir / "raw_rest_reference.json", result, output_dir)
    return result


def compare_raw_reference(raw_path, clips, output_dir, raw_rest=None):
    """Compare converter JSON only; never execute or import the raw sampler.

    raw_source.json schema: a four-clip list. Each clip has source_file, names,
    parents, rest_global_positions_m, and frames[{time, world_positions_m,
    world_rotations}]. Quaternions are x,y,z,w in source Y-up world coordinates.
    """
    import numpy as np

    raw_path = reject_reparse_components(raw_path).resolve(strict=True)
    raw_digest_before = digest(raw_path)
    raw_clips = json.loads(raw_path.read_text(encoding="utf-8"))
    if not isinstance(raw_clips, list) or len(raw_clips) != len(SELECTED):
        raise ValueError("Raw reference must contain exactly the four approved source clips")

    def statistics(values):
        values = np.asarray(values, dtype=float)
        return {"max": float(values.max()), "median": float(np.median(values)),
                "p95": float(np.percentile(values, 95)),
                "rms": float(np.sqrt(np.mean(values ** 2)))}

    def rotation_matrix_error_degrees(matrix, expected):
        # Remove roundoff in Blender's 32-bit evaluated basis by polar rotation.
        u, _, vh = np.linalg.svd(np.asarray(matrix, dtype=float)[:3, :3])
        actual = u @ vh
        if np.linalg.det(actual) < 0:
            raise ValueError("Blender reference has a reflected bone basis")
        difference = np.asarray(expected, dtype=float)[:3, :3].T @ actual
        sine = np.linalg.norm([difference[2, 1]-difference[1, 2],
                               difference[0, 2]-difference[2, 0],
                               difference[1, 0]-difference[0, 1]]) / 2
        cosine = float(np.clip((difference.trace()-1)/2, -1, 1))
        return math.degrees(math.atan2(float(sine), cosine))

    def rotation_error_degrees(matrix, quaternion):
        q = np.asarray(quaternion, dtype=float)
        x, y, z, w = q / np.linalg.norm(q)
        expected = np.array([[1 - 2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                             [2*(x*y+z*w), 1 - 2*(x*x+z*z), 2*(y*z-x*w)],
                             [2*(x*z-y*w), 2*(y*z+x*w), 1 - 2*(x*x+y*y)]])
        return rotation_matrix_error_degrees(matrix, expected)

    report = {"schema": "mixamo_raw_blender_comparison_v1",
              "raw_reference": str(raw_path), "raw_reference_sha256": raw_digest_before,
              "method": "Name-aligned original 65 bones at every exact 30 Hz time; source Y-up meter world positions and shortest global quaternion angle; Blender basis polar-normalized only for 32-bit roundoff",
              "thresholds": {"position_m": 0.00002, "rotation_degrees": 0.005,
                             "time_s": 1e-8}, "clips": []}
    for clip in clips:
        reference = json.loads(Path(clip["reference_file"]).read_text(encoding="utf-8"))
        matching = [item for item in raw_clips if item["source_file"] == reference["archive_member"]]
        if len(matching) != 1:
            raise ValueError(f"Raw reference missing unique clip {reference['archive_member']}")
        raw = matching[0]
        names = reference["bone_order"]
        if len(raw["names"]) != 65 or set(raw["names"]) != set(names):
            raise ValueError("Raw and Blender source bone membership differ")
        lookup = [raw["names"].index(name) for name in names]
        if len(raw["frames"]) != len(reference["frames"]):
            raise ValueError("Raw and Blender frame counts differ")
        for bone in reference["bones"]:
            if raw["parents"][bone["name"]] != bone["parent"]:
                raise ValueError(f"Source parent differs for {bone['name']}")
        rest = [np.linalg.norm(np.asarray(bone["rest_world_position_m"])
                               - raw["rest_global_positions_m"][lookup[index]])
                for index, bone in enumerate(reference["bones"])]
        positions, rotations, times = [], [], []
        for expected, actual in zip(raw["frames"], reference["frames"]):
            times.append(abs(expected["time"] - actual["time_s"]))
            positions.append([float(np.linalg.norm(np.asarray(actual["world_positions_m"][index])
                                                  - expected["world_positions_m"][raw_index]))
                              for index, raw_index in enumerate(lookup)])
            rotations.append([rotation_error_degrees(actual["world_matrices"][index],
                                                     expected["world_rotations"][raw_index])
                              for index, raw_index in enumerate(lookup)])
        positions = np.asarray(positions)
        rotations = np.asarray(rotations)
        worst_position = np.unravel_index(positions.argmax(), positions.shape)
        worst_rotation = np.unravel_index(rotations.argmax(), rotations.shape)
        summary = {"id": clip["id"], "source_file": reference["archive_member"],
                   "frame_count": len(reference["frames"]), "bone_count": len(names),
                   "compared_bone_frames": int(positions.size),
                   "max_time_error_s": max(times),
                   "rest_position_error_m": statistics(rest),
                   "world_position_error_m": statistics(positions.ravel()),
                   "world_rotation_error_degrees": statistics(rotations.ravel()),
                   "worst_position": {"frame": int(worst_position[0]),
                                      "bone": names[worst_position[1]]},
                   "worst_rotation": {"frame": int(worst_rotation[0]),
                                      "bone": names[worst_rotation[1]]},
                   "per_bone": [{"name": name,
                                 "max_world_position_error_m": float(positions[:, index].max()),
                                 "max_world_rotation_error_degrees": float(rotations[:, index].max())}
                                for index, name in enumerate(names)]}
        if raw_rest:
            rest_raw = next(item for item in raw_rest["clips"]
                            if item["source_file"] == reference["archive_member"])
            rest_matrices = rest_raw["rest_world_matrices"]
            rest_rotation_errors = [rotation_matrix_error_degrees(bone["rest_world_matrix"],
                                                                 rest_matrices[bone["name"]])
                                    for bone in reference["bones"]]
            rest_matrix_errors = [float(np.abs(np.asarray(bone["rest_world_matrix"])
                                               - rest_matrices[bone["name"]]).max())
                                  for bone in reference["bones"]]
            summary["rest_world_rotation_error_degrees"] = statistics(rest_rotation_errors)
            summary["rest_world_matrix_max_abs_element_error"] = max(rest_matrix_errors)
        summary["passed"] = (max(times) <= report["thresholds"]["time_s"]
                             and max(rest) <= report["thresholds"]["position_m"]
                             and float(positions.max()) <= report["thresholds"]["position_m"]
                             and float(rotations.max()) <= report["thresholds"]["rotation_degrees"])
        if raw_rest:
            summary["passed"] &= max(rest_rotation_errors) <= report["thresholds"]["rotation_degrees"]
        report["clips"].append(summary)
    if digest(raw_path) != raw_digest_before:
        raise RuntimeError("Raw reference changed during read-only comparison")
    report["passed"] = all(clip["passed"] for clip in report["clips"])
    if raw_rest:
        report["raw_rest_reference"] = {"file": str(output_dir / "raw_rest_reference.json"),
                                        "sampler": raw_rest["sampler"],
                                        "sampler_sha256": raw_rest["sampler_sha256"]}
    report["compared_bone_frames"] = sum(clip["compared_bone_frames"] for clip in report["clips"])
    write_json(output_dir / "raw_comparison.json", report, output_dir)
    if not report["passed"]:
        raise RuntimeError(f"Raw FK and Blender disagree; inspect {output_dir / 'raw_comparison.json'}")
    return report


def main():
    import bpy
    if not bpy.app.background or "--factory-startup" not in sys.argv:
        raise RuntimeError("Use --background --factory-startup in a separate Blender process")
    if bpy.data.filepath:
        raise RuntimeError("A .blend file was supplied; this checker requires an empty factory session")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=Path(r"E:\backup\Locomotion Pack.zip"))
    parser.add_argument("--compare-raw", type=Path,
                        help="Read-only converter raw_source.json to compare all 65 bones at every frame")
    parser.add_argument("--rest-sampler", type=Path,
                        help="Optional sibling mixamo_retarget.py; call only source_frames to compare rest basis")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if arguments.rest_sampler and not arguments.compare_raw:
        parser.error("--rest-sampler requires --compare-raw")
    project = reject_reparse_components(Path(__file__).absolute().parent.parent).resolve()
    prototype = checked_path(project / ".tools" / "mixamo-turn-prototype", project)
    sources = ensure_directory(prototype / "source", prototype)
    output = ensure_directory(prototype / "blender", prototype)
    archive = reject_reparse_components(arguments.archive).resolve(strict=True)
    before = archive_snapshot(archive)
    if before["sha256"] != ARCHIVE_SHA256:
        raise ValueError("Original archive SHA-256 differs from the approved read-only source")
    result = {"schema": "mixamo_blender_manifest_v1", "archive_before": before,
              "blender_version": bpy.app.version_string,
              "blender_build_hash": bpy.app.build_hash.decode("utf-8"),
              "blender_binary": bpy.app.binary_path,
              "command_argv": sys.argv,
              "script": str(Path(__file__).resolve()),
              "script_sha256": digest(__file__),
              "import_options": IMPORT_OPTIONS, "sample_hz": SAMPLE_HZ,
              "method": "Blender FBX import and evaluated dependency-graph world matrices; original 65 bones; no .blend input or output; no Godot",
              "sources": [], "clips": []}
    try:
        result["sources"] = extract_four(archive, sources)
        for source in result["sources"]:
            summary = export_clip(source, output)
            result["clips"].append(summary)
            print("MIXAMO_REFERENCE_CLIP " + json.dumps(summary), flush=True)
        if arguments.compare_raw:
            rest = (raw_rest_reference(arguments.rest_sampler, result["sources"], output)
                    if arguments.rest_sampler else None)
            comparison = compare_raw_reference(arguments.compare_raw, result["clips"], output, rest)
            result["raw_comparison"] = {"file": str(output / "raw_comparison.json"),
                                        "sha256": digest(output / "raw_comparison.json"),
                                        "raw_reference": comparison["raw_reference"],
                                        "raw_reference_sha256": comparison["raw_reference_sha256"],
                                        "passed": comparison["passed"],
                                        "compared_bone_frames": comparison["compared_bone_frames"]}
            if rest:
                result["raw_comparison"]["rest_sampler"] = rest["sampler"]
                result["raw_comparison"]["rest_sampler_sha256"] = rest["sampler_sha256"]
                result["raw_comparison"]["rest_reference_sha256"] = digest(output / "raw_rest_reference.json")
    finally:
        after = archive_snapshot(archive)
        result["archive_after"] = after
        result["archive_unchanged"] = before == after
        if before != after:
            raise RuntimeError("Original archive changed while the reference was exported")
    write_json(output / "manifest.json", result, output)
    print("MIXAMO_REFERENCE_COMPLETE " + json.dumps(result["clips"]), flush=True)


if __name__ == "__main__":
    main()
