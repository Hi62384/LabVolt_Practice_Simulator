extends SceneTree
func _initialize():
 var B=load("res://scripts/breadboard_model.gd")
 var source=B.empty();source.parts=[{"id":"switch","type":"button","a":"A1","b":"F1"}]
 var inner=B.blueprint(source,"Inner");inner.package="IC";inner.footprint={"width":8,"height":8,"color":"24775b"};inner.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]};inner.exposed=["switch"]
 var middle=B.empty();middle.definitions={"ic:inner":inner};middle.parts=[{"id":"nested","type":"ic:inner","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}]
 var outer=B.blueprint(middle,"Outer");outer.package="IC";outer.footprint={"width":12,"height":10,"color":"24775b"};outer.layout={"rows":30,"parts":middle.parts.duplicate(true),"wires":[]};outer.exposed=["nested"]
 var board=B.empty();board.definitions={"ic:inner":inner,"ic:outer":outer};board.parts=[{"id":"one","type":"ic:outer","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}]
 var canvas=load("res://scripts/breadboard_canvas.gd").new();canvas.board=board
 var controls=canvas.exposed_controls();assert(controls.size()==1);assert(controls[0].id=="board/one/nested/switch");assert(controls[0].center.is_finite())
 var station=load("res://scripts/dc_station.gd").new();assert(station.apply({"op":"board","design":board})=="")
 assert(station.apply({"op":"input","id":controls[0].id,"pressed":true,"hold":true})=="")
 station.step(.0005);assert(station.board.controls[controls[0].id].pressed)
 outer.exposed=[];board.definitions["ic:outer"]=outer;canvas.board=board;assert(canvas.exposed_controls().is_empty())
 outer.exposed=["nested"];inner.exposed=[];board.definitions["ic:outer"]=outer;board.definitions["ic:inner"]=inner;canvas.board=board;assert(canvas.exposed_controls().is_empty())
 canvas.free();print("PASS: recursive package control path, actual input state, finite placement, exposure respected at both levels");quit()
