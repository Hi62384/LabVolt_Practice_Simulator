extends SceneTree
## Exercises a real manufactured PCB through the world invention runtime and
## the DC station solver. Do not replace this with hand-computed mock voltages.
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")

var failures:=0

func check(ok: bool,label: String) -> void:
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func _initialize() -> void:
	var source: Dictionary=Board.empty()
	# The pins L1/L2/R1 share the first two upper/lower breadboard rows
	# with A1/A2/F1 respectively. A real 10 uF capacitor charges through
	# a 1 kΩ resistor, with a 10 ms expected time constant.
	source.parts=[
		{"id":"feed","type":"r1000","a":"A1","b":"A2"},
		{"id":"storage","type":"c10.0","a":"A2","b":"F1"}
	]
	var bp: Dictionary=Board.blueprint(source,"RC transient verification")
	bp.package="PCB"
	bp.footprint={"width":8,"height":8,"color":"24775b"}
	bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
	bp.pins=[
		{"name":"VCC","node":"L1"},
		{"name":"GND","node":"R1"},
		{"name":"OUT_A","node":"L2"}
	]
	var defs: Dictionary={"ic:rc_transient":bp}
	check(Custom.validate("ic:rc_transient",defs)=="","PCB definition is valid")
	if failures>0:quit(1);return
	var rt:=Runtime.new()
	check(rt.configure("ic:rc_transient",defs,{"power":0,"ground":1,"A":2,"B":-1}),"Mounted PCB configured")
	if failures>0:quit(1);return
	var start:=Time.get_ticks_usec()
	var measured: Dictionary=rt.tick(.05)
	var duration_ms:=float(Time.get_ticks_usec()-start)/1000.0
	var expected:=5.0*(1.0-exp(-5.0))
	check(measured.get("ok",false),"The mounted PCB simulation converges: "+str(measured.get("error","")))
	if measured.get("ok",false):
		check(absf(float(measured.A)-expected)<0.05,
			"RC charging after 50 ms is near the reference transient, got "+str(measured.A))
	check(absf(rt.station.solver.time-.05)<1e-7,"Internal simulation advances exactly 50 ms")
	var settled: Dictionary=rt.tick(.05)
	check(settled.get("ok",false) and float(settled.get("A",0.0))>4.95,
		"RC output settles near 5 V rather than restarting every world tick")
	check(absf(rt.station.solver.time-.1)<1e-7,"Consecutive mounted PCB ticks preserve solver time")
	var failure: Dictionary=rt.tick(-.5)
	check(not failure.get("ok",true),"Negative time is rejected")

	# Verify actual LV Micro firmware executes inside a mounted invention PCB;
	# ordinary lab-only controller tests do not cover this nested route.
	var cpu_board: Dictionary=Board.empty()
	cpu_board.parts=[{
		"id":"cpu","type":"lv_mcu","a":"A1","b":"F1",
		"pins":["A1","F1","A2","F2","A3","F3"],
		"firmware":"mode D0 out\nwrite D0 1\nwait 200\nwrite D0 0\nhalt"
	}]
	var cpu_bp: Dictionary=Board.blueprint(cpu_board,"Mounted CPU")
	cpu_bp.package="PCB"
	cpu_bp.footprint={"width":8,"height":8,"color":"24775b"}
	cpu_bp.layout={"rows":30,"parts":cpu_board.parts.duplicate(true),"wires":[]}
	cpu_bp.pins=[
		{"name":"VCC","node":"L1"},
		{"name":"GND","node":"R1"},
		{"name":"OUT_A","node":"L2"}
	]
	# The external ground must connect to CPU pin GND (index 1), and
	# OUT_A must connect to CPU pin D0 (index 2). The previous fixture
	# accidentally mapped them to D1 and GND, producing a false reading.
	check(Board.node(str(cpu_board.parts[0].pins[1]))==str(cpu_bp.pins[1].node)
		and Board.node(str(cpu_board.parts[0].pins[2]))==str(cpu_bp.pins[2].node),
		"Mounted CPU external ground and D0 outputs are correctly routed")
	var cpu_defs: Dictionary={"ic:mounted_cpu":cpu_bp}
	check(Custom.validate("ic:mounted_cpu",cpu_defs)=="","Programmed MCU PCB definition is valid")
	if failures==0:
		var cpu:=Runtime.new()
		check(cpu.configure("ic:mounted_cpu",cpu_defs,{"power":0,"ground":1,"A":2,"B":-1}),"Mounted MCU initializes")
		if failures==0:
			var output: Dictionary=cpu.tick(.05)
			check(output.get("ok",false) and float(output.get("A",0.0))>2.5,
				"Firmware writes D0 high on the real mounted PCB circuit")
			for index in 5:output=cpu.tick(.05)
			check(output.get("ok",false) and float(output.get("A",5.0))<1.0,
				"Firmware wait and write pull D0 low in the mounted circuit")
	print("MOUNTED_PCB_TRANSIENT %s (%.3f ms first world tick, %d failures)" %
		["PASS" if failures==0 else "FAIL",duration_ms,failures])
	quit(1 if failures>0 else 0)
