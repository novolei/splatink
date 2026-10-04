"""Freeze the narrow diagnostic overlay; does not export or modify references."""
from __future__ import annotations

import gzip
import argparse
import hashlib
import io
import json
import tarfile
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", choices=["v2", "v3"], default="v2")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    target = project / ".tools/mm-discriminative"
    target.mkdir(parents=True, exist_ok=True)
    archive = target / f"20261004-candidate-{args.revision}.tar.gz"
    manifest = target / f"20261004-candidate-{args.revision}.json"
    if archive.exists() or manifest.exists():
        raise SystemExit("Frozen candidate already exists; use a new explicit revision")
    names = ["tools/.gdignore", "scripts/animation/ink_motion_matcher.gd",
             "tools/verify_mm_discriminative_hysteresis.gd",
             "tools/mm_discriminative_hysteresis_fixture.gd"]
    files = []
    with archive.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as bundle:
            for name in names:
                data = (project / name).read_bytes()
                item = tarfile.TarInfo(name)
                item.size = len(data)
                item.mtime = 0
                item.mode = 0o644
                bundle.addfile(item, io.BytesIO(data))
                files.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    unchanged = ["assets/animation/locomotion.features.bin",
                 "addons/motion_matching/bin/macos/libgdmotionmatching.macos.template_debug.splatlower1.dylib",
                 "addons/motion_matching/bin/macos/libgdmotionmatching.macos.template_release.splatlower1.dylib"]
    record = {"diagnostic_only": True, "accepted_for_production": False,
              "archive_sha256": digest(archive), "archive_bytes": archive.stat().st_size,
              "files": files, "unchanged_base": [{"path": name, "sha256": digest(project / name)} for name in unchanged]}
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps({"archive": str(archive), "bytes": record["archive_bytes"],
                      "sha256": record["archive_sha256"], "files": len(files)}))


if __name__ == "__main__":
    main()
