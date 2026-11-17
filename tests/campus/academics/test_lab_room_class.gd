extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 var classes=game.lecture_classes
 var school=game.school
 var identity="0123456789abcdef0123456789abcdef0123456789abcdef"
 school.identities[1]=identity
 game.session.roster[1]={"name":"Student"}
 for room in ["ac_lab","dc_lab"]:
  var course="ELM253" if room=="ac_lab" else "ETY155"
  assert(classes._start(room,{"kind":"lecture","course_id":course,"week":1,"difficulty":2})!="")
  game.faculty.current[room]="mr_phillips"
  assert(classes._start(room,{"kind":"lab","course_id":course,"week":1,"difficulty":2})=="")
  game.player.global_position=classes.signs[room].desk
  assert(classes._sign(1,room)=="")
  var activity: Dictionary=classes.classes[room]
  assert(activity.students[identity].project.kind=="lab")
  assert(classes._begin_assignment(room,activity))
  var id: int=activity.students[identity].paper
  assert(id>0 and school.papers[id].project.kind=="lab")
  assert(classes.paper_action_allowed(1,school.papers[id],"answer"))
  classes.classes.erase(room)
  school.papers.clear()
 game.faculty.current.dc_lab="mr_hamstrings"
 var digital_start: String=classes._start("dc_lab",{"kind":"lab","course_id":"DGS266","week":3,"difficulty":2})
 if not digital_start.is_empty():push_error(digital_start)
 assert(digital_start=="")
 game.player.global_position=classes.signs.dc_lab.desk
 assert(classes._sign(1,"dc_lab")=="")
 var digital: Dictionary=classes.classes.dc_lab
 var bench: int=int(digital.students[identity].bench)
 assert(bench>=0 and bench<game.dc_lab.benches.size())
 assert(classes._begin_assignment("dc_lab",digital))
 assert(school.equipment_access(1,bench,"ETY155"))
 assert(not school.equipment_access(1,bench,"ELM253"))
 if game.dc_lab.benches.size()>1:
  assert(not school.equipment_access(1,(bench+1)%game.dc_lab.benches.size(),"ETY155"))
 var digital_paper: Dictionary=school.papers[int(digital.students[identity].paper)]
 for page_index in 4:
  var page=preload("res://scripts/worksheet_page.gd").new()
  page.paper=digital_paper;page.page=page_index
  root.add_child(page)
  assert(is_instance_valid(page.ink))
  page.queue_free()
 for i in digital_paper.project.questions.size():
  digital_paper.answers[str(i)]=str(digital_paper.project.questions[i].answer)
 var station=game.dc_lab.benches[bench]
 var board=preload("res://scripts/breadboard_model.gd").empty()
 var pins: Array=[]
 for i in range(1,8):pins.append("A%d"%i)
 for i in range(1,8):pins.append("F%d"%i)
 board.parts=[{"id":"gate","type":"hc08","pins":pins}]
 station.board=board;station.board_held=false;station.board_stowed=false;station.wires=[]
 var nodes: Array=pins.map(func(h):return "board/"+preload("res://scripts/breadboard_model.gd").node(h,30))
 var solver=preload("res://scripts/electronics_solver.gd").new()
 var voltage: Dictionary={}
 for a in 2:
  for b in 2:
   var sources: Array=[{"id":"v","kind":"V","a":nodes[13],"b":nodes[6],"value":5.0,"resistance":.1},{"id":"a","kind":"V","a":nodes[0],"b":nodes[6],"value":5.0*a,"resistance":.1},{"id":"b","kind":"V","a":nodes[1],"b":nodes[6],"value":5.0*b,"resistance":.1}]
   for step in 4:
    var parts=sources.duplicate(true)
    parts.append_array(preload("res://scripts/device_models.gd").expand(preload("res://scripts/electronics_catalog.gd").all().hc08,"board/gate",nodes,{},voltage,{}))
    station.result=solver.solve(parts,[],.0005);assert(station.result.ok);voltage=station.result.v
   assert(school.equipment_adapter.record_measurement(1,bench,digital_paper.project))
 assert(school.equipment_adapter.grade(digital_paper.project,school.equipment_adapter.capture(1,bench,digital_paper.project)).score==100.0)
 station.board.wires.append(["A1","A2"])
 assert(school.equipment_adapter.grade(digital_paper.project,school.equipment_adapter.capture(1,bench,digital_paper.project)).score==0.0)
 station.board.wires.clear()
 school._mark(digital_paper,false)
 assert(is_equal_approx(float(digital_paper.mark.score),100.0))
 assert(is_equal_approx(float(digital_paper.mark.practical.score),100.0))
 var flip_assignment=digital_paper.project.duplicate(true)
 flip_assignment.assessment_id="flip-test";flip_assignment.practical={"type":"digital_flipflop"}
 station.board.parts=[{"id":"ff","type":"flip74","pins":pins}]
 var flip_volts:={};var flip_islands:={}
 for node in nodes:flip_volts[node]=0.0;flip_islands[node]="powered"
 flip_volts[nodes[13]]=5.0;flip_volts[nodes[0]]=5.0;flip_volts[nodes[3]]=5.0
 station.result={"ok":true,"v":flip_volts,"islands":flip_islands}
 station.firmware_states={"board/ff":{"powered":true,"a":false}}
 for bit in 2:
  flip_volts[nodes[1]]=5.0*bit;flip_volts[nodes[2]]=0.0
  assert(school.equipment_adapter.record_measurement(1,bench,flip_assignment))
  flip_volts[nodes[2]]=5.0;flip_volts[nodes[4]]=5.0*bit
  station.firmware_states["board/ff"].a=bool(bit)
  assert(school.equipment_adapter.record_measurement(1,bench,flip_assignment))
 assert(school.equipment_adapter.grade(flip_assignment,school.equipment_adapter.capture(1,bench,flip_assignment)).score==100.0)
 var interlock=flip_assignment.duplicate(true);interlock.assessment_id="interlock-test";interlock.practical={"type":"digital_interlock"}
 assert(not school.equipment_adapter.record_measurement(1,bench,interlock))
 print("PASS lab class track, attendance and assignment issuance")
 game.queue_free();await process_frame
 quit()
