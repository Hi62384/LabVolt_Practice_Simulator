extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Digital=preload("res://scripts/campus/academics/digital_evidence.gd")
const Device=preload("res://scripts/device_models.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
func _initialize():
 for week in [4,5]:test_network(week)
 test_binary()
 print("PASS DGS binary and combinational circuit evidence")
 quit()
func pins(start: int) -> Array:
 var result: Array=[]
 for i in range(start,start+7):result.append("A%d"%i)
 for i in range(start,start+7):result.append("F%d"%i)
 return result
func nodes(p: Array) -> Array:
 return p.map(func(h):return "board/"+Board.node(h,30))
func test_network(week: int) -> void:
 var a=pins(1);var o=pins(9);var n=pins(17)
 var board=Board.empty();board.parts=[{"id":"and","type":"hc08","pins":a},{"id":"or","type":"hc32","pins":o}]
 board.wires=[[a[6],o[6]],[a[13],o[13]]]
 if week==4:
  board.parts.append({"id":"not","type":"hc04","pins":n})
  board.wires.append_array([[a[6],n[6]],[a[13],n[13]],[n[0],o[0]],[n[1],o[1]],[o[2],a[1]]])
 else:board.wires.append([a[2],o[0]])
 var an=nodes(a);var on=nodes(o);var nn=nodes(n)
 var solver=preload("res://scripts/electronics_solver.gd").new();var voltage: Dictionary={};var observed:={}
 for bits in (4 if week==4 else 8):
  var av: int=(bits>>1)&1 if week==4 else (bits>>2)&1
  var bv: int=bits&1 if week==4 else (bits>>1)&1
  var cv: int=bits&1
  var sources: Array=[{"id":"supply","kind":"V","a":an[13],"b":an[6],"value":5.0,"resistance":.01},{"id":"a","kind":"V","a":an[0],"b":an[6],"value":5.0*av,"resistance":.01},{"id":"b","kind":"V","a":nn[0] if week==4 else an[1],"b":an[6],"value":5.0*bv,"resistance":.01}]
  if week==5:sources.append({"id":"c","kind":"V","a":on[1],"b":an[6],"value":5.0*cv,"resistance":.01})
  var solved: Dictionary={}
  for step in 8:
   var parts=sources.duplicate(true)
   for part in board.parts:parts.append_array(Device.expand(Catalog.simulation_entry(part.type),"board/"+part.id,nodes(part.pins),{},voltage,{}))
   solved=solver.solve(parts,Board.wires_only(board),.0005);assert(solved.ok);voltage=solved.v
  var found=Digital.combinational_samples(board,[],solved,week)
  assert(found.any(func(s):return s.row==bits and s.correct))
  observed[bits]=true
 assert(observed.size()==(4 if week==4 else 8))
 board.wires.clear()
 assert(Digital.combinational_samples(board,[],{"ok":true,"v":voltage,"islands":solved_islands(solver)},week).is_empty())
func solved_islands(solver: RefCounted) -> Dictionary:return solver.last.get("islands",{})
func test_binary() -> void:
 var p=pins(1);var board=Board.empty();board.parts=[{"id":"chip","type":"hc08","pins":p}]
 var ns=nodes(p);var solver=preload("res://scripts/electronics_solver.gd").new();var voltage: Dictionary={}
 for value in 16:
  var sources: Array=[{"id":"v","kind":"V","a":ns[13],"b":ns[6],"value":5.0,"resistance":.01}]
  for bit in 4:sources.append({"id":"i%d"%bit,"kind":"V","a":ns[[0,1,3,4][bit]],"b":ns[6],"value":5.0 if value&(1<<bit) else 0.0,"resistance":.01})
  var solved: Dictionary={}
  for step in 3:
   var parts=sources.duplicate(true);parts.append_array(Device.expand(Catalog.simulation_entry("hc08"),"board/chip",ns,{},voltage,{}))
   solved=solver.solve(parts,[],.0005);assert(solved.ok);voltage=solved.v
  var found=Digital.binary_samples(board,solved)
  assert(found.size()==1 and found[0].row==value)
