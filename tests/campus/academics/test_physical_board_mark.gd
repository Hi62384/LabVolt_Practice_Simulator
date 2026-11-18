extends SceneTree
const School=preload("res://scripts/school_session.gd")
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")

class Session:
	var roster:={1:{},2:{}}
	var online:=false
	var poses:={1:{"position":Vector3.ZERO},2:{"position":Vector3.ZERO}}
	func peer_connected_now(_peer: int) -> bool:return false
class Classes:
	extends RefCounted
	var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"ETY155","week":1,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
	var classroom_events: Node
	func _inside(_peer: int,_room: String) -> bool:return true
class Events:
	extends Node
	var enabled:=true
	var service: Node
class Game:
	extends Node
	var session:=Session.new()
	var school: Node
	var lecture_classes:=Classes.new()
	var player:=Node3D.new()

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var game:=Game.new();root.add_child(game);game.add_child(game.player)
	var school:=School.new();game.add_child(school);school.game=game;game.school=school;school.set_process(false)
	school.project={"title":"Lesson","questions":[]}
	school.identities={1:"alice",2:"bob"}
	school.papers[1]={"id":1,"owner":1,"held":true,"supply_id":"marker"}
	school.papers[2]={"id":2,"owner":0,"held":false,"supply_id":"whiteboard","classroom_board":"room","position":Vector3(0,1,0),"wall_normal":Vector3.BACK,"board_lines":[],"revision":0,"project":{"title":"Board","questions":[]},"mark":{},"lesson":false}
	var events:=Events.new();game.add_child(events);game.lecture_classes.classroom_events=events
	var service:=Service.new();events.add_child(service);service.configure(game);events.service=service
	var now:=Time.get_ticks_msec()/1000.0
	game.lecture_classes.classes.room.deadline=now+300.0
	assert(service.start("room",now,[],"board"))
	var stroke:={"id":2,"from":Vector2(.2,.2),"point":Vector2(.4,.4),"erase":false}
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.is_empty())
	var event_id: String=service.rooms.room.round.event_id
	assert(service.rooms.room.hands.call_student(true,event_id,"alice"))
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==1 and school.papers[2].revision==2)
	school._mark_whiteboard(2,stroke)
	assert(school.papers[2].board_lines.size()==1)
	game.player.global_position=Vector3(0,1,5)
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==1)
	game.player.global_position=Vector3.ZERO
	school._mark_whiteboard(1,{"id":2,"from":Vector2(-.1,0),"point":Vector2(.3,.3)})
	assert(school.papers[2].board_lines.size()==1)
	school.papers[1].held=false
	school._mark_whiteboard(1,{"id":2,"from":Vector2(.4,.4),"point":Vector2(.6,.6)})
	assert(school.papers[2].board_lines.size()==2)
	school.papers[3]={"id":3,"owner":1,"held":false,"supply_id":"whiteboard","position":Vector3(0,1,0),"wall_normal":Vector3.BACK,"board_lines":[],"revision":0}
	school.papers[4]={"id":4,"owner":0,"held":false,"supply_id":"whiteboard","classroom_board":"other","position":Vector3(0,1,0),"wall_normal":Vector3.BACK,"board_lines":[],"revision":0}
	school._mark_whiteboard(1,{"id":3,"from":Vector2(.2,.2),"point":Vector2(.4,.4)})
	school._mark_whiteboard(1,{"id":4,"from":Vector2(.2,.2),"point":Vector2(.4,.4)})
	assert(school.papers[3].board_lines.is_empty() and school.papers[4].board_lines.is_empty())
	school.papers[5]={"id":5,"owner":1,"held":true,"supply_id":"notebook"}
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==2)
	school.papers[5].held=false
	game.player.global_position=Vector3(0,1,5)
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==2)
	game.player.global_position=Vector3.ZERO
	events.enabled=false
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==2)
	events.enabled=true
	service.rooms.room.round.deadline=now-1.0
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.size()==2)
	game.lecture_classes.classes.room.phase="assignment"
	service.tick(Time.get_ticks_msec()/1000.0)
	assert(service.rooms.is_empty())
	school._mark_whiteboard(1,stroke)
	assert(school.papers[2].board_lines.is_empty())
	# The 2D editor writes to the same physical board and obeys the marker check.
	var path := PackedVector2Array([Vector2(.2,.2),Vector2(.4,.4),Vector2(.6,.2)])
	var edit := {"op":"board_path","id":3,"points":path,"color":"227755","width":8.0}
	school._mark_whiteboard(1,edit)
	assert(school.papers[3].board_lines.is_empty())
	school.papers[1].held=true
	school._mark_whiteboard(1,edit)
	assert(school.papers[3].board_lines.size()==1 and school.papers[3].board_lines[0].color=="227755")
	school._mark_whiteboard(1,{"op":"board_edit","id":3,"edit":"undo"})
	assert(school.papers[3].board_lines.is_empty())
	for i in 700:
		school._mark_whiteboard(1,{"id":3,"from":Vector2(.22,.25),"point":Vector2(.45,.44)})
	assert(school.papers[3].board_lines.size()==700)
	school._mark_whiteboard(1,{"op":"board_edit","id":3,"edit":"clear"})
	assert(school.papers[3].board_lines.is_empty())
	print("PHYSICAL_BOARD_MARK PASS")
	game.queue_free();quit(0)
