extends SceneTree
const Manager = preload("res://scripts/campus/computers/computer_sessions.gd")
const Fixture = preload("res://tests/campus/computers/network_fixture.gd")
var manager: Node
var game: Node
func _initialize() -> void:call_deferred("exercise")
func action(peer: int, op: String, extra: Dictionary = {}) -> void:
	manager.last_request.erase(peer)
	var packet := {"op":op,"lease":manager.sessions[peer].lease,"revision":manager.sessions[peer].revision}
	packet.merge(extra,true)
	manager._accept(peer,packet)
func exercise() -> void:
	game=Fixture.GameDouble.new()
	root.add_child(game)
	game.session=Fixture.SessionDouble.new()
	game.school=Fixture.SchoolDouble.new()
	game.session.online=false
	game.add_child(game.session)
	game.add_child(game.school)
	game.session.roster={1:{},2:{},3:{}}
	game.session.poses={2:{"position":Vector3.ZERO},3:{"position":Vector3.ZERO}}
	for i in range(2):
		var chair=Fixture.ChairDouble.new()
		game.add_child(chair)
		game.chairs.append(chair)
	manager=Fixture.Capture.new()
	game.add_child(manager)
	manager.build(game)
	assert(manager.register_station("a",0,Vector3.ZERO))
	assert(manager.register_station("b",1,Vector3.ZERO))
	manager._accept(2,{"op":"enter","station":"a"})
	manager._accept(3,{"op":"enter","station":"a"})
	assert(not manager.sessions.has(3))
	manager._accept(3,{"op":"enter","station":"b"})
	for peer in [2,3]:action(peer,"restore",{"files":{}})
	action(2,"save",{"path":"answer.txt","text":"A","version":0})
	action(3,"save",{"path":"answer.txt","text":"B","version":0})
	assert(manager.workspaces[2].files["answer.txt"].text=="A")
	assert(manager.workspaces[3].files["answer.txt"].text=="B")
	game.school.activity={"kind":"lecture"}
	game.school.papers[42]={"id":42,"owner":2,"project":{"title":"Existing assignment","questions":[],"answer_key":"secret"},"answers":{},"mark":{},"lesson":false}
	action(3,"submit",{"paper":42})
	assert(game.school.submissions==0)
	action(2,"submit",{"paper":42})
	action(2,"submit",{"paper":42})
	assert(game.school.submissions==1)
	action(2,"rename",{"path":"answer.txt","new_path":"renamed.txt"})
	assert(manager.workspaces[2].files.has("renamed.txt"))
	action(2,"rename",{"path":"renamed.txt","new_path":"answer.txt"})
	var old_lease: int=manager.sessions[2].lease
	action(3,"save",{"lease":old_lease,"path":"answer.txt","text":"stolen","version":1})
	assert(manager.workspaces[3].files["answer.txt"].text=="B")
	action(2,"restore",{"files":{}})
	assert(manager.workspaces[2].files.has("answer.txt"))
	action(2,"exit")
	assert(game.chairs[0].occupant==0 and not manager.sessions.has(2))
	manager._accept(2,{"op":"enter","station":"a"})
	assert(manager.sessions[2].lease!=old_lease)
	assert(manager.workspaces[2].files["answer.txt"].text=="A")
	game.session.roster.erase(2)
	manager._prune()
	assert(not manager.sessions.has(2) and not manager.workspaces.has(2))
	game._release_chair(2)
	game.session.roster[2]={}
	manager._accept(2,{"op":"enter","station":"a"})
	assert(manager.workspaces[2].files.is_empty())
	assert(not manager.restored.has(2))
	manager._reset()
	assert(manager.sessions.is_empty() and manager.workspaces.is_empty())
	print("SESSION_LIFECYCLE_PASS")
	quit()
