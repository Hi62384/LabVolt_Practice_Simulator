"""Optional exact-preimage rollback; refuses any unknown current source revision."""
from pathlib import Path
import hashlib, json
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
entries=json.loads((HERE/'manifest.json').read_text())
for entry in entries:
    path=entry['path']
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==entry['after_sha256'], f'Unknown current edit: {path}'
    assert hashlib.sha256((HERE/'preimages'/path).read_bytes()).hexdigest()==entry['before_sha256'], f'Unknown preimage: {path}'
for entry in entries:
    (ROOT/entry['path']).write_bytes((HERE/'preimages'/entry['path']).read_bytes())
print('Restored the five assigned source preimages. Additive helper and review evidence retained.')
