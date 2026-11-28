extends SceneTree
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Hands=preload("res://scripts/campus/academics/classroom_events/hand_queue.gd")
const Prefs=preload("res://scripts/campus/ui/client_preferences.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
class Session:
 var roster:={1:{}}
 var poses:={}
 var online:=false
class School:
 var identities:={1:"alice"}
 var local_identity:="class-call-host"
class OfflineClient:
 extends Node
 var busy:=false
 var enabled:=false
 var tts_enabled:=false
 var tts_model:="fixture"
 var requests:=0
 func ready_for_class() -> bool:return enabled
 func configured() -> bool:return enabled
 func moderate(_text: String)->Dictionary:return {"ok":true,"flagged":false}
 func interpret_character(_instructions: String,_context: Dictionary,question: String)->Dictionary:
  # The conservative past-event guard reviews "how you reached your answer".
  # These authored inputs are explanation requests, not claimed grades/actions.
  var consistent:=question in ["Explain how you reached your answer.","Walk the class through your method.","Which assumption did you start with?"]
  return {"ok":true,"text":JSON.stringify({"consistent":consistent,"reason":"The fixture requests an explanation and asserts no completed gameplay action or grade."})}
 func respond_character(_instructions: String,context: Dictionary,_question: String,_visual:=false)->Dictionary:
  var lines:=["Explain how you reached your answer.","Walk the class through your method.","Which assumption did you start with?"]
  var line: String=lines[requests%lines.size()]
  requests+=1
  return {"ok":true,"text":JSON.stringify({"speech":line,"biography_facts":[],"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}})}
class Registry:
 func locate(_position: Vector3) -> String:return "ac_lab"
class Campus:
 var registry:=Registry.new()
class Classes:
 var classes:={"ac_lab":{"id":"class-1","teacher":"jeff","phase":"lesson","course":"ETY155","students":{"alice":{"peer":1,"done":false}}}}
 var classroom_events: Node
 func _inside(peer: int,room: String) -> bool:return peer==1 and room=="ac_lab"
class Round:
 extends RefCounted
 var event_id:="event-1"
 var closed:=false
 var present:={"alice":true}
class EventService:
 extends Node
 var rooms:={}
class Events:
 extends Node
 var enabled:=true
 var service: EventService
class World:
 var teacher:=Node3D.new()
 var dc_instructor:=Node3D.new()
class Game:
 extends Node3D
 var client_preferences:=Prefs.new()
 var session:=Session.new()
 var school:=School.new()
 var campus:=Campus.new()
 var lecture_classes:=Classes.new()
 var school_world:=World.new()
 var host_openai:=OfflineClient.new()
 var player:=Node3D.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 create_timer(8.).timeout.connect(func():quit(1))
 var game:=Game.new();root.add_child(game)
 game.add_child(game.host_openai)
 game.add_child(game.player);game.player.position=Vector3(0,0,2)
 game.add_child(game.school_world.teacher)
 game.add_child(game.school_world.dc_instructor)
 var model:=Node3D.new();model.name="InstructorModel";model.set_meta("faculty_id","jeff");game.school_world.teacher.add_child(model)
 var events:=Events.new();game.add_child(events);events.service=EventService.new();events.add_child(events.service);game.lecture_classes.classroom_events=events
 var hands:=Hands.new();assert(hands.begin(true,"event-1",["alice"]));assert(hands.call_student(true,"event-1","alice"))
 events.service.rooms["ac_lab"]={"class_id":"class-1","hands":hands,"round":Round.new()}
 var faculty:=Faculty.new();faculty.process_mode=Node.PROCESS_MODE_DISABLED;game.add_child(faculty);faculty.game=game;faculty.current={"ac_lab":"jeff"}
 faculty.brain.bind_mind(faculty.character_mind)
 assert(faculty.brain.set_host_profile(game.school.local_identity)==OK)
 assert(Store.set_host_profile(game.school.local_identity)==OK)
 faculty.character_interaction.bind(faculty.character_mind,faculty.brain)
 faculty.speech_player=Player.new();faculty.add_child(faculty.speech_player)
 events.enabled=false
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.is_empty())
 events.enabled=true
 events.service.rooms.ac_lab.round.present.clear()
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.is_empty())
 events.service.rooms.ac_lab.round.present["alice"]=true
 game.lecture_classes.classes.ac_lab.students.alice.done=true
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.is_empty())
 game.lecture_classes.classes.ac_lab.students.alice.done=false
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.has("ac_lab") and not faculty.speech_player.subtitles.has("ac_lab"),"A selected student stays selected without an invented offline utterance")
 assert(faculty.character_interaction.diagnostics.back().source=="technical_unavailable")
 faculty.class_calls.clear()
 game.host_openai.enabled=true
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.has("ac_lab") and faculty.speech_player.subtitles.has("ac_lab"))
 var text: String=faculty.speech_player.subtitles.ac_lab.item.text
 assert(faculty.reaction_labels.is_empty(),"Class prompts use the subtitle HUD without a floating world-space speech label")
 assert(text.contains("answer") or text.contains("reasoning") or text.contains("method"))
 assert(not text.contains("mA") and not text.contains("correct value"))
 var serial:=int(faculty.speech_player.last_serial.ac_lab)
 faculty.present_class_call("ac_lab","jeff",2)
 assert(int(faculty.speech_player.last_serial.ac_lab)==serial)
 assert(hands.finish_turn(true,"event-1"))
 faculty._prune_class_calls()
 assert(faculty.class_calls.is_empty() and faculty.speech_player.subtitles.is_empty())
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.is_empty())
 assert(hands.call_student(true,"event-1","alice"))
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.has("ac_lab"))
 var newer:=faculty._next_speech("ac_lab")
 faculty._show_reaction("ac_lab","jeff","A different class reminder",game.player.global_position,newer,3)
 assert(hands.finish_turn(true,"event-1"))
 faculty._prune_class_calls()
 assert(faculty.class_calls.is_empty() and faculty.speech_player.subtitles.has("ac_lab"))
 game.lecture_classes.classes.ac_lab.phase="assignment"
 assert(hands.call_student(true,"event-1","alice"))
 faculty.present_class_call("ac_lab","jeff",1)
 assert(faculty.class_calls.is_empty())
 game.queue_free();await process_frame
 print("TEACHER_CLASS_CALL_PROMPT PASS (local provider fixture; no live AI or voice)")
 quit()
