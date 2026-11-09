from pathlib import Path
import re
root=Path('review_artifacts/circuit_redesign_20261107/contextual_panels');scripts=list(root.glob('*.gd'))
assert len(scripts)==6
for p in scripts:
 s=p.read_text(encoding='utf-8-sig')
 for resource in re.findall(r'preload\("res://([^\"]+)"\)',s):assert Path(resource).is_file(),(p,resource)
 assert not re.search(r'FileAccess|DirAccess|\.rpc\b|authority_submit|\.save\(',s),p
assert 'Query.search_owned' in (root/'component_picker.gd').read_text()
assert 'if part.is_empty():hide();return' in (root/'selection_inspector.gd').read_text()
assert 'canvas.inspection_text()' in (root/'analyzer_panel.gd').read_text()
assert 'validate.call(index,raw,rows)' in (root/'bench_connections.gd').read_text()
print('Six private modules checked: resources resolve, no save/network calls, canonical query, contextual hide, real analyzer readout and mapping validator present')
