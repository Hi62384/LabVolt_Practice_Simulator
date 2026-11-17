extends SceneTree
const Selector=preload("res://scripts/campus/academics/classroom_events/event_selector.gd")
func _initialize() -> void:
 var lecture:={"kind":"lecture","course":"ELM253","deadline":420.0,"teaching":{"title":"AC circuit measurements","duration_seconds":420.0,"objectives":["Predict voltage and current in a circuit"],"stages":[{"start_seconds":0.0,"duration_seconds":210.0,"title":"Waveforms","caption":"Compare voltage and current"},{"start_seconds":210.0,"duration_seconds":210.0,"title":"Circuit experiment","caption":"Measure a resistor"}]}}
 assert(Selector.lesson_focus(lecture,20.0).contains("waveforms"))
 assert(Selector.lesson_focus(lecture,240.0).contains("circuit experiment"))
 var strict:={"teaching":.9,"focus":.9,"difficulty":.8,"talkativeness":.4,"description":"strict in class"}
 var first: Array=Selector.rank(lecture,strict,2,[],102,240.0,true)
 assert(first==Selector.rank(lecture,strict,2,[],102,240.0,true))
 assert(first.size()==10 and first.has("demonstration") and not first.has("quiz"))
 assert(Selector.rank(lecture,strict,2,["practice"],102,240.0,true).has("quiz"))
 var solo: Array=Selector.rank(lecture,strict,1,[],102,240.0,true)
 for mode in ["quiz","group","duel","race"]:assert(mode not in solo)
 var no_board: Array=Selector.rank(lecture,strict,2,[],102,240.0,false)
 for mode in ["board","demonstration","mistake","teacher","mystery","duel","pass","race"]:assert(mode not in no_board)
 assert(Selector.rank(lecture,strict,0,[],102,240.0,true).is_empty())
 var digital:=lecture.duplicate(true);digital.course="DGS266"
 var digital_modes: Array=Selector.rank(digital,strict,2,[],102,240.0,true)
 for mode in ["demonstration","mistake","mystery","pass"]:assert(mode not in digital_modes)
 var lab:=lecture.duplicate(true);lab.kind="lab";lab.room="ac_lab"
 assert(Selector.rank(lab,strict,1,[],102,240.0,true)==["physical"])
 lab.room="dc_lab";assert(Selector.rank(lab,strict,1,[],102,240.0,true).is_empty())
 var without_repeat:=0;var with_repeat:=0
 for seed_value in 100:
  if Selector.rank(lecture,strict,2,[],seed_value,240.0,true)[0]=="practice":without_repeat+=1
  if Selector.rank(lecture,strict,2,["practice"],seed_value,240.0,true)[0]=="practice":with_repeat+=1
 assert(with_repeat<without_repeat)
 print("CLASSROOM_EVENT_SELECTOR PASS");quit(0)
