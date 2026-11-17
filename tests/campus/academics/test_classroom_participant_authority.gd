extends SceneTree
const Authority=preload("res://scripts/campus/academics/classroom_events/participant_authority.gd")
func _initialize() -> void:
 var roster:={1:{},2:{}}
 var identities:={1:"alice",2:"bob"}
 var activity:={"phase":"lesson","students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}
 assert(Authority.resolve(1,roster,identities,activity,true)=="alice")
 assert(Authority.resolve(2,roster,identities,activity,true)=="bob")
 assert(Authority.resolve(3,roster,identities,activity,true).is_empty())
 assert(Authority.resolve(1,roster,identities,activity,false).is_empty())
 activity.phase="assignment";assert(Authority.resolve(1,roster,identities,activity,true).is_empty())
 activity.phase="lesson";activity.students.alice.peer=2
 assert(Authority.resolve(1,roster,identities,activity,true).is_empty())
 activity.students.alice.peer=1;activity.students.alice.done=true
 assert(Authority.resolve(1,roster,identities,activity,true).is_empty())
 print("CLASSROOM_PARTICIPANT_AUTHORITY PASS");quit(0)
