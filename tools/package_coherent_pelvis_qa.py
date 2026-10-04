"""Freeze the explicit pelvis authority fixture for an isolated Mac QA stage."""
from pathlib import Path
import hashlib
import io
import json
import tarfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / '.tools/coherent-pelvis-presentation-macos'
NAME = '20261004-coherent-pelvis-v1'
FILES = [
    'tools/.gdignore',
    'tools/verify_coherent_pelvis_presentation.gd',
    'scripts/characters/ink_avatar.gd',
    'scripts/animation/ink_pose_presentation.gd',
    'scripts/animation/experiments/ink_coherent_pelvis_presentation.gd',
]

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
            inventory.append({'path': relative, 'bytes': len(data),
                              'sha256': hashlib.sha256(data).hexdigest()})
    previous = json.loads((ROOT / '.tools/coherent-presentation-macos/20261004-coherent-presentation-v3.json').read_text(encoding='utf-8'))
    data = archive.read_bytes()
    record = {'experimental': True, 'default_enabled': False,
              'accepted_for_production': False, 'files': inventory,
              'unchanged_base': previous['unchanged_base'],
              'purpose': 'coherent pelvis exact restore/authority, with source-link deformation explicitly reported; no quality acceptance',
              'archive_sha256': hashlib.sha256(data).hexdigest(), 'archive_bytes': len(data)}
    manifest.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'manifest': str(manifest), 'archive_bytes': len(data),
                      'archive_sha256': record['archive_sha256']}))

if __name__ == '__main__':
    main()
