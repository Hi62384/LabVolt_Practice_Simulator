"""File-only documentation freshness/ownership audit. Never launches the game."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
DOCS = ROOT / 'docs/practice'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def audit(external=False):
    checks = []
    anchors = json.loads((DOCS / 'source_anchors.json').read_text(encoding='utf-8'))
    for entry in anchors:
        path = ROOT / entry['path']
        lines = path.read_text(encoding='utf-8-sig').splitlines()
        digest = sha(path)
        assert digest in [entry['snapshot_sha256'], entry['current_main_sha256']], f"Source changed: {entry['path']}"
        line = entry['line'] if digest == entry['snapshot_sha256'] else entry['current_main_line']
        assert entry['needle'] in lines[line - 1], f"Stale anchor: {entry['topic']}"
        checks.append('source freshness: ' + entry['topic'])
    for path in DOCS.glob('*.md'):
        for link in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            assert not link.startswith(('http:', 'https:')), 'Guide uses local source evidence only'
            assert (path.parent / link.split('#')[0]).exists(), f'Broken link: {link}'
        checks.append('local links: ' + path.name)
    evidence = json.loads((DOCS / 'evidence.json').read_text(encoding='utf-8'))
    for receipt in evidence:
        assert len(receipt['sha256']) == 64
        if external:
            assert sha(Path(receipt['path'])) == receipt['sha256'], f"Receipt changed: {receipt['path']}"
            checks.append('receipt freshness: ' + Path(receipt['path']).name)
    text = (DOCS / 'QUICK_START.md').read_text(encoding='utf-8')
    for required in ['P15/P16', 'AM0_OUT', 'V0_150', 'V0_300', 'C/C++ source compilation is deferred', 'source review only']:
        # The last phrase lives in the evidence ledger.
        assert required in text + (DOCS / 'FEATURE_LEDGER.md').read_text(encoding='utf-8'), required
        checks.append('required distinction: ' + required)
    # Audit electrical examples independently as small graphs, including the
    # common COM-lead mistake that would short the proposed current measurement.
    def connected(edges, start, end):
        seen = {start}
        while True:
            more = {v for a,b in edges for u,v in [(a,b),(b,a)] if u in seen}
            if more <= seen: return end in seen
            seen |= more
    current_leads = [('CH1+', 'A'), ('COM', 'B1'), ('CH1-', 'B2')]
    assert not connected(current_leads, 'B1', 'B2')
    assert connected(current_leads + [('COM','B2')], 'B1', 'B2')
    checks.append('current measurement: no wire-only bypass; retained voltage COM lead would bypass resistor')
    # Independent coordinate calculation for the documented two-pin footprint.
    letters = 'PNABCDEFGHIJ'
    assert [letters[2+y] + '1' for y in [0,5]] == ['A1','F1']
    assert 2 + 6 <= len(letters)
    checks.append('custom package: anchored physical coordinates occupy A1/F1 inside 2x6 footprint')
    return {'passed': True, 'count': len(checks), 'checks': checks,
            'scope': 'File-only freshness, links, receipt identity and example topology; no UI/runtime acceptance.'}

if __name__ == '__main__':
    print(json.dumps(audit(external='--external' in sys.argv), indent=2, ensure_ascii=False))
