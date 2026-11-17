extends SceneTree
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
class Session:
 var roster:={1:{}}
 var poses:={}
 var online:=false
class Registry:
 func locate(_point: Vector3) -> String:return "ac_lab"
class Campus:
 var registry:=Registry.new()
class Faculty extends Node:
 var calls:=0
 func report_event(_peer: int,_room: String,_kind: String,_position: Vector3,_strength: float) -> void:calls+=1
class Game extends Node:
 var session:=Session.new()
 var campus:=Campus.new()
 var player:=Node3D.new()
 var faculty:=Faculty.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game);game.add_child(game.player);game.add_child(game.faculty)
 var voice:=Voice.new();game.add_child(voice);voice.set_process(false);voice.game=game
 var packet:=PackedByteArray();packet.resize(640)
 for i in range(0,640,2):packet.encode_s16(i,6000)
 for i in 10:
  voice.last_packet.clear();voice._relay(1,packet,false)
 assert(game.faculty.calls==0 and voice.teacher_sound.state.is_empty())
 for i in 3:
  voice.last_packet.clear();voice._relay(1,packet,true)
 assert(game.faculty.calls==0 and voice.teacher_sound.state.has(1))
 voice.last_packet.clear();voice._relay(1,packet,false)
 assert(not voice.teacher_sound.state.has(1))
 for i in 3:
  voice.last_packet.clear();voice._relay(1,packet,true)
 assert(game.faculty.calls==0)
 for i in 6:
  voice.last_packet.clear();voice._relay(1,packet,true)
 assert(game.faculty.calls==1)
 print("TEACHER_MICROPHONE_OPT_OUT PASS")
 game.queue_free();await process_frame;quit(0)
