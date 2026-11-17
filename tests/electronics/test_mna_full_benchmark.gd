extends SceneTree
const Solver=preload("res://scripts/electronics_solver.gd")
func _initialize() -> void:
	var parts: Array=[{"id":"s","kind":"supply","a":"P","b":"N","value":5.0,"limit":1.0,"resistance":.01}]
	for i in 60:parts.append({"id":"r%d"%i,"kind":"R","a":"P" if i==0 else "n%d"%i,"b":"N" if i==59 else "n%d"%(i+1),"value":220.0})
	parts.append({"id":"led","kind":"LED","a":"n6","b":"n7","vf":1.8,"ron":10.0})
	var times:={}
	for csharp in [false,true]:
		var solver=Solver.new();solver.use_csharp=csharp
		assert(solver.solve(parts,[],.001).ok)
		var started:=Time.get_ticks_usec()
		for i in 100:
			var result: Dictionary=solver.solve(parts,[],.001)
			assert(result.ok)
		times["csharp" if csharp else "gdscript"]=Time.get_ticks_usec()-started
	print("full circuit x100 GDScript ",times.gdscript," us; C# kernel ",times.csharp," us")
	quit()
