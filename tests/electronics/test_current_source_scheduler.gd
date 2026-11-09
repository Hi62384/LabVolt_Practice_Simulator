extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	var lab=game.dc_lab;lab.set_process(false)
	var station=lab.benches[0]
	assert(not station.master and station.board.is_empty())
	station.resistance[0]=1000.
	station.wires=[["IS+","R1a"],["IS-","R1b"],["IS4+","R1a"],["IS4-","R1b"]]
	for source_index in [0,3]:
		station.solver.reset();station.meter_samples.clear();lab.accumulator=0
		station.current_source.enabled=source_index==0
		for i in station.auxiliary_sources.size():station.auxiliary_sources[i].enabled=i+1==source_index
		lab._process(.01)
		assert(absf(float(station.result.get("drop",{}).get("r0",0)))<.000001,"Master OFF must isolate enabled sources")
		station.master=true;station.meter_samples.clear();station.solver.reset();lab.accumulator=0
		lab._process(.01)
		assert(absf(float(station.result.drop.r0)-10.)<.001,"Enabled current source must drive the actual resistor")
		assert(station.meter_samples.size()==20,"Active independent sources require twenty 0.5 ms steps per 10 ms frame")
		assert(is_equal_approx(station.solver.time,.01))
		station.master=false
	station.current_source.enabled=false
	for source in station.auxiliary_sources:source.enabled=false
	game.queue_free();await process_frame
	print("PASS: primary and fourth independent current-source channels respect master isolation and fixed-step energized timing")
	quit()
