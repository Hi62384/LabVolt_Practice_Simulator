from pathlib import Path
import hashlib,json,re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=HERE/'assembled'
manifest=json.loads((HERE/'ASSEMBLED_MANIFEST.json').read_text(encoding='utf-8'))
for item in manifest['production_preimages']:
    assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['preimage_sha256'], item['path']
def balanced(text,path):
    stack=[];quote=None;escape=False;comment=False
    for ch in text:
        if comment:
            if ch=='\n':comment=False
            continue
        if quote:
            if escape:escape=False
            elif ch=='\\':escape=True
            elif ch==quote:quote=None
        elif ch=='#':comment=True
        elif ch in ['"',"'"]:quote=ch
        elif ch in '([{':stack.append(ch)
        elif ch in ')]}':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[ch],path
    assert not stack and quote is None,path
for item in manifest['files']:
    path=OUT/item['target'];assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],path
    text=path.read_text(encoding='utf-8');balanced(text,path)
    assert 'res://review_artifacts/' not in text,path
    for resource in re.findall(r'(?:preload|extends)\(?"res://([^"\n]+)"',text):
        assert (OUT/resource).exists() or (ROOT/resource).exists(),(path,resource)
adapter=(OUT/'scripts/electronics/circuit_workspace/host_adapter.gd').read_text(encoding='utf-8')
for callback in ['record_instance','validate_property','apply_property','validate_port','apply_port','open_projects']:
    assert '"'+callback+'":' in adapter,callback
assert adapter.count('panels.configure(')==1
assert 'workspace.canvas.add_child(panels)' in adapter
assert 'host.wire_io_canvas(host.canvas)' in adapter
assert 'host.canvas.board=candidate.duplicate(true)' in adapter
mount=(OUT/'scripts/electronics/circuit_workspace/package_mount.gd').read_text(encoding='utf-8')
for operation in ['editor.open_project(', 'host.open_pcb_routing(', 'host.profile.obtain_ic(', 'editor.preview.selected.connect(', 'editor.model.draft.exposed=', 'host.profile.data=previous']:
    assert operation in mount,operation
model=(OUT/'scripts/electronics/ic_pcb_editor/package_pin_model.gd').read_text(encoding='utf-8')
assert 'draft.footprint=old_foot;' not in model and 'draft.footprint=old_footprint;' in model
assert 'package_store.gd' in model
ui=(OUT/'scripts/electronics_ui.gd').read_text(encoding='utf-8')
assert 'adapter.mount(self)' in ui and 'package_mount.gd' in ui
assert '"board","design","ics"' in ui
builder=(OUT/'scripts/campus/facilities/circuit_studio/builder_window.gd').read_text(encoding='utf-8')
assert 'package_mount.gd' in builder and 'if str(blueprint.get("package","IC"))!=kind' not in builder # filtering belongs to adapter
assert 'if str(bp.get("package","IC"))!=kind:continue' in mount
report=f'PASS: {len(manifest["files"])} exact assembled files; 3 unchanged live preimages; local resource closure; balanced delimiters; single panel mount; required real callbacks; board/IC/PCB entry paths; package rollback correction; type-filtered saved projects. No engine parse, fixture execution or screenshots.\n'
(HERE/'ASSEMBLED_VALIDATION.txt').write_text(report,encoding='utf-8');print(report)
