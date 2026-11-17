extends SceneTree
func _initialize():
 var catalog=load("res://scripts/electronics_catalog.gd")
 var entry: Dictionary=catalog.simulation_entry("button_nc")
 assert(entry.name=="Normally closed pushbutton" and entry.normally_closed)
 assert(load("res://scripts/breadboard_model.gd").manual_input_type("button_nc")=="button")
 var model=load("res://scripts/device_models.gd")
 assert(model.expand(entry,"switch",["a","b"],{})[0].value==.01)
 assert(model.expand(entry,"switch",["a","b"],{"pressed":true})[0].value==1e12)
 assert(model.expand(entry,"switch",["a","b"],{"pressed":false})[0].value==.01)
 var no: Dictionary=catalog.simulation_entry("button")
 assert(model.expand(no,"switch",["a","b"],{})[0].value==1e12)
 assert(model.expand(no,"switch",["a","b"],{"pressed":true})[0].value==.01)
 var board=load("res://scripts/breadboard_model.gd").empty()
 board.parts=[{"id":"s","type":"button_nc","a":"A1","b":"A3"}]
 assert(load("res://scripts/breadboard_model.gd").validate(board,{},true)=="")
 var station=load("res://scripts/dc_station.gd").new();station.board=board
 assert(station.apply({"op":"input","id":"board/s","pressed":true,"hold":true})=="")
 assert(station.board.controls["board/s"].pressed)
 assert(station.apply({"op":"input","id":"board/s","pressed":false,"hold":true})=="")
 assert(not station.board.controls["board/s"].pressed)
 print("PASS normally closed and normally open button behavior")
 quit()
