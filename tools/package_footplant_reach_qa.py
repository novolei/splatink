"""Freeze only the explicit imported-rig FootPlant contract for Mac QA."""
from pathlib import Path
import hashlib
import io
import json
import tarfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / '.tools/footplant-continuous-reach-macos'
NAME = '20261004-footplant-reach-v1'
FILES = ['tools/.gdignore', 'tools/verify_footplant_reach_contract.gd',
         'scripts/characters/ink_avatar.gd',
         'scripts/animation/experiments/ink_foot_plant_continuous_reach.gd']
BASE = ['scripts/animation/ink_foot_plant.gd', 'scripts/animation/ink_inertializer.gd',
        'scripts/animation/ink_motion_matcher.gd', 'scripts/animation/native_motion_matcher.gd',
        'data/motion_matching.json', 'assets/animation/locomotion.features.bin',
        'assets/animation/locomotion.poses.bin', 'assets/characters/body.glb']

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    archive = DEST / (NAME + '.tar.gz')
    manifest = DEST / (NAME + '.json')
    if archive.exists() or manifest.exists():
        raise SystemExit('Frozen package already exists; use a fresh revision')
    inventory = []
    with tarfile.open(archive, 'w:gz') as target:
        for relative in FILES:
            data = (ROOT / relative).read_bytes()
            info = tarfile.TarInfo(relative)
            info.size = len(data)
            info.mtime = 0
            info.mode = 0o644
            target.addfile(info, io.BytesIO(data))
            inventory.append({'path': relative, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    unchanged = [{'path': path, 'sha256': hashlib.sha256((ROOT / path).read_bytes()).hexdigest()} for path in BASE]
    data = archive.read_bytes()
    record = {'experimental': True, 'default_enabled': False, 'accepted_for_production': False,
              'files': inventory, 'unchanged_base': unchanged,
              'purpose': 'original/trace exact parity and continuous raw link invariants; no motion quality acceptance',
              'archive_sha256': hashlib.sha256(data).hexdigest(), 'archive_bytes': len(data)}
    manifest.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'archive_bytes': len(data), 'archive_sha256': record['archive_sha256']}))

if __name__ == '__main__':
    main()
