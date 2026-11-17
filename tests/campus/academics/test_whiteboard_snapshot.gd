extends SceneTree
const School=preload("res://scripts/school_session.gd")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var host:=School.new()
	root.add_child(host)
	host.project={"title":"Lesson","questions":[]}
	host.papers[7]={"id":7,"owner":0,"identity":"host-only-token","classroom_board":"ety155_lecture","position":Vector3(26,7.28,-2.7),"project":{"title":"Classroom whiteboard","questions":[]},"lesson":false,"mark":{},"answers":{},"strokes":{},"annotations":{},"revision":1,"board_lines":[[Vector2(.1,.2),Vector2(.4,.3)]],"board_notes":[{"text":"I = V / R"}]}
	var observer: Dictionary=host._public_state(2)
	assert(observer.papers[7].board_lines.size()==1 and observer.papers[7].board_notes[0].text=="I = V / R")
	assert(not observer.papers[7].has("identity"))
	host.papers[7].board_lines.append([Vector2(.4,.3),Vector2(.6,.5)])
	host.papers[7].board_notes.append({"text":"I = 6 mA"})
	host.papers[7].revision=2
	assert(observer.papers[7].board_lines.size()==1)
	var late_join: Dictionary=host._public_state(3)
	assert(late_join.papers[7].board_lines.size()==2 and late_join.papers[7].board_notes.size()==2)
	var client:=School.new()
	root.add_child(client)
	client._snapshot(late_join)
	assert(client.papers[7].revision==2 and client.papers[7].board_lines.size()==2 and client.papers[7].board_notes[1].text=="I = 6 mA")
	print("WHITEBOARD_SNAPSHOT PASS")
	client.queue_free();host.queue_free();quit(0)
