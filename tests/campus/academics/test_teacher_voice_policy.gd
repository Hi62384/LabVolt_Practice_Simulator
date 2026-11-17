extends SceneTree
const Policy=preload("res://scripts/campus/academics/teacher_voice_policy.gd")
class Round:
 extends RefCounted
 var closed:=false
 var mode:="practice"
 var deadline:=30.0
 var participants:={"student":true}
class Hands:
 extends RefCounted
 var selected:="student"
func _initialize() -> void:
 var activity:={"id":"class-1","phase":"lesson","students":{"student":{"peer":4,"done":false}}}
 var event:={"class_id":"class-1","round":Round.new(),"hands":Hands.new(),"called_until":20.0,"open_at":5.0}
 assert(not Policy.permitted(4,"student",activity,event,4.0))
 assert(Policy.permitted(4,"student",activity,event,10.0))
 assert(not Policy.permitted(4,"student",activity,event,30.0))
 assert(not Policy.permitted(4,"student",activity,event,21.0))
 assert(not Policy.permitted(5,"student",activity,event,10.0))
 assert(not Policy.permitted(4,"other",activity,event,10.0))
 event.class_id="stale"
 assert(not Policy.permitted(4,"student",activity,event,10.0))
 event.class_id="class-1"
 event.round.mode="group"
 event.hands.selected=""
 assert(Policy.permitted(4,"student",activity,event,10.0))
 event.round.closed=true
 assert(not Policy.permitted(4,"student",activity,event,10.0))
 event.round.closed=false
 activity.phase="assignment"
 assert(not Policy.permitted(4,"student",activity,event,10.0))
 assert(not Policy.permitted(4,"student",activity,{},10.0))
 print("TEACHER_VOICE_POLICY PASS")
 quit(0)
