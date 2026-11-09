"""Restore only owned existing files, refusing unknown concurrent edits."""
from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parents[3]
entries=json.loads((root/'scripts/ui/hud_settings/review/manifest.json').read_text())
for entry in entries:
    current=(root/entry['path']).read_bytes()
    before=(root/entry['preimage']).read_bytes()
    assert hashlib.sha256(current).hexdigest()==entry['after'], 'Refusing unknown changes: '+entry['path']
    assert hashlib.sha256(before).hexdigest()==entry['before'], 'Preimage checksum mismatch: '+entry['path']
if '--apply' not in sys.argv:
    print('All 8 source files match the redesign. Pass --apply to restore exact preimages; additive helpers stay available.')
    sys.exit()
for entry in entries:
    path=root/entry['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['after'], 'Concurrent change: '+entry['path']
    path.write_bytes((root/entry['preimage']).read_bytes())
print('Restored exact preimages for 8 owned source files.')
