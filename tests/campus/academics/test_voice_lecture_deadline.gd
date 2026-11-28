extends SceneTree
const Classes=preload("res://scripts/campus/academics/class_start/room_classes.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
class Faculty extends Node:
	var interrupted:=false
	var speech_player:=Player.new()
	func lesson_question_active(_room: String) -> bool:return interrupted
class Game extends Node:
	var faculty:=Faculty.new()
class TestClasses extends Classes:
	var clock:=0.
	var transitions:=0
	func _now() -> float:return clock
	func _begin_assignment(_room: String,activity: Dictionary) -> bool:
		transitions+=1;activity.phase="assignment";return true
	func _publish() -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game:=Game.new();root.add_child(game);game.add_child(game.faculty);game.faculty.add_child(game.faculty.speech_player)
	var classes:=TestClasses.new();game.add_child(classes);classes.set_process(false);classes.game=game
	var activity:={"phase":"lesson","deadline":120.,"lesson_tick":100.,"lesson_pause":89.,"students":{}}
	classes.classes.room=activity
	game.faculty.interrupted=true;classes.clock=101.;classes._advance()
	assert(activity.voice_pause_remaining==20. and activity.deadline==121.)
	classes.clock=300.;classes._advance()
	assert(activity.phase=="lesson" and activity.deadline==320. and classes.transitions==0,"A long question must not exhaust an arbitrary 90-second pause budget.")
	game.faculty.interrupted=false;classes.clock=301.;classes._advance()
	assert(activity.deadline==321. and not activity.has("voice_pause_remaining"))
	classes.clock=320.;classes._advance();assert(classes.transitions==0)
	game.faculty.speech_player.presentations.room={"serial":1,"until":9999999999}
	classes.clock=322.;classes._advance()
	assert(classes.transitions==0,"Final queued narration must finish before timed assessment starts.")
	game.faculty.speech_player.presentations.clear();classes._advance()
	assert(classes.transitions==1 and activity.phase=="assignment")
	activity={"phase":"lesson","deadline":1.,"lesson_tick":0.,"students":{},"npc_voice_question":true}
	classes.classes.room=activity;classes.clock=5.;classes._advance()
	assert(activity.phase=="lesson" and activity.deadline==6.,"A question starting at the deadline must still freeze the remaining explanation.")
	activity.npc_voice_question=false;classes.clock=10.;classes._advance()
	assert(activity.deadline==11. and classes.transitions==1)
	game.queue_free();await process_frame
	print("VOICE_LECTURE_DEADLINE PASS (long interruptions, exact remaining time, final narration, deadline boundary)")
	quit()
