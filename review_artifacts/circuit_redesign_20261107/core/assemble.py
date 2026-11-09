"""Build one private install tree and bound shared candidates; no production writes."""
from pathlib import Path
import hashlib,json,difflib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=HERE/'assembled'
manifest=[]
def emit(target,data,origin):
    path=OUT/target;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    manifest.append({'target':target,'origin':origin,'sha256':hashlib.sha256(data).hexdigest()})
for source_group,target_group in [(HERE/'modules','circuit_workspace'),(HERE.parent/'contextual_panels','contextual_panels'),(HERE.parent/'ic_pcb_editor/modules','ic_pcb_editor')]:
    for path in sorted(source_group.glob('*.gd')):
        text=path.read_text(encoding='utf-8').replace('res://review_artifacts/circuit_redesign_20261107/ic_pcb_editor/modules/','res://scripts/electronics/ic_pcb_editor/')
        if path.name=='package_pin_model.gd':
            assert 'draft.footprint=old_foot;' in text
            text=text.replace('draft.footprint=old_foot;','draft.footprint=old_footprint;')
            text=text.replace('func save(profile: RefCounted) -> String:\n','func save(profile: RefCounted) -> String:\n\tif profile.data.kits[profile.data.equipped].board!=design:return "Source circuit changed; reopen the package editor before saving."\n')
        if path.name=='package_editor.gd':
            needle='inspector=VBoxContainer.new();inspector.custom_minimum_size.x=260;split.add_child(inspector)'
            assert text.count(needle)==1
            text=text.replace(needle,'var inspector_scroll:=ScrollContainer.new();inspector_scroll.custom_minimum_size.x=280;inspector_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;split.add_child(inspector_scroll)\n\tinspector=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector_scroll.add_child(inspector)')
        emit(f'scripts/electronics/{target_group}/{path.name}',text.encode(),str(path.relative_to(ROOT)))

records=json.loads((HERE/'INTEGRATION.json').read_text())
for record in records:
    target=record['path'];source=ROOT/target;old=source.read_bytes()
    assert hashlib.sha256(old).hexdigest()==record['preimage_sha256'],f'Rebase required: {target}'
    text=(HERE/(source.stem+'.candidate.gd')).read_text(encoding='utf-8')
    if source.stem=='electronics_ui':
        start=text.index('func custom_ics() -> void:');end=text.index('func view_path()',start)
        text=text[:start]+'''func custom_ics() -> void:
	var draft: Dictionary=profile.data.kits[profile.data.equipped].get("package_draft",{}).duplicate(true)
	var kind: String=str(draft.get("package","IC"))
	preload("res://scripts/electronics/circuit_workspace/package_mount.gd").mount(self,body,kind,draft)

'''+text[end:]
        text=text.replace('if page in ["board","design"]:', 'if page in ["board","design","ics"]:')
    data=text.replace('\n','\r\n').encode()
    emit(target,data,'core exact-preimage candidate')
    (HERE/(source.stem+'.assembled.patch')).write_text(''.join(difflib.unified_diff(old.decode().replace('\r\n','\n').splitlines(True),text.splitlines(True),fromfile='a/'+target,tofile='b/'+target)),encoding='utf-8')

target='scripts/campus/facilities/circuit_studio/builder_window.gd'
source=ROOT/target;old=source.read_bytes();text=old.decode().replace('\r\n','\n')
(HERE/'builder_window.preimage.gd').write_bytes(old)
start=text.index('func _rebuild(');end=text.index('func _edit_board(',start)
text=text[:start]+'''func _rebuild(message: String="") -> void:
	for child in get_children():remove_child(child);child.queue_free()
	content=VBoxContainer.new();content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(content)
	var tools:=HFlowContainer.new();content.add_child(tools)
	_button(tools,"Close workstation",_close)
	notice=Label.new();notice.text=message;content.add_child(notice)
	if not game.electronics.profile.data.get("pending_trade",{}).is_empty():notice.text="Finish the pending trade before editing circuit packages.";return
	var profile=game.electronics.profile
	var draft: Dictionary=profile.data.kits[profile.data.equipped].get("package_draft",{}).duplicate(true)
	if str(draft.get("package",kind))!=kind:draft={}
	draft.package=kind
	var editor: Control=preload("res://scripts/electronics/circuit_workspace/package_mount.gd").mount(game.electronics,content,kind,draft,func():hide();queue_free())
	editor.saved.connect(func(result):notice.text=result)

'''+text[end:]
emit(target,text.replace('\n','\r\n').encode(),'builder_window exact preimage')
(HERE/'builder_window.assembled.patch').write_text(''.join(difflib.unified_diff(old.decode().replace('\r\n','\n').splitlines(True),text.splitlines(True),fromfile='a/'+target,tofile='b/'+target)),encoding='utf-8')
records.append({'path':target,'preimage_sha256':hashlib.sha256(old).hexdigest()})
for source,target in [(HERE/'model_fixture.gd','tests/circuit_redesign/core_model_fixture.gd'),(HERE.parent/'ic_pcb_editor/tests/package_model_fixture.gd','tests/circuit_redesign/package_model_fixture.gd')]:
    text=source.read_text(encoding='utf-8').replace('res://review_artifacts/circuit_redesign_20261107/ic_pcb_editor/modules/','res://scripts/electronics/ic_pcb_editor/')
    emit(target,text.encode(),str(source.relative_to(ROOT)))
(HERE/'ASSEMBLED_MANIFEST.json').write_text(json.dumps({'production_preimages':records,'files':manifest},indent=2)+'\n',encoding='utf-8')
print(f'Assembled {len(manifest)} exact files privately; 3 production patches bound to preimages.')
