from pathlib import Path
root=Path('review_artifacts/m203_computer_classroom_20261107/sessions')
p=root/'network_fixture.gd';s=p.read_text();s=s.replace('var activity := {}','''var activity := {}
	var phase := "freeplay"
	var submissions := 0
	func _public_project(project: Dictionary, _marked: bool=false) -> Dictionary:
		var copy := project.duplicate(true)
		copy.erase("answer_key")
		return copy
	func apply(peer: int, action: Dictionary) -> void:
		var paper: Dictionary=papers.get(action.id,{})
		if paper.get("owner",0)!=peer or not paper.mark.is_empty():return
		if action.op=="submit":
			submissions+=1
			paper.mark={"score":1}
		elif action.op=="answer":paper.answers[str(action.key)]=action.value''');p.write_text(s)
p=root/'test_lifecycle.gd';s=p.read_text();s=s.replace('\tvar old_lease:', '''	game.school.activity={"kind":"lecture"}
	game.school.papers[42]={"id":42,"owner":2,"project":{"title":"Existing assignment","questions":[],"answer_key":"secret"},"answers":{},"mark":{},"lesson":false}
	action(3,"submit",{"paper":42})
	assert(game.school.submissions==0)
	action(2,"submit",{"paper":42})
	action(2,"submit",{"paper":42})
	assert(game.school.submissions==1)
	action(2,"rename",{"path":"answer.txt","new_path":"renamed.txt"})
	assert(manager.workspaces[2].files.has("renamed.txt"))
	action(2,"rename",{"path":"renamed.txt","new_path":"answer.txt"})
	var old_lease:''');p.write_text(s)
p=root/'computer_sessions.gd';s=p.read_text();s=s.replace('or workspace.files.has(target):','or workspace.files.has(target) or int(workspace.files.get(source,{}).get("version",0))>=2147483646:');p.write_text(s)
# exact preimage edits for main, including all shared assembly points
import json,hashlib
base=Path.cwd()
patches=[]
for rel,edits in [
('scripts/game.gd',[
('var school: Node','var school: Node\nvar computers: Node\nvar computer_room_adapter: Node'),
('\tschool.build(self)','\tschool.build(self)\n\tcomputers=preload("res://scripts/campus/computers/computer_sessions.gd").new()\n\tcomputers.name="ComputerSessions"\n\tadd_child(computers)\n\tcomputers.build(self)'),
('func _input(event: InputEvent) -> void:','func _input(event: InputEvent) -> void:\n\tif is_instance_valid(computer_room_adapter) and computer_room_adapter.route_event(event):return'),
('func activate() -> void:','func activate() -> void:\n\tif is_instance_valid(computer_room_adapter) and computer_room_adapter.interact(current_target):return'),
('\t\telif role=="teacher":','\t\telif role=="computer":\n\t\t\thint="E / click: use classroom computer"\n\t\telif role=="teacher":')]),
('scripts/campus_integration.gd',[
('var service_decor: Node3D','var service_decor: Node3D\nvar m203_room: Node3D'),
('\troom_finish_results.m103=m103_finish.mount(game.campus,game.campus.registry)', '\troom_finish_results.m103=m103_finish.mount(game.campus,game.campus.registry)\n\tm203_room=preload("res://scripts/campus/presentation/decor/computer_rooms/m203_room.gd").new()\n\tadd_child(m203_room)\n\troom_finish_results.m203=m203_room.mount(game.campus,game.campus.registry)\n\tif room_finish_results.m203:\n\t\tgame.computer_room_adapter=preload("res://scripts/campus/computers/classroom_adapter.gd").new()\n\t\tgame.computer_room_adapter.name="ComputerClassroomAdapter"\n\t\tgame.add_child(game.computer_room_adapter)\n\t\tif not game.computer_room_adapter.build(game,m203_room):push_error("M203 station integration failed")')])]:
    data=(base/rel).read_bytes();text=data.decode('utf-8-sig')
    for old,new in edits: assert text.count(old)==1,(rel,old)
    (root/(rel.replace('/','__')+'.preimage')).write_bytes(data)
    patches.append({'path':rel,'preimage_sha256':hashlib.sha256(data).hexdigest(),'edits':[{'old':a,'new':b} for a,b in edits]})
(root/'assembly_shared_patches.json').write_text(json.dumps(patches,indent=2)+'\n')
print('Staged full assembly patches; production files unchanged')
