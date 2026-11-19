extends SceneTree
const Solver=preload("res://scripts/electronics_solver.gd")
func _initialize() -> void:
	var parts: Array=[{"id":"s","kind":"supply","a":"P","b":"N","value":5.0,"limit":1.0,"resistance":.01}]
	for i in 60:parts.append({"id":"r%d"%i,"kind":"R","a":"P" if i==0 else "n%d"%i,"b":"N" if i==59 else "n%d"%(i+1),"value":220.0})
	parts.append({"id":"led","kind":"LED","a":"n6","b":"n7","vf":1.8,"ron":10.0})
	var fallback=Solver.new()
	fallback.use_csharp=false
	var native=Solver.new()
	assert(native.linear_kernel!=null)
	for changing in [false,true]:
		var samples := [[], []]
		for trial in 6:
			for index in [trial % 2, 1 - trial % 2]:
				var solver= [fallback,native][index]
				solver.reset()
				var started:=Time.get_ticks_usec()
				for i in 100:
					parts[1].value=220.0+0.01*i if changing else 220.0
					var result: Dictionary=solver.solve(parts,[],.001)
					assert(result.ok)
				if trial>0:samples[index].append(Time.get_ticks_usec()-started)
		for trial in 3:
			parts[1].value=220.0+0.012*trial if changing else 220.0
			var expected: Dictionary=fallback.solve(parts,[],.001)
			var actual: Dictionary=native.solve(parts,[],.001)
			for field in ["v","i","drop"]:
				for id in expected[field]:
					assert(absf(expected[field][id]-actual[field][id])<1e-10)
		for values in samples:values.sort()
		print("Full circuit x100 (%s) GDScript %d us, native %d us" %
			["changing matrix" if changing else "cached matrix",samples[0][2],samples[1][2]])
	print("MNA_FULL_BENCHMARK PASS")
	quit()
