extends RefCounted
## Explicit invocation only in an approved isolated runtime; never touches game/session saves.
const Station = preload("res://scripts/dc_station.gd")
const Adapter = preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/control_adapter.gd")

static func run() -> void:
	var benches := [Station.new(),Station.new(),Station.new()]
	var bench = benches[0]
	for action in [{"op":"channel","index":0,"key":"voltage","value":5.0},{"op":"channel","index":0,"key":"limit","value":.1},{"op":"channel","index":0,"key":"enabled","value":true},{"op":"resistor","index":0,"value":100.0},{"op":"master"}]:assert(bench.apply(action)=="")
	for pair in [["CH1+","R1a"],["R1b","A"],["COM","CH1-"],["VΩ","R1a"]]:assert(bench.apply({"op":"wire","a":pair[0],"b":pair[1]})=="")
	for _i in 8:bench.step(.0005)
	assert(bench.result.ok)
	assert(absf(bench.difference("VΩ","COM")-5.0)<.05)
	assert(absf(absf(float(bench.result.i.get("ammeter",0)))-.05)<.002)
	assert(bench.apply({"op":"channel","index":0,"key":"limit","value":.01})=="")
	for _i in 8:bench.step(.0005)
	assert(absf(float(bench.result.i.get("ammeter",0)))<.011)
	assert(bench.result.mode.get("s0","")=="CC")
	bench.meter_mode="Resistance"
	assert(bench.test_measure().begins_with("LIVE"))
	assert(bench.apply({"op":"master"})=="")
	assert(bench.apply({"op":"clear"})=="")
	for pair in [["VΩ","R1a"],["COM","R1b"]]:assert(bench.apply({"op":"wire","a":pair[0],"b":pair[1]})=="")
	assert(absf(bench.test_measure().to_float()-100.0)<.2)
	assert(benches[1].wires.is_empty() and benches[2].wires.is_empty())
	assert(not benches[1].master and not benches[2].master)
	for wave in Adapter.WAVES:
		assert(bench.apply({"op":"generator","key":"wave","value":wave})=="")
		assert(is_finite(bench.source_value(.0125)))
	for key in Adapter.GEN:
		var action := Adapter.action({"op":"generator","key":key},bench.snapshot())
		assert(bench.apply(action)=="")
		assert(is_equal_approx(float(bench.generator[key]),float(action.value)))
	for channel in 3:
		var action := Adapter.action({"op":"channel","index":channel,"key":"enabled"},bench.snapshot())
		assert(bench.apply(action)=="")
	for key in ["timebase","trigger","source","edge","trigger_mode"]:
		assert(bench.apply(Adapter.action({"op":"scope","key":key},bench.snapshot()))=="")
	for channel in 2:
		for key in ["scale","position","coupling","attenuation","enabled"]:
			assert(bench.apply(Adapter.action({"op":"scope","key":key,"channel":channel},bench.snapshot()))=="")
	var saved: Dictionary=bench.snapshot()
	var restored := Station.new();restored.restore_scope(saved.scope)
	assert(restored.scope==bench.scope)
	assert(bench.apply({"op":"wire","a":"bad","b":"COM"})!="")
	assert(bench.apply({"op":"channel","index":3,"key":"voltage","value":5})!="")
