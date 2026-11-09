extends SceneTree
func _initialize():
 var S=load("res://scripts/dc_station.gd");var B=load("res://scripts/breadboard_model.gd")
 var s=S.new();var board=B.empty();board.parts=[{"id":"speaker","type":"speaker","a":"A1","b":"F1"}];board.ports=["A1","F1","A2","F2"]
 assert(s.apply({"op":"board","design":board})=="")
 s.wires=[["GEN","B1"],["REF","B2"]];s.generator.enabled=true;s.generator.frequency=100;s.generator.amplitude=1.
 for i in 600:s.step(.0005)
 assert(s.result.audio.has("board/speaker"));assert(s.result.audio["board/speaker"].size()==512)
 var peak=0.
 for frame in s.result.audio["board/speaker"]:peak=maxf(peak,absf(frame[1]))
 assert(abs(peak-8./58.)<.001)
 assert(abs(float(s.result.i["board/speaker"])*8.-s.result.audio["board/speaker"][-1][1])<.000001)
 print("PASS: passive speaker voltage history is derived from actual loaded circuit and bounded to 512 samples")
 quit()
