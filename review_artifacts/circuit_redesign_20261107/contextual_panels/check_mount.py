from pathlib import Path
import json,hashlib
base=Path('review_artifacts/circuit_redesign_20261107/contextual_panels');data=json.loads((base/'CORE_WORKSPACE_MOUNT.json').read_text())
raw=Path(data['path']).read_bytes()
assert hashlib.sha256(raw).hexdigest()==data['sha256']
s=raw.decode('utf-8-sig').replace('\r\n','\n')
assert s.count(data['old'])==1
assert hashlib.sha256(s.replace(data['old'],data['new'],1).encode()).hexdigest()==data['normalized_after_sha256']
for name in ['component_picker','selection_inspector','analyzer_panel','bench_connections','status_help','panel_host']:
 assert (base/(name+'.gd')).is_file()
print('Private mount patch preimage verified; six modules present; no core/live writes')
