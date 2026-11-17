extends SceneTree
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
class Session:
 var roster:={1:{},2:{}}
 var poses:={2:{"position":Vector3(0,0,3)}}
 var last_pose:={}
 var online:=false
class Registry:
 func locate(_point: Vector3) -> String:return "ac_lab"
class Campus:
 var registry:=Registry.new()
class Faculty extends Node:
 var reactions:=0
 func report_event(_peer: int,_room: String,_kind: String,_position: Vector3,_severity: float) -> void:reactions+=1
class Game extends Node:
 var session:=Session.new()
 var campus:=Campus.new()
 var player:=Node3D.new()
 var faculty:=Faculty.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game);game.add_child(game.player);game.add_child(game.faculty)
 var voice:=Voice.new();game.add_child(voice);voice.set_process(false);voice.game=game
 var sound:=PackedByteArray();sound.resize(640)
 for i in range(0,640,2):sound.encode_s16(i,6000)
 for i in 6:voice._observe_teacher_sound(2,sound)
 assert(game.faculty.reactions==0 and not voice.teacher_sound.state.has(2))
 game.session.last_pose[2]=Time.get_ticks_msec()
 for i in 6:voice._observe_teacher_sound(2,sound)
 assert(game.faculty.reactions==1)
 voice.last_packet[2]=Time.get_ticks_msec()
 game.session.roster.erase(2)
 voice._prune()
 assert(not voice.teacher_sound.state.has(2) and not voice.last_packet.has(2))
 print("TEACHER_VOICE_STALE PASS")
 game.queue_free();await process_frame;quit(0)
