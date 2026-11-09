"""Bounded source and contract checks only; no Godot launch or game writes."""
from pathlib import Path
import hashlib,re,json
root=Path(__file__).resolve().parents[3];here=Path(__file__).resolve().parent
files=['catalog.gd','session.gd','projection.gd','target_resolver.gd','formal_guide_policy.gd','fixture.gd','controller.gd']
for name in files:
 text=(here/name).read_text(encoding='utf-8')
 for resource in re.findall(r'preload\("res://([^"]+)"\)',text):assert (root/resource).is_file(),resource
assert '"ac_lab":"ELM253"' in (here/'catalog.gd').read_text()
assert '"dc_lab":"ETY155"' in (here/'catalog.gd').read_text()
assert 'event.get("accepted",false)' in (here/'session.gd').read_text()
assert 'event.get("peer_id",-1)' in (here/'session.gd').read_text()
assert 'activity.get("kind","")' in (here/'formal_guide_policy.gd').read_text()
assert 'activity.get("mode","")' in (here/'formal_guide_policy.gd').read_text()
assert 'material_override' not in (here/'projection.gd').read_text()
assert 'set_meta' not in (here/'projection.gd').read_text()
controller=(here/'controller.gd').read_text(encoding='utf-8')
assert 'registry.call("locate",game.player.global_position)' in controller
assert 'game.release_mouse()' in controller and 'game.capture()' in controller
assert 'if not _intent_applied(' in controller and 'int(after.get("revision",-1))<=int(before.get("revision",-1))' in controller
assert 'event.keycode==KEY_F6' in controller
catalog=(here/'catalog.gd').read_text(encoding='utf-8')
assert catalog.split('static func _dc()',1)[1].split('static func _ac()',1)[0].count('_device(')==7
assert catalog.split('static func _ac()',1)[1].count('_device(')==11
dc_ports=json.loads((root/'review_artifacts/m103_dc_rebuild_20261107/physical_models/ports.json').read_text(encoding='utf-8'))
actual_ports={row['id'] for row in dc_ports['ports']}
for cue in re.findall(r'_step\([^\n]*?,"([^"]+)"',catalog.split('static func _dc()',1)[1].split('static func _ac()',1)[0]):
 if cue in ['psu','meter','generator','scope_trace']:continue
 assert cue in actual_ports or cue in ['psu_ch1_voltage','psu_ch1_limit','psu_ch1_enable','psu_master','meter_mode','generator_wave','generator_output','scope_timebase','scope_ch1_scale','is1_enable'],cue
school=(root/'scripts/school_session.gd');paper=(root/'scripts/paper_ui.gd')
school_text=school.read_text(encoding='utf-8');paper_text=paper.read_text(encoding='utf-8')
old_school='\telif op=="guide":\n\t\tif not _near(peer,teacher_position):return'
new_school='\telif op=="guide":\n\t\tif not preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/formal_guide_policy.gd").allowed(mode,activity):return\n\t\tif not _near(peer,teacher_position):return'
old_paper='\t\t_button(column,"Equipment guide",func():school.request({"op":"guide"});close())'
new_paper='\t\tif preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/formal_guide_policy.gd").allowed(school.mode,assigned):_button(column,"Equipment guide",func():school.request({"op":"guide"});close())'
assert old_school in school_text and old_paper in paper_text
patches=[]
for path,old,new in [(school,old_school,new_school),(paper,old_paper,new_paper)]:
 patches.append({'file':str(path.relative_to(root)).replace('\\','/'),'preimage_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'old':old,'new':new})
(here/'formal_class_patches.json').write_text(json.dumps(patches,indent=2)+'\n',encoding='utf-8')
report={'files':{name:hashlib.sha256((here/name).read_bytes()).hexdigest() for name in files},'formal_patches':2,'runtime':'Fixture authored; not run in Godot','scope':'Open Lab tutorial only; lecture guide hidden and server-rejected; lab class guide retained.'}
hooks=json.loads((here/'game_hooks.json').read_text(encoding='utf-8'))
for hook in hooks:
 path=root/hook['file']
 assert hashlib.sha256(path.read_bytes()).hexdigest()==hook['preimage_sha256'],'Shared source changed: '+hook['file']
 for edit in hook['edits']:assert path.read_text(encoding='utf-8').count(edit['old'])==1
(here/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('Tutorial source checks passed; 2 preimage-pinned formal guide patches staged. Godot fixture not run.')
