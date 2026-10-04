"""Freeze an experiment-only Mac diagnostic overlay. Never exports a game."""
from __future__ import annotations
import gzip
import hashlib
import io
import json
import tarfile
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    folder = project / ".tools/mixamo-loop-prototype"
    archive = folder / "20261004-candidate-v3.tar.gz"
    manifest = folder / "20261004-candidate-v3.json"
    if archive.exists() or manifest.exists():
        raise SystemExit("Frozen candidate exists; use a new explicit revision")
    resources = sorted((project / "assets/animation/experiments/mixamo_loops").glob("*.tres"))
    if len(resources) != 18:
        raise SystemExit("Expected exactly 18 loop resources")
    names = ["tools/.gdignore", "tools/mixamo_loop_retarget.py",
             "tools/verify_mixamo_loops.gd", "tools/mixamo_loop_fixture.gd",
             "scripts/animation/experiments/mixamo_loop_prototype.gd",
             "assets/animation/experiments/mixamo_loops/loops.json",
             "assets/animation/experiments/mixamo_loops/provenance.json"]
    names += [path.relative_to(project).as_posix() for path in resources]
    files = []
    with archive.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as bundle:
            for name in names:
                path = project / name
                if path.is_symlink() or not path.resolve().is_relative_to(project.resolve()):
                    raise SystemExit("Unsafe overlay member")
                payload = path.read_bytes()
                member = tarfile.TarInfo(name)
                member.size = len(payload)
                member.mtime = 0
                member.mode = 0o644
                bundle.addfile(member, io.BytesIO(payload))
                files.append({"path": name, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
    base = ["assets/characters/body.glb", "assets/animation/locomotion.features.bin",
            "scripts/animation/ink_motion_matcher.gd",
            "addons/motion_matching/bin/macos/libgdmotionmatching.macos.template_debug.splatlower1.dylib",
            "addons/motion_matching/bin/macos/libgdmotionmatching.macos.template_release.splatlower1.dylib"]
    record = {"diagnostic_only": True, "accepted_for_production": False,
              "archive_sha256": digest(archive), "archive_bytes": archive.stat().st_size,
              "files": files, "unchanged_base": [{"path": name, "sha256": digest(project / name)} for name in base]}
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps({"archive": str(archive), "bytes": record["archive_bytes"],
                      "sha256": record["archive_sha256"], "files": len(files)}))


if __name__ == "__main__":
    main()
