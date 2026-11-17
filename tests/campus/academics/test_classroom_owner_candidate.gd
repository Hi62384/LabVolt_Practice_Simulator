extends SceneTree
const OwnerCandidate=preload("res://scripts/campus/academics/classroom_events/controller.gd")
class Session:
 var roster:={1:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false}}}}
 var signs:={"room":{}}
 var present:=true
 func _inside(peer: int,_room: String) -> bool:return peer==1 and present
class Front:
 var in_game:=false
class Registry:
 func get_room(room: String) -> Dictionary:return {"center":Vector3(0,5,3)} if room=="room" else {}
class Campus:
 var registry:=Registry.new()
class Faculty:
 extends Node
 var calls: Array=[]
 func present_class_call(room: String,teacher: String,peer: int) -> void:calls.append([room,teacher,peer])
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
 var front:=Front.new()
 var campus:=Campus.new()
 var faculty:=Faculty.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 assert(OwnerCandidate.activity_gap({"talkativeness":1.0,"focus":1.0})<OwnerCandidate.activity_gap({"talkativeness":0.0,"focus":0.0}))
 assert(OwnerCandidate.activity_gap({"teaching":1.0})<OwnerCandidate.activity_gap({"teaching":0.0}))
 assert(OwnerCandidate.activity_gap({"difficulty":1.0})>OwnerCandidate.activity_gap({"difficulty":0.0}))
 assert(OwnerCandidate.quiz_affinity({"focus":1.0,"difficulty":1.0,"talkativeness":1.0,"teaching":0.0})>OwnerCandidate.quiz_affinity({"focus":0.0,"difficulty":0.0,"talkativeness":0.0,"teaching":1.0}))
 assert(OwnerCandidate.choose_mode({"teaching":.9},0,1)=="board")
 assert(OwnerCandidate.choose_mode({"teaching":.9},0,1,"ETY155")=="demonstration")
 assert(OwnerCandidate.choose_mode({"focus":.9},1,2,"ETY155")=="mistake")
 assert(OwnerCandidate.choose_mode({"teaching":.9},2,1,"MTH147")=="teacher")
 assert(OwnerCandidate.choose_mode({"focus":.2},2,1,"ETY155")=="mystery")
 assert(OwnerCandidate.choose_mode({"talkativeness":.9},1,2)=="group")
 assert(OwnerCandidate.choose_mode({"focus":1.0,"difficulty":1.0},1,2)=="quiz")
 assert(OwnerCandidate.choose_mode({"teaching":.2},0,1,"ETY155")=="pass")
 assert(OwnerCandidate.choose_mode({"talkativeness":.2,"focus":.3},1,2)=="race")
 assert(OwnerCandidate.choose_mode({"talkativeness":.2,"focus":.6},2,2,"DGS266")=="duel")
 var game:=Game.new();root.add_child(game)
 var owner:=OwnerCandidate.new();root.add_child(owner);owner.configure(game)
 owner.step(100.0);assert(owner.service.rooms.is_empty())
 owner.enabled=true;owner.step(89.0);assert(owner.service.rooms.is_empty())
 owner.step(90.0);assert(owner.service.rooms.has("room"))
 assert(not is_instance_valid(owner.presentation.panel))
 assert(is_instance_valid(owner.presentation.announcement) and owner.presentation.announcement.visible)
 assert(owner.service.view(1,"room",90.0).stage=="announcing")
 var first_mode: String=owner.service.rooms.room.round.mode
 assert(owner.projector.board.visible==(first_mode in ["board","demonstration","mistake","teacher","mystery","duel","pass","race"]))
 var event: String=owner.service.rooms.room.round.event_id
 owner.step(91.0);assert(owner.service.rooms.room.round.event_id==event)
 assert(owner.service.perform(1,"room","class-1",event,"submit","0",91.0)=="announcing")
 owner.step(94.0);assert(is_instance_valid(owner.presentation.panel))
 owner.step(120.0);assert(owner.service.rooms.room.round.closed)
 owner.step(130.0);assert(owner.service.rooms.is_empty())
 game.lecture_classes.classes.room.teacher="jeff"
 assert(owner.service.start("room",131.0,[],"quiz"))
 assert(owner.projector.board.visible and owner.projector.active_room=="room")
 assert(not owner.projector.board.signature.contains("Answer:"))
 owner.step(141.0)
 assert(owner.service.rooms.room.hands.selected=="alice")
 assert(owner.service.rooms.room.call_count==1)
 assert(game.faculty.calls==[["room","jeff",1]])
 owner.step(161.0)
 assert(owner.service.rooms.room.round.closed)
 assert(owner.projector.board.signature.contains("Answer:"))
 game.lecture_classes.classes.room.phase="assignment";owner.step(162.0)
 assert(not owner.projector.board.visible and owner.service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.phase="lesson"
 owner.step(190.0);assert(owner.service.rooms.has("room"))
 assert(owner.service.rooms.room.round.event_id!=event)
 game.lecture_classes.classes.room.phase="assignment";owner.step(191.0)
 assert(owner.service.rooms.is_empty() and owner.presentation.panel==null)
 owner.disable();assert(not owner.enabled)
 owner.enabled=true;game.lecture_classes.present=false
 game.lecture_classes.classes.room={"id":"class-2","phase":"lesson","kind":"lecture","deadline":700.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false}}}
 for time in [490.0,505.0,520.0,535.0,550.0]:owner.step(time)
 assert(owner.service.rooms.is_empty())
 game.lecture_classes.present=true;owner.step(595.0)
 assert(owner.service.rooms.has("room"))
 print("CLASSROOM_OWNER_CANDIDATE PASS")
 owner.queue_free();game.faculty.free();game.queue_free();await process_frame;quit(0)
