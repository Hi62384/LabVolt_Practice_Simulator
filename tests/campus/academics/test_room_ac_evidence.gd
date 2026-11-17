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
 assert(classes._start("ac_lab",{"kind":"lab","course_id":"ELM253","week":2,"difficulty":1})=="")
 game.player.global_position=classes.signs.ac_lab.desk
 assert(classes._sign(1,"ac_lab")=="")
 var activity: Dictionary=classes.classes.ac_lab
 assert(classes._begin_assignment("ac_lab",activity))
 var paper: Dictionary=school.papers[activity.students[identity].paper]
 var bench: int=paper.room_bench
 assert(bench>=0 and school.equipment_access(1,bench,"ELM253"))
 assert(not school.equipment_access(1,bench,"ETY155"))
 var adapter=school.equipment_adapter;var lab=game.session.labs[bench];var plan: Dictionary=paper.project.physical_ac_plan
 lab.cables.clear();lab.powered=false
 for kind in ["R","L","C"]:lab.switches[kind]=[false,false,false,false,false,false,false,false,false]
 lab.level=plan.variable_level;lab.frequency=plan.frequency_hz
 var nodes: Dictionary=plan.source_nodes.duplicate();var serial:=1
 for bank in plan.banks:
  var id: String=str(bank.kind)+str(bank.index)
  var switch_index: int=Catalog.LOADS[bank.kind].values.find(bank.value)
  assert(switch_index>=0)
  lab.switches[bank.kind][int(bank.index)*3+switch_index]=true
  for pair in [[bank.a,id+"_P"],[bank.b,id+"_N"]]:
   if not nodes.has(pair[0]):nodes[pair[0]]=pair[1]
   else:lab.cables.append({"id":serial,"a":nodes[pair[0]],"b":pair[1],"owner":0,"color":0});serial+=1
 for lead in lab.cables:
  if lead.b=="R0_P":lead.b="AM0_IN";break
 for pair in [["AM0_OUT","R0_P"],["V0_COM","R0_N"],["V0_150","R0_P"]]:
  lab.cables.append({"id":serial,"a":pair[0],"b":pair[1],"owner":0,"color":0});serial+=1
 adapter.observe_ac_action(1,bench,{"op":"plug"},{"powered":false})
 lab.powered=true;lab.recalculate()
 assert(adapter.record_measurement(1,bench,paper.project))
 lab.powered=false;lab.recalculate()
 adapter.observe_ac_action(1,bench,{"op":"power"},{"powered":true})
 var grade: Dictionary=adapter.grade(paper.project,adapter.capture(1,bench,paper.project))
 assert(grade.score==100)
 print("PASS room-hosted AC lab uses real bench and recorded evidence")
 game.queue_free();await process_frame
 quit()
