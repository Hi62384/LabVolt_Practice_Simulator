extends SceneTree
func _initialize():
 var B=load("res://scripts/breadboard_model.gd")
 var source=B.empty();source.parts=[{"id":"cpu","type":"lv_mcu","a":"A1","b":"A2","pins":["A1","A2","A3","A4","A5","A6"],"firmware":"halt"}]
 var bp=B.blueprint(source,"Controller")
 var board=B.empty();board.definitions={"ic:cpu":bp};board.parts=[{"id":"one","type":"ic:cpu","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]},{"id":"two","type":"ic:cpu","a":"A10","b":"F10","pins":["A10","F10","A11","F11"]}]
 board.programs={"board/one/cpu":{"firmware":"mode D0 out\nwrite D0 1\nhalt","run":true}}
 assert(B.validate(board,{},true)=="")
 var expanded=B.expand(board);var controllers=expanded.parts.filter(func(p):return p.kind=="controller")
 assert(controllers.size()==2);assert(controllers[0].source.begins_with("mode D0"));assert(controllers[1].source=="halt");assert(bp.parts[0].firmware=="halt")
 var encoded=JSON.stringify(board);var restored=JSON.parse_string(encoded);assert(B.validate(restored,{},true)=="");assert(B.expand(restored).parts.filter(func(p):return p.kind=="controller")[0].source==controllers[0].source)
 board.programs["board/one/cpu"].firmware="execute malicious";assert(B.validate(board,{},true)!="")
 print("PASS: per-instance embedded firmware, independent copies, JSON persistence, invalid upload rejection")
 quit()
