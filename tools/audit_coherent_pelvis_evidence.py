"""Audit scoped pelvis evidence; structural success never implies visual acceptance."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DIAGNOSTIC = re.compile(r'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:|WARNING:|Unicode parsing error')

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def fingerprint(path):
    stat = path.stat()
    return {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns}

def main():
    run_name = re.compile(r'pc-coherent-pelvis-real-(?:144|30|scale6)(?:-extended)?-(?:off|on|coherent)-v2\.json')
    runs = sorted(path for path in (ROOT / 'shots').glob('pc-coherent-pelvis-real-*-v2.json') if run_name.fullmatch(path.name))
    if len(runs) != 11:
        raise SystemExit(f'Expected 11 uncaptured real-input runs, found {len(runs)}')
    captured = ROOT / 'shots/pc-coherent-pelvis-real-144-on-v1.json'
    inputs = read(ROOT / '.tools/mixamo-loop-refined/report.json')['inputs_before']
    changed = []
    for item in inputs:
        actual = fingerprint(Path(item['path']))
        expected = {'sha256': item['sha256'], 'size': item['size_bytes'], 'mtime_ns': item['mtime_ns']}
        if actual != expected:
            changed.append({'path': item['path'], 'expected': expected, 'actual': actual})
    formal = read(ROOT / '.tools/mm-dataset-proposal/manifest.json')['production_before']
    formal_changed = [path for path, expected in formal.items() if fingerprint(ROOT / path) != expected]
    old = read(ROOT / 'shots/coherent-presentation-final-audit-v1.json')['files']
    frozen_old_changed = []
    for item in old:
        if item['path'] == 'scripts/characters/ink_avatar.gd':
            continue  # Explicit new mode wiring, never presented as unchanged.
        actual = fingerprint(ROOT / item['path'])
        if actual['sha256'] != item['sha256'] or actual['size'] != item['bytes']:
            frozen_old_changed.append(item['path'])
    contracts = [ROOT / 'shots/coherent-pelvis-contract-v1.json',
                 ROOT / 'shots/coherent-pelvis-contract-v2.json',
                 ROOT / 'shots/mac-coherent-pelvis-v1/output/coherent-pelvis-contract.json']
    logs = [ROOT / 'shots/coherent-pelvis-import-v1.log', ROOT / 'shots/coherent-pelvis-import-v1.log.stdout']
    for path in runs + [captured] + contracts[:2]:
        logs.extend([path.with_suffix('.log'), path.with_suffix('.log.stdout')])
    logs.extend(sorted((ROOT / 'shots/mac-coherent-pelvis-v1/logs').glob('*.log*')))
    hits = []
    for path in logs:
        for line, text in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
            if DIAGNOSTIC.search(text):
                hits.append({'path': str(path.relative_to(ROOT)), 'line': line, 'text': text})
    reports = []
    for path in runs + [captured]:
        record = read(path)
        if record['failures'] or record['accepted_for_production']:
            raise SystemExit(f'Unexpected structural/acceptance state: {path}')
        reports.append({'path': str(path.relative_to(ROOT)), 'sha256': fingerprint(path)['sha256'],
                        'checks': record['checks'], 'frames': record['sample_count'],
                        'physics_samples': record['physics_sample_count'], 'process_samples': record['process_sample_count'],
                        'synchronous_capture': record['synchronous_capture_requested'],
                        'capture_mismatches': record['physics_capture_mismatch_samples']})
    sources = ['scripts/characters/ink_avatar.gd', 'scripts/animation/ink_pose_presentation.gd',
               'scripts/animation/experiments/ink_coherent_pelvis_presentation.gd',
               'tools/verify_coherent_pelvis_presentation.gd', 'tools/verify_locomotion_pelvis_real_chain.gd',
               'tools/locomotion_pelvis_physics_observer.gd', 'tools/analyze_locomotion_pelvis_real_chain.py',
               'tools/run_macos_coherent_pelvis_presentation.sh', 'tools/package_coherent_pelvis_qa.py',
               'tools/audit_coherent_pelvis_evidence.py', 'docs/coherent-pelvis-locomotion.md',
               '.tools/coherent-pelvis-presentation/independent-review.md',
               '.tools/coherent-pelvis-presentation/next-design.md']
    record = {'diagnostic_only': True, 'accepted_for_production': False, 'default_enabled': False,
              'exported_build_verified': False, 'new_mixamo_database_selected': False,
              'qualified_logs': len(logs), 'diagnostic_hits': hits,
              'read_only_inputs_count': len(inputs), 'read_only_inputs_changed': changed,
              'formal_matcher_and_database_changed': formal_changed, 'frozen_previous_evidence_changed': frozen_old_changed,
              'real_input_reports': reports, 'uncaptured_real_input_checks': sum(r['checks'] for r in reports if not r['synchronous_capture']),
              'captured_real_input_checks': sum(r['checks'] for r in reports if r['synchronous_capture']),
              'contracts': [{'path': str(path.relative_to(ROOT)), 'sha256': fingerprint(path)['sha256'], 'report': read(path)} for path in contracts],
              'current_sources': [{'path': path, **fingerprint(ROOT / path)} for path in sources],
              'limitations': ['Rig-space upper preservation changes source parent links; not accepted.',
                              'Late process and post-draw observation times do not measure display presents.',
                              'Captured run includes synchronous screenshot stalls; separate from timing controls.',
                              'Mac headless imported-rig authority only; no Mac GPU real-input acceptance.']}
    if hits or changed or formal_changed or frozen_old_changed:
        raise SystemExit(json.dumps({'hits': hits, 'inputs_changed': changed, 'formal_changed': formal_changed, 'frozen_changed': frozen_old_changed}))
    for path in contracts:
        if read(path)['failures'] or read(path)['accepted_for_production']:
            raise SystemExit('Unexpected imported contract state')
    output = ROOT / 'shots/coherent-pelvis-final-audit-v1.json'
    output.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: record[key] for key in ['qualified_logs', 'read_only_inputs_count', 'uncaptured_real_input_checks', 'captured_real_input_checks', 'accepted_for_production']}))

if __name__ == '__main__':
    main()
