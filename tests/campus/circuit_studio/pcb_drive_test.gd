extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var source:=Board.empty()
	source.parts=[{"id":"gate","type":"toggle","a":"A1","b":"A2"},{"id":"pull","type":"r1000","a":"A2","b":"F1"}]
	var bp: Dictionary=Board.blueprint(source,"Drive PCB")
	bp.package="PCB";bp.footprint={"width":8,"height":8,"color":"24775b"}
	bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
	bp.pins=[{"name":"VCC","node":"L1"},{"name":"GND","node":"R1"},{"name":"OUT_A","node":"L2"}]
	var defs: Dictionary={"ic:drive_test":bp}
	assert(Custom.validate("ic:drive_test",defs)=="")
	var runtime:=Runtime.new()
	assert(runtime.configure("ic:drive_test",defs,{"power":0,"ground":1,"A":2,"B":-1}))
	var low: Dictionary=runtime.tick(.01)
	assert(low.ok and float(low.A)<1.0,str(low))
	assert(runtime.input("board/pcb/gate",true))
	var high: Dictionary=runtime.tick(.01)
	assert(high.ok and float(high.A)>2.5,str(high))
	assert(runtime.input("board/pcb/gate",true))
	var off: Dictionary=runtime.tick(.01)
	assert(off.ok and float(off.A)<1.0,str(off))
	var with_io: Dictionary=source.duplicate(true)
	with_io.parts.append({"id":"encoder","type":"io_encoder","a":"A3","b":"A4","pins":["A3","A4","A5"]})
	var io_bp: Dictionary=Board.blueprint(with_io,"Controller PCB")
	io_bp.package="PCB";io_bp.footprint={"width":8,"height":8,"color":"24775b"}
	io_bp.layout={"rows":30,"parts":with_io.parts.duplicate(true),"wires":[]}
	io_bp.pins=bp.pins.duplicate(true)
	var io_defs: Dictionary={"ic:io_test":io_bp}
	assert(Custom.validate("ic:io_test",io_defs)=="")
	var io_runtime:=Runtime.new()
	assert(io_runtime.configure("ic:io_test",io_defs,{"power":0,"ground":1,"A":2,"B":-1}))
	assert(io_runtime.inputs.any(func(entry):return entry.id=="board/pcb/encoder" and entry.kind=="io_encoder"))
	assert(io_runtime.input("board/pcb/encoder",true,false,{"op":"turn","steps":1}))
	assert(io_runtime.station.board.io_controls["board/pcb/encoder"].detent==1)
	var start:=Time.get_ticks_usec()
	for i in 80:runtime.tick(.05)
	print("PCB_DRIVE_80_TICKS_MS ",(Time.get_ticks_usec()-start)/1000.0)
	print("PCB_DRIVE_PASS")
	quit()
