extends SceneTree
func _initialize():
 var B=load("res://scripts/breadboard_model.gd");var C=load("res://scripts/custom_circuit.gd")
 var source=B.empty();source.parts=[{"id":"switch","type":"toggle","a":"A1","b":"F1"}]
 var bp=B.blueprint(source,"Switch PCB");bp.package="PCB";bp.footprint={"width":8,"height":8,"color":"24775b"};bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
 var defs={"ic:test":bp};assert(C.validate("ic:test",defs)=="")
 var bad=defs.duplicate(true);bad["ic:test"].layout.parts=[null];assert(C.validate("ic:test",bad)!="")
 bad=defs.duplicate(true);bad["ic:test"].layout.wires=[["A1"]];assert(C.validate("ic:test",bad)!="")
 var board=B.empty();board.definitions=defs;board.parts=[{"id":"one","type":"ic:test","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]},{"id":"two","type":"ic:test","a":"A12","b":"F12","pins":["A12","F12","A13","F13"]}]
 assert(B.validate(board,{},true)=="")
 var station=load("res://scripts/dc_station.gd").new();assert(station.apply({"op":"board","design":board})=="")
 assert(station.apply({"op":"input","id":"board/one/switch"})=="")
 assert(station.board.controls["board/one/switch"].pressed)
 assert(not station.board.controls.has("board/two/switch"));assert(not defs["ic:test"].parts[0].pressed)
 var canvas=load("res://scripts/breadboard_canvas.gd").new();canvas.board=station.board
 assert(canvas.exposed_controls().size()==2);canvas.free()
 print("PASS: PCB layout validation, independent nested controls, immutable definitions, physical control discovery")
 quit()
