extends SceneTree
func _initialize():
 var B=load("res://scripts/breadboard_model.gd");var C=load("res://scripts/custom_circuit.gd")
 var source=B.empty();source.parts=[{"id":"switch","type":"button","a":"A1","b":"F1"}]
 var bp=B.blueprint(source,"Exposed button");bp.package="IC";bp.footprint={"width":8,"height":8,"color":"24775b"};bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]};bp.exposed=["switch"]
 var board=B.empty();board.definitions={"ic:test":bp};board.parts=[{"id":"one","type":"ic:test","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}]
 assert(C.validate("ic:test",board.definitions)=="");assert(B.validate(board,{},true)=="")
 var canvas=load("res://scripts/breadboard_canvas.gd").new();canvas.board=board
 assert(canvas.exposed_controls().size()==1)
 var before=B.expand(board)
 board.definitions["ic:test"].exposed=[];canvas.board=board;assert(canvas.exposed_controls().is_empty())
 assert(B.expand(board)==before)
 board.definitions["ic:test"].exposed=["missing"];assert(C.validate("ic:test",board.definitions)!="")
 board.definitions["ic:test"].exposed=["switch"]
 var station=load("res://scripts/dc_station.gd").new();assert(station.apply({"op":"board","design":board})=="")
 assert(station.apply({"op":"input","id":"board/one/switch","hold":true,"pressed":true})=="")
 for i in 700:station.step(.0005)
 assert(station.board.controls["board/one/switch"].pressed)
 assert(station.apply({"op":"input","id":"board/one/switch","hold":true,"pressed":false})=="")
 assert(not station.board.controls["board/one/switch"].pressed)
 canvas.free()
 print("PASS: IC exposed controls, hidden electrical equivalence, invalid exposure rejection, held button duration and release")
 quit()
