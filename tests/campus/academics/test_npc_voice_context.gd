extends SceneTree
## Exercise real routing/noise gates and async reservation ownership without a
## microphone, a cloud service, or subjective acoustic assertions.
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
const Natural=preload("res://scripts/campus/voice/npc_voice_router.gd")
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")

class Session:
 var roster:={1:{}}
 var poses:={}
 var online:=false
class Registry:
 func locate(_point: Vector3) -> String:return "ac_lab"
class Campus:
 var registry:=Registry.new()
class Probe extends Faculty:
 var reports:=0
 var valid_target:=true
 var student_question:=false
 func voice_target_valid(_peer: int,_target: Dictionary) -> bool:return valid_target
 func _ai_activity(_room: String) -> Dictionary:return {"npc_voice_question":student_question}
 func report_event(_peer: int,_room: String,_kind: String,_position: Vector3,_strength: float,_context: Dictionary={}) -> bool:
  reports+=1;return true
class Game extends Node:
 var session:=Session.new()
 var campus:=Campus.new()
 var player:=Node3D.new()
 var faculty: Node

func _initialize() -> void:run.call_deferred()

func run() -> void:
 create_timer(10.).timeout.connect(func():push_error("NPC voice context timed out");quit(1))
 var game:=Game.new();root.add_child(game);game.add_child(game.player)
 var faculty:=Probe.new();game.add_child(faculty);faculty.set_process(false);faculty.game=game;game.faculty=faculty
 var natural:=Natural.new();faculty.add_child(natural);natural.set_process(false);natural.game=game;natural.faculty=faculty;faculty.natural_voice=natural
 var voice:=Voice.new();game.add_child(voice);voice.set_process(false);voice.game=game
 var packet:=PackedByteArray();packet.resize(640)
 for offset in range(0,640,2):packet.encode_s16(offset,6000)
 for index in 8:voice._observe_teacher_sound(1,packet)
 assert(faculty.reports==1,"Unaddressed, opted-in sustained noise still reaches classroom observation.")
 natural.remote_turns[1]={"token":"question","target":{"id":"mr_bro"},"started":Time.get_ticks_msec(),"input_finished":false}
 for index in 8:voice._observe_teacher_sound(1,packet)
 assert(faculty.reports==1 and not voice.teacher_sound.state.has(1),"An addressed academic question cannot also trigger a loudness-only reprimand.")
 natural.mark_input_finished(1,"stale-token")
 assert(natural.addressed_speech_active(1),"A stale turn cannot end the current question's context.")
 natural.mark_input_finished(1,"question")
 assert(not natural.addressed_speech_active(1))
 for index in 8:voice._observe_teacher_sound(1,packet)
 assert(faculty.reports==2,"A finished question does not suppress future classroom sound observation.")
 natural.remote_turns[1].input_finished=false;faculty.valid_target=false
 assert(not natural.addressed_speech_active(1),"Leaving valid hearing context stops addressed-turn exemption.")
 faculty.ai_busy[1]="ac_lab";faculty.question_channels[1]="mr_bro"
 var old_epoch:=faculty.character_epoch
 faculty.character_epoch+=1
 assert(not faculty._release_question(1,old_epoch) and faculty.ai_busy.has(1) and faculty.question_channels.has(1),"An old callback cannot erase a new session's reservation.")
 assert(faculty._release_question(1,faculty.character_epoch) and faculty.ai_busy.is_empty() and faculty.question_channels.is_empty())
 faculty.student_question=true
 assert(faculty.lesson_question_active("ac_lab"),"Invited student speech holds the lecture even without a paused teacher clip.")
 faculty.student_question=false
 assert(not faculty.lesson_question_active("ac_lab"))
 faculty.speech_player=Player.new();faculty.add_child(faculty.speech_player)
 faculty.voice_channel_rooms={"classmate:one":"ac_lab","classmate:two":"dc_lab"}
 var actor:=Node3D.new();game.add_child(actor)
 var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=16000
 var silence:=PackedByteArray();silence.resize(320000);wav.data=silence
 assert(faculty.speech_player.accept("classmate:one","One",1,"A lesson question.",1,actor,wav))
 assert(faculty.speech_player.accept("classmate:two","Two",1,"An unrelated room.",1,actor,wav))
 faculty._sync_voice_room_context("ac_lab",{"id":"same-class","teacher":"mr_bro","phase":"lesson"})
 faculty._sync_voice_room_context("ac_lab",{"id":"same-class","teacher":"mr_bro","phase":"assignment"})
 assert(not faculty.speech_player.has_utterance("classmate:one",1),"A class phase change cancels already playing student dialogue.")
 assert(faculty.speech_player.has_utterance("classmate:two",1),"Another classroom's valid audio remains intact.")
 game.queue_free();await process_frame
 print("NPC_VOICE_CONTEXT PASS (addressed speech, stale turns, session reservations, student lecture gate, class phase cancellation)")
 quit()
