extends SceneTree
## Real classroom scheduling and local relationship selection with a counted
## generation boundary. No network/provider/hardware claim is made here.
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
var checks:=0
var failures: Array[String]=[]

class Faculty extends Node:
	var ai_busy: Dictionary={}
	var questions: Array=[]
	var brain:=Memory.new()
	func student_speech_pending(_id: String) -> bool:return false
class Session extends Node:
	var roster: Dictionary={1:{}}
class School extends Node:
	var identities: Dictionary={1:"host-person",2:"guest-person"}
class Client extends Node:
	var busy:=false
class Classes extends Node:
	var classes: Dictionary={}
	var positions: Dictionary={1:Vector3(100.,0.,0.),2:Vector3.ZERO}
	var rooms: Dictionary={1:"hallway",2:"classroom"}
	func _inside(peer: int,room: String) -> bool:return rooms.get(peer,"")==room
	func _position(peer: int) -> Vector3:return positions.get(peer,Vector3.INF)
class Game extends Node:
	var faculty:=Faculty.new()
	var session:=Session.new()
	var school:=School.new()
	var host_openai:=Client.new()
	var lecture_classes:=Classes.new()
	func _init() -> void:
		add_child(faculty);add_child(session);add_child(school);add_child(host_openai);add_child(lecture_classes)
class CountedStudents extends Students:
	var generated:=0
	func _start_social_exchange(activity: Dictionary,_speaker: Dictionary,_listener: Dictionary,_history: Dictionary,_reverse: Dictionary,_room: String) -> void:
		generated+=1
		activity.social_pending=false

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message)

func _initialize() -> void:_run.call_deferred()

func _run() -> void:
	var game:=Game.new();root.add_child(game)
	var students:=CountedStudents.new();game.add_child(students);students.game=game
	var actors: Dictionary={}
	for index in 2:
		var person:=Profiles.legacy_student(index);person.traits.initiative=1.
		actors[person.id]={"profile":person,"position":Vector3(float(index),0.,0.),"arrival":0.,"arrived":true,"seated":true,"action":"listening"}
	var activity:={"id":"budget-class","phase":"arrival","deadline":INF,"classmates":actors}
	game.lecture_classes.classes.classroom=activity
	for tick in 1200:students._before_class(activity,float(tick),"classroom")
	check(students.generated==0 and students.background_turns.is_empty(),"Unobserved classroom makes zero requests across 1,200 scheduler ticks")
	game.lecture_classes.positions[1]=Vector3.ZERO;game.lecture_classes.rooms[1]="classroom"
	students._before_class(activity,1500.,"classroom")
	check(students.generated==1,"Nearby human still permits natural social initiation")
	activity.social_pairs={};activity.social_next=0.;students.social_next_global=0.
	game.lecture_classes.positions[1]=Vector3(50.,0.,0.)
	students._before_class(activity,1600.,"classroom")
	check(students.generated==1,"A distant player does not authorize inaudible optional speech")
	game.session.roster[2]={}
	students._before_class(activity,1700.,"classroom")
	check(students.generated==2,"Remote player's nearby position enables host-authoritative optional speech")
	game.faculty.questions=[{"peer":2,"content":"A direct question"}]
	activity.social_pairs={};activity.social_next=0.;students.social_next_global=0.
	students._before_class(activity,1800.,"classroom")
	check(students.generated==2,"Queued player conversation has priority over optional NPC social work")
	game.faculty.questions.clear()
	var now:=Time.get_ticks_msec()
	check(students._reserve_background_turn("classroom",activity,now),"Third optional turn fits shared budget")
	check(students._reserve_background_turn("classroom",activity,now),"Fourth optional turn fits shared budget")
	check(not students._reserve_background_turn("classroom",activity,now),"Fifth optional turn is deferred without making an API request")
	check(students._reserve_background_turn("classroom",activity,now+Students.BACKGROUND_WINDOW_MS),"Budget becomes available after the rolling window")
	for member in actors.values():member.removed_from_class=true
	check(not students._has_player_audience("classroom",activity),"Removed actors cannot keep an invisible background conversation active")
	for member in actors.values():member.removed_from_class=false
	activity.classmate_reply={"phase":"arrival","room":"classroom","line":"Late optional reply"}
	game.session.roster.erase(2)
	students._show_preclass_reply(activity,2000.)
	check(not activity.has("classmate_reply"),"Leaving the room discards queued optional reply before TTS")
	check(not students._background_current("classroom",activity,"arrival"),"In-flight generation guard invalidates when audience leaves")
	game.lecture_classes.classes.clear()
	check(not students._activity_current(activity,"arrival"),"Ended class cannot retain a valid background callback")
	game.queue_free();await process_frame
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_BACKGROUND_BUDGET %s (%d checks; scheduler/request-boundary fixture)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
