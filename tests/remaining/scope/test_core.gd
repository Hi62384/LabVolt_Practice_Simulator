extends SceneTree
const Measure = preload("res://scripts/dc_scope/measurements.gd")
var failures := 0
var assertions := 0
func check(ok: bool, message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual-expected)<=tolerance,message+" actual="+str(actual)+" expected="+str(expected))
func _initialize() -> void:call_deferred("run")
func command(station: RefCounted,key: String,value: Variant,channel := -1) -> void:
	var action := {"op":"scope","key":key,"value":value}
	if channel>=0:action.channel=channel
	check(station.apply(action)=="","host command "+key)
func run() -> void:
	var station: RefCounted=preload("res://tests/remaining/scope/core_fixture.gd").station("require-integrated" in OS.get_cmdline_user_args())
	if station==null:quit(1);return
	station.master=true;station.channels[0].enabled=true;station.channels[0].voltage=5;station.generator.enabled=true;station.generator.frequency=20;station.generator.amplitude=2;station.generator.offset=-1
	station.wires=[["CH1-","GND"],["REF","GND"],["CH1+","S1"],["GEN","S2"]]
	command(station,"timebase",0.01)
	command(station,"source",1)
	command(station,"trigger",-1.0)
	for i in 2000:station.step(0.0005)
	var snapshot: Dictionary=station.snapshot()
	var raw_samples: Array=snapshot.samples.duplicate(true)
	var first := Measure.statistics(raw_samples,0,snapshot.scope.channels[0]);var second := Measure.statistics(raw_samples,1,snapshot.scope.channels[1])
	# Independent closed-form DC/AC loading reference: 1 MΩ scope / source resistance.
	near(first.average,5.0*1e6/(1e6+0.01),1e-7,"real CH1 loaded DC")
	near(second.vpp,4.0*1e6/(1e6+50.0),0.03,"real CH2 loaded generator amplitude")
	near(second.frequency,20,0.01,"real circuit frequency")
	check(snapshot.scope_probe.reference_connected and snapshot.scope_probe.signal_connected==[true,true],"actual probe lead diagnostics")
	command(station,"scale",0.5,1);command(station,"position",-1.25,1);command(station,"attenuation",10.0,1)
	check(station.scope.channels[0].scale==2 and station.scope.channels[0].attenuation==1,"CH2 settings do not affect CH1")
	check(station.samples==raw_samples,"scale/position/probe controls never rewrite raw samples")
	var calibrated := Measure.statistics(station.samples,1,station.scope.channels[1])
	near(calibrated.vpp,second.vpp*10,1e-7,"per-channel probe calibration actual data")
	command(station,"running",false)
	var frozen: Array=station.samples.duplicate(true);var before: float=station.solver.time
	for i in 50:station.step(0.0005)
	check(station.samples==frozen,"host Stop freezes acquired record")
	near(station.solver.time-before,0.025,1e-9,"Stop never pauses electrical simulation")
	command(station,"autoset",true)
	check(station.scope.running and station.scope.channels[0].scale!=station.scope.channels[1].scale,"atomic host autoset independently fits channels")
	near(station.scope.timebase,0.01,0.0001,"autoset two actual cycles")
	command(station,"trigger",-10.0);command(station,"source",1);command(station,"single",true)
	for i in 600:station.step(0.0005)
	check(not station.scope.running and not station.scope.single,"real circuit single acquisition completes")
	check(station.snapshot().scope_acquisition.triggered,"single is edge triggered")
	command(station,"enabled",false,1)
	check(not station.scope.channels[1].enabled and station.scope.channels[0].enabled,"independent enable")
	command(station,"coupling","AC",0)
	check(station.scope.channels[0].coupling=="AC" and station.scope.channels[1].coupling=="DC","independent coupling")
	command(station,"scale",3.0)
	check(station.scope.channels[0].scale==3 and station.scope.channels[1].scale==3,"legacy shared control preserved")
	check(station.apply({"op":"scope","channel":-1,"key":"scale","value":2})!="","host rejects forged channel")
	check(station.apply({"op":"scope","channel":1,"key":"scale","value":INF})!="","host rejects invalid numeric")
	check(station.apply({"op":"clear"})=="","clear remains valid")
	station.step(0.0005)
	check(station.scope_capture.rejected_rows==0,"solver reset resets acquisition timestamps")
	print("SCOPE_CORE_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
