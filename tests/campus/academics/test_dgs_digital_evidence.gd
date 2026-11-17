extends SceneTree
const Digital=preload("res://scripts/campus/academics/digital_evidence.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Device=preload("res://scripts/device_models.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Evidence=preload("res://scripts/campus/academics/equipment_evidence.gd")
func _initialize():
 var board=Board.empty()
 var pins: Array=[]
 for i in range(1,8):pins.append("A%d"%i)
 for i in range(1,8):pins.append("F%d"%i)
 board.parts=[{"id":"gate","type":"hc08","pins":pins}]
 var nodes: Array=pins.map(func(h):return "board/"+Board.node(h,30))
 var solver=preload("res://scripts/electronics_solver.gd").new()
 var voltage: Dictionary={};var rows:={}
 for a in 2:
  for b in 2:
   var sources: Array=[{"id":"supply","kind":"V","a":nodes[13],"b":nodes[6],"value":5.0,"resistance":.1},{"id":"a","kind":"V","a":nodes[0],"b":nodes[6],"value":5.0*a,"resistance":.1},{"id":"b","kind":"V","a":nodes[1],"b":nodes[6],"value":5.0*b,"resistance":.1}]
   var solved: Dictionary={}
   for i in 4:
    var parts: Array=sources.duplicate(true)
    parts.append_array(Device.expand(Catalog.all().hc08,"board/gate",nodes,{},voltage,{}))
    solved=solver.solve(parts,[],.0005)
    assert(solved.ok)
    voltage=solved.v
   var found: Array=Digital.samples(board,solved).filter(func(s):return s.gate=="gate:0")
   assert(found.size()==1 and found[0].correct and found[0].row==a*2+b)
   rows[str(found[0].row)]=found[0].correct
 var adapter=Evidence.new()
 var assignment={"course_id":"DGS266","practical":{"type":"digital_truth_table"}}
 assert(adapter.grade(assignment,{"digital_rows":{"gate:0":{"required":4,"values":rows}}}).score==100.0)
 rows["0"]=false
 assert(adapter.grade(assignment,{"digital_rows":{"gate:0":{"required":4,"values":rows}}}).score==75.0)
 assert(Digital.samples(board,{"ok":true,"v":{},"islands":{}}).is_empty())
 var flip_board=Board.empty();flip_board.parts=[{"id":"ff","type":"flip74","pins":pins}]
 var flip_volts:={};var flip_islands:={}
 for node in nodes:flip_volts[node]=0.0;flip_islands[node]="powered"
 flip_volts[nodes[13]]=5.0;flip_volts[nodes[0]]=5.0;flip_volts[nodes[3]]=5.0
 flip_volts[nodes[1]]=5.0;flip_volts[nodes[2]]=5.0;flip_volts[nodes[4]]=5.0
 var flip_result={"ok":true,"v":flip_volts,"islands":flip_islands}
 var flip=Digital.flip_samples(flip_board,flip_result,{"board/ff":{"powered":true,"a":true}})
 assert(flip.size()==1 and flip[0].data and flip[0].clock and flip[0].output and flip[0].state)
 flip_volts[nodes[0]]=0.0
 assert(Digital.flip_samples(flip_board,flip_result,{"board/ff":{"powered":true,"a":true}}).is_empty())
 var original=Digital.signature(board,[])
 board.wires.append(["A1","A2"])
 assert(Digital.signature(board,[])!=original)
 print("PASS DGS powered gate truth-table evidence and topology changes")
 quit()
