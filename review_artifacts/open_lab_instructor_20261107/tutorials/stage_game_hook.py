"""Stages exact-preimage patches only. Does not edit production."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[3];here=Path(__file__).resolve().parent
game=root/'scripts/game.gd';dc=root/'scripts/dc_lab.gd'
g=game.read_text(encoding='utf-8');d=dc.read_text(encoding='utf-8')
game_anchor='var cable_obstacles:Array[AABB]=[]'
game_intent='\taction["station"]=number\n\tsession.request(action)'
dc_intent='\tif multiplayer.is_server():accept(1,index,action)\n\telse:command.rpc_id(1,index,action)'
assert game_anchor in g and game_intent in g and dc_intent in d
hook='''var open_lab_tutorial

'''
method='''func open_lab_equipment_tutorial() -> void:
	if not is_instance_valid(open_lab_tutorial):
		open_lab_tutorial=preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/controller.gd").new()
		add_child(open_lab_tutorial)
	if not open_lab_tutorial.open(self):
		ui.log_message("Equipment tutorial is available in the M101 or M103 Open Lab.")

'''
patches=[
 {'file':'scripts/game.gd','preimage_sha256':hashlib.sha256(game.read_bytes()).hexdigest(),'edits':[
  {'old':game_anchor,'new':hook+game_anchor},
  {'old':'func _ready() -> void:','new':method+'func _ready() -> void:'},
  {'old':game_intent,'new':'\taction["station"]=number\n\tif is_instance_valid(open_lab_tutorial):open_lab_tutorial.record_intent("ac_lab",number,action)\n\tsession.request(action)'}]},
 {'file':'scripts/dc_lab.gd','preimage_sha256':hashlib.sha256(dc.read_bytes()).hexdigest(),'edits':[
  {'old':dc_intent,'new':'\tif is_instance_valid(game.open_lab_tutorial):game.open_lab_tutorial.record_intent("dc_lab",index,action)\n'+dc_intent}]}]
for patch,source in [(patches[0],g),(patches[1],d)]:
 for edit in patch['edits']:assert source.count(edit['old'])==1,(patch['file'],edit['old'])
(here/'game_hooks.json').write_text(json.dumps(patches,indent=2)+'\n',encoding='utf-8')
print('Staged game.open_lab_equipment_tutorial and AC/DC intent hooks against current exact preimages.')
