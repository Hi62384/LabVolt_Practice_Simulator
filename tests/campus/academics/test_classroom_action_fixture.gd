extends SceneTree
const Actions=preload("res://tests/campus/academics/classroom_action_fixture.gd")
func _initialize() -> void:
 var state:=Actions.new()
 state.roster={1:{},2:{}}
 state.identities={1:"alice",2:"bob"}
 state.activity={"id":"class-1","phase":"lesson","students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}
 assert(state.round.prepare(true,"event-1","DGS266",3,0,42,30.0,["alice","bob"]))
 assert(state.hands.begin(true,"event-1",["alice","bob"]))
 var answer: String=str(state.round.private_assignment.questions[state.round.question_index].answer)
 assert(state.submit(false,1,true,"class-1","event-1",answer,1.0)=="denied")
 assert(state.submit(true,3,true,"class-1","event-1",answer,1.0)=="denied")
 assert(state.submit(true,1,false,"class-1","event-1",answer,1.0)=="denied")
 assert(state.submit(true,1,true,"stale","event-1",answer,1.0)=="denied")
 assert(state.submit(true,1,true,"class-1","old-event",answer,1.0)=="not_participating")
 assert(not state.hand(true,1,true,"class-1","old-event",true))
 assert(state.hand(true,1,true,"class-1","event-1",true))
 assert(state.hands.snapshot().hands==["alice"])
 assert(state.submit(true,1,true,"class-1","event-1",answer,1.0)=="accepted")
 assert(state.round.result("alice").is_empty())
 state.activity.students.bob.peer=4
 assert(state.submit(true,2,true,"class-1","event-1",answer,1.0)=="denied")
 assert(state.assessment_started(true))
 assert(state.submit(true,1,true,"class-1","event-1",answer,2.0)=="denied")
 assert(state.hands.snapshot().event_id.is_empty())
 assert(state.round.result("alice").correct)
 print("CLASSROOM_ACTION_FIXTURE PASS");quit(0)
