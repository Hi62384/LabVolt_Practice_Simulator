extends SceneTree
const Catalog=preload("res://scripts/equipment_catalog.gd")
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 var school=game.school;var classes=game.lecture_classes
 var identity="0123456789abcdef0123456789abcdef0123456789abcdef"
 school.identities[1]=identity;game.session.roster[1]={"name":"Student"}
 game.faculty.current.ac_lab="mr_phillips"
 for lesson in school.course_bridge.weeks("ELM253","lab"):
  verify_week(game,identity,int(lesson.week))
 print("PASS all room-hosted AC lab weeks use the real bench and recorded evidence")
 game.queue_free();await process_frame
 quit()

func verify_week(game: Node,identity: String,week: int) -> void:
 var school=game.school;var classes=game.lecture_classes
 assert(classes._start("ac_lab",{"kind":"lab","course_id":"ELM253","week":week,"difficulty":1})=="")
 game.player.global_position=classes.signs.ac_lab.desk
 assert(classes._sign(1,"ac_lab")=="")
 var activity: Dictionary=classes.classes.ac_lab
 assert(classes._begin_assignment("ac_lab",activity))
 var paper: Dictionary=school.papers[activity.students[identity].paper]
 assert(paper.project.practical.type=="physical_ac")
 var bench: int=paper.room_bench
 assert(bench>=0 and school.equipment_access(1,bench,"ELM253"))
 assert(not school.equipment_access(1,bench,"ETY155"))
 var adapter=school.equipment_adapter;var lab=game.session.labs[bench];var plan: Dictionary=paper.project.physical_ac_plan
 lab.cables.clear();lab.powered=false
 for kind in ["R","L","C"]:lab.switches[kind]=[false,false,false,false,false,false,false,false,false]
 lab.level=plan.variable_level;lab.frequency=plan.frequency_hz
 for bank in plan.banks:
  var switch_index: int=Catalog.LOADS[bank.kind].values.find(bank.value)
  assert(switch_index>=0)
  lab.switches[bank.kind][int(bank.index)*3+switch_index]=true
 assert(paper.project.physical_wire_steps.has(["W0_VN","R0_N"]))
 for pair in paper.project.physical_wire_steps:
  lab.cables.append({"id":lab.cables.size()+1,"a":pair[0],"b":pair[1],"owner":0,"color":0})
 adapter.observe_ac_action(1,bench,{"op":"plug"},{"powered":false})
 lab.powered=true;lab.recalculate()
 assert(adapter.record_measurement(1,bench,paper.project))
 var evidence: Dictionary=adapter.capture(1,bench,paper.project)
 assert(evidence.observations.get("power",0.0)>0.0)
 evidence.observations.erase("power")
 assert(adapter.grade(paper.project,evidence).score<100)
 lab.powered=false;lab.recalculate()
 adapter.observe_ac_action(1,bench,{"op":"power"},{"powered":true})
 var grade: Dictionary=adapter.grade(paper.project,adapter.capture(1,bench,paper.project))
 assert(grade.score==100,"ELM253 week %d scored %s with %s"%[week,grade,adapter.capture(1,bench,paper.project).observations])
 assert(not adapter.record_measurement(1,bench,paper.project))
 assert(adapter.capture(1,(bench+1)%game.session.labs.size(),paper.project).is_empty())
 lab.frequency+=1.0
 assert(not adapter.capture(1,bench,paper.project).get("topology",false))
 classes.classes.erase("ac_lab")
 school.papers.erase(paper.id)
