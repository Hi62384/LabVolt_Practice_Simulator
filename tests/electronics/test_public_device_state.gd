extends SceneTree
func _initialize():
 var station=load("res://scripts/dc_station.gd").new();var board=load("res://scripts/breadboard_model.gd").empty()
 board.parts=[{"id":"screen","type":"io_graphic","a":"A1","b":"F1","pins":["A1","F1","A2","F2","A3"]},{"id":"nv","type":"eeprom25","a":"A4","b":"F4","pins":["A4","F4","A5","F5","A6","F6","A7","F7"]}]
 station.board=board;station.board.component_runtime={"board/nv":{"memory":{"0":165}}}
 station.firmware_states={"board/screen":{"powered":true,"cells":[1,2],"bits":7,"shift":33,"control":{}},"board/nv":{"powered":true,"memory":{"0":165},"pending":{"17":44},"bits":7,"word":33,"command":3,"shift":9,"drive":{}}}
 var packet=station.snapshot()
 assert(packet.firmware["board/screen"].cells==[1,2])
 assert(not packet.firmware["board/screen"].has("bits") and not packet.firmware["board/screen"].has("shift"))
 for private_field in ["memory","pending","bits","word","command","shift"]:assert(not packet.firmware["board/nv"].has(private_field))
 assert(not packet.board.has("component_runtime"))
 assert(station.firmware_states["board/nv"].memory["0"]==165)
 assert(station.board.component_runtime["board/nv"].memory["0"]==165)
 print("PASS: observable display state published; parser and EEPROM bytes withheld; host state unchanged")
 quit()
