extends SceneTree
const Digital=preload("res://scripts/campus/academics/digital_evidence.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Device=preload("res://scripts/device_models.gd")
const Library=preload("res://scripts/component_models/library.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
func _initialize():
 var station=preload("res://scripts/dc_station.gd").new()
 station.generator.enabled=true;station.generator.wave="Square";station.generator.frequency=40.0
 station.wires=[["GEN","S1"],["REF","GND"]]
 for i in 600:station.step(.0005)
 assert(not Digital.scope_sample(station).is_empty())
 station.wires=[["GEN","S1"]]
 assert(Digital.scope_sample(station).is_empty())
 var board=Board.empty();var chip_pins: Array=[];var display_pins: Array=[]
 for i in range(1,17):chip_pins.append("A%d"%i)
 for i in range(1,10):display_pins.append("F%d"%i)
 board.parts=[{"id":"decoder","type":"ls47","pins":chip_pins},{"id":"display","type":"seven_segment_ca","pins":display_pins}]
 board.wires=[[chip_pins[15],display_pins[8]]]
 var nodes: Array=chip_pins.map(func(h):return "board/"+Board.node(h,30))
 var dn: Array=display_pins.map(func(h):return "board/"+Board.node(h,30))
 var model: Dictionary=Catalog.all().ls47;var display: Dictionary=Catalog.all().seven_segment_ca
 var solver=preload("res://scripts/electronics_solver.gd").new();var voltage: Dictionary={};var state: Dictionary={}
 for digit in 10:
  var solved: Dictionary={};var parts: Array=[]
  for step in 12:
   parts=[{"id":"vcc","kind":"V","a":nodes[15],"b":nodes[7],"value":5.0,"resistance":.01}]
   for pair in [[6,0],[0,1],[1,2],[5,3]]:
    parts.append({"id":"input%d"%pair[0],"kind":"V","a":nodes[pair[0]],"b":nodes[7],"value":5.0 if digit&(1<<pair[1]) else 0.0,"resistance":.01})
   for pin in [2,3,4]:parts.append({"id":"control%d"%pin,"kind":"V","a":nodes[pin],"b":nodes[7],"value":5.0,"resistance":.01})
   for segment in 7:parts.append({"id":"r%d"%segment,"kind":"R","a":nodes[[12,11,10,9,8,14,13][segment]],"b":dn[segment],"value":330.0})
   parts.append_array(Library.expand(model,"board/decoder",nodes,{},voltage,{"board/decoder":state}).filter(func(p):return p.kind!="stateful"))
   parts.append_array(Device.expand(display,"board/display",dn,{}))
   solved=solver.solve(parts,Board.wires_only(board),.0005)
   assert(solved.ok);voltage=solved.v
   state=Library.tick(model,nodes,voltage,state,.0005,solved.i,"board/decoder")
  var sample=Digital.display_samples(board,[],solved,{"board/decoder":state},parts)
  assert(sample.size()==1 and sample[0].row==digit and sample[0].correct)
  if digit==8:
   var broken=parts.duplicate(true);broken=broken.filter(func(p):return p.id!="r0")
   assert(not Digital.display_samples(board,[],solved,{"board/decoder":state},broken)[0].correct)
 print("PASS DGS connected scope and BCD display evidence")
 quit()
