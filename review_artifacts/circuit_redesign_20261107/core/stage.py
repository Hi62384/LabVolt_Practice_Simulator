"""Generate exact-preimage review artifacts. Never modifies production."""
from pathlib import Path
import hashlib,json,difflib
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
records=[]
for name in ['electronics_ui','breadboard_canvas']:
    path=ROOT/'scripts'/f'{name}.gd'
    data=path.read_bytes()
    snapshot=HERE/f'{name}.preimage.gd'
    assert snapshot.read_bytes()==data, f'Current source changed: {path}; rebase required'
    old=data.decode().replace('\r\n','\n')
    new=old
    if name=='electronics_ui':
        start=new.index('func breadboard() -> void:')
        end=new.index('func deploy() -> void:',start)
        new=new[:start]+'''func breadboard() -> void:
	var adapter=preload("res://scripts/electronics/circuit_workspace/host_adapter.gd").new()
	var workspace: Control=adapter.mount(self)
	workspace.set_meta("host_adapter",adapter)

'''+new[end:]
        needle='body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)'
        assert new.count(needle)==1
        new=new.replace(needle,needle+'''
	if page in ["board","design"]:
		scroll.remove_child(body);column.remove_child(scroll);scroll.queue_free();page_scroll=null
		body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
		title.text="Circuit workspace";status.hide()
'''.rstrip())
        # Existing scroll restoration already guards invalid page_scroll; preserve it.
    else:
        needle='timing_visible=value;custom_minimum_size.y=590 if value else 500'
        assert new.count(needle)==1
        new=new.replace(needle,'timing_visible=value\n\t\tif not get_meta("workspace_embedded",false):custom_minimum_size.y=590 if value else 500')
    output=new.replace('\n','\r\n').encode()
    (HERE/f'{name}.candidate.gd').write_bytes(output)
    (HERE/f'{name}.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile=f'a/scripts/{name}.gd',tofile=f'b/scripts/{name}.gd')),encoding='utf-8')
    records.append({'path':f'scripts/{name}.gd','preimage_sha256':hashlib.sha256(data).hexdigest(),'candidate_sha256':hashlib.sha256(output).hexdigest()})
(HERE/'INTEGRATION.json').write_text(json.dumps(records,indent=2)+'\n')
print('Staged two exact-preimage patches; production untouched.')
