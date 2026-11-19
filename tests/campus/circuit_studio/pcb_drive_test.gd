extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")

class MockGame extends Node:
	var session := {"online":false}

class ClockProbe extends RefCounted:
	var calls := 0
	var elapsed := 0.0

	func tick(delta: float) -> Dictionary:
		calls+=1
		elapsed+=delta
		return {"ok":true,"A":0.0,"B":0.0}

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
	_check_world_clock()
	print("PCB_DRIVE_PASS")
	quit()

func _check_world_clock() -> void:
	var world:=World.new()
	var game:=MockGame.new()
	get_root().add_child(game)
	game.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.game=game
	world.placed["test"]={
		"controls":{"A":"hold","B":"toggle"},
		"state":{"A":false,"B":false},
		"effective":{"A":false,"B":false},
		"drive":{"A":"manual","B":"manual"},
		"pcb_voltage":{"A":0.0,"B":0.0},
		"pcb_error":"","features":{"battery":false}
	}
	for fps in [15,30,60,144]:
		var probe:=ClockProbe.new()
		world.simulators["test"]={"runtime":probe,"clock":0.0}
		for frame in fps:
			world._physics_process(1.0/float(fps))
		assert(probe.calls==20 and is_equal_approx(probe.elapsed,1.0),"PCB time differed at %d FPS"%fps)
	var stalled:=ClockProbe.new()
	world.simulators["test"]={"runtime":stalled,"clock":0.0}
	world._physics_process(.53)
	assert(stalled.calls==4,"Lag catch-up exceeded its step budget")
	world._physics_process(0.0)
	world._physics_process(0.0)
	assert(stalled.calls==10 and is_equal_approx(float(world.simulators.test.clock),.03),"Lag catch-up discarded elapsed time")
	print("PCB_WORLD_CLOCK_PASS 15/30/60/144 FPS and 530 ms stall")
	game.free()
