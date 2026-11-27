extends SceneTree
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
class Interaction extends RefCounted:
	var recorded: Array=[]
	func _current(_prepared: Dictionary) -> bool:return true
	func record(result: Dictionary,delivered: bool) -> void:recorded.append({"result":result,"delivered":delivered})
class Faculty extends Node:
	var pending: Dictionary={}
	var voices: Array=[]
	var heard: Array=[]
	var character_interaction:=Interaction.new()
	func student_speech_pending(actor: String) -> bool:return bool(pending.get(actor,false))
	func present_student_speech(room: String,class_id: String,actor: String,line: String,mood: String,affect: Dictionary,priority: int) -> void:
		voices.append({"room":room,"class_id":class_id,"actor":actor,"line":line,"mood":mood,"affect":affect,"priority":priority})
	func generate_character_exchange(_profile: Dictionary,_speaker: String,_activity: Dictionary,line: String,_options: Dictionary) -> Dictionary:
		heard.append(line)
		return {}
class Classes extends Node:
	var classes: Dictionary={}
class Game extends Node:
	var faculty:=Faculty.new()
	var lecture_classes:=Classes.new()
class TestStudents extends Students:
	func _observe_student_behavior(_room: String,_activity: Dictionary,_member: Dictionary,_now: float) -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game:=Game.new();root.add_child(game);game.add_child(game.faculty);game.add_child(game.lecture_classes)
	var students:=TestStudents.new();game.add_child(students);students.game=game
	var first:={"profile":{"id":"first","name":"First student"},"position":Vector3.ZERO,"action":"chatting","mood":"steady"}
	var second:={"profile":{"id":"second","name":"Second student"},"position":Vector3.ONE,"action":"listening","mood":"happy"}
	var activity:={"id":"class","phase":"arrival","classmates":{"first":first,"second":second}}
	game.lecture_classes.classes.room=activity
	activity.classmate_reply={"speaker":"first","listener":"second","line":"Thanks, that helps.","phase":"arrival","at":0.,"room":"room","emotion":"happy","result":{"prepared":{},"emotions":{"joy":.7}}}
	game.faculty.pending.first=true
	students._show_preclass_reply(activity,100.)
	assert(activity.has("classmate_reply") and game.faculty.voices.is_empty(),"A ready reply must wait for real opening playback, even after text timing elapsed.")
	game.faculty.pending.first=false
	students._show_preclass_reply(activity,100.1)
	assert(game.faculty.voices.is_empty(),"Turns need a short natural gap after hearing the opening.")
	students._show_preclass_reply(activity,100.5)
	assert(not activity.has("classmate_reply") and game.faculty.voices.size()==1)
	assert(game.faculty.voices[0].actor=="second" and game.faculty.voices[0].room=="room" and game.faculty.voices[0].class_id=="class")
	assert(game.faculty.voices[0].affect.joy==.7 and second.line=="Thanks, that helps.")
	assert(game.faculty.character_interaction.recorded.size()==1 and game.faculty.heard==["Thanks, that helps."])
	activity.classmate_reply={"speaker":"first","listener":"second","line":"Old response.","phase":"lesson","at":0.}
	game.faculty.pending.first=true
	students._show_preclass_reply(activity,200.)
	assert(not activity.has("classmate_reply") and game.faculty.voices.size()==1,"A changed class phase cancels speech instead of waiting forever.")
	students._present_student_speech(activity,first,"","No room.")
	assert(game.faculty.voices.size()==1)
	game.queue_free();await process_frame
	print("STUDENT_VOICE_TURNS PASS (real playback turn gate, gap, identity, emotional routing, stale phase)")
	quit()
