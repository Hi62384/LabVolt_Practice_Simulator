extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")

class MockGame extends Node:
	var session := {"online":false}

class ThresholdProbe extends RefCounted:
	var values := [2.499,2.501,2.499]
	var calls := 0
	func tick(_dt: float) -> Dictionary:
		var value: float=float(values[mini(calls,values.size()-1)])
		calls+=1
		return {"ok":true,"A":value,"B":0.0}

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
	await _check_hinge()
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
	# Motor drive must update when a PCB voltage crosses 2.5 V by less than
	# the normal 10 mV voltage-publication deadband.
	world.placed.test.drive.A="pcb"
	world.placed.test.pcb_voltage.A=0.0
	world.placed.test.effective.A=false
	var edge:=ThresholdProbe.new()
	world.simulators.test={"runtime":edge,"clock":0.0}
	world._physics_process(.05)
	assert(not world.placed.test.effective.A,"2.499 V should leave PCB drive off")
	world._physics_process(.05)
	assert(world.placed.test.effective.A,"2.501 V must activate PCB drive")
	world._physics_process(.05)
	assert(not world.placed.test.effective.A,"2.499 V must deactivate PCB drive")
	game.free()

func _check_hinge() -> void:
	var game:=MockGame.new()
	var world:=World.new()
	root.add_child(game)
	game.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.game=game
	var parts: Array = [
		{"type":"servo","x":0,"y":0,"z":1,"control":"A"},
		{"type":"hinge","x":0,"y":0,"z":0},
		{"type":"wood_frame","x":0,"y":0,"z":-1},
		{"type":"plastic_shell","x":0,"y":0,"z":-2}
	]
	var joints:=Model.hinges(parts)
	assert(joints.size()==1 and joints[0].indices==[2,3] and joints[0].control=="A")
	var passive:=parts.duplicate(true)
	passive[0].type="wood_frame"
	assert(Model.hinges(passive)[0].control=="")
	var locked:=parts.duplicate(true)
	for z in [-1,0,1]:locked.append({"type":"wood_frame","x":1,"y":0,"z":z})
	assert(Model.hinges(locked).is_empty())
	var item := {
		"name":"Servo hinge", "position":Vector3(0,2,0),"parts":parts,"angle":0.0,"yaw":0.0,
		"controls":{"A":"toggle","B":"toggle"},"state":{"A":true,"B":false},"effective":{"A":false,"B":false},
		"drive":{"A":"manual","B":"manual"},"pcb_voltage":{"A":0.0,"B":0.0},"pcb_error":"",
		"features":{"battery":true},"hinge_angles":{}
	}
	world.placed.test=item
	world.visuals.test=world._create_view("test",item)
	var joint: Dictionary=world.visuals.test.get_meta("joints")[0]
	var moving: Node3D=joint.bindings[0].node
	var collider: CollisionShape3D=joint.bindings[1].node
	var origin := moving.position
	for i in 60:world._physics_process(1.0/60.0)
	assert(is_equal_approx(item.hinge_angles[0],Model.HINGE_OPEN))
	assert(not moving.position.is_equal_approx(origin) and moving.transform.is_equal_approx(collider.transform))
	item.features.battery=false
	for i in 60:world._physics_process(1.0/60.0)
	assert(moving.position.is_equal_approx(origin) and is_zero_approx(item.hinge_angles[0]))
	var wall:=StaticBody3D.new()
	game.add_child(wall)
	wall.position=Vector3(-.28,2.36,-.15)
	var wall_shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(.18,.25,.2)
	wall_shape.shape=box
	wall.add_child(wall_shape)
	await physics_frame
	await physics_frame
	assert(not world._hinge_clear(world.visuals.test,joint,Model.HINGE_OPEN))
	# Place the child hinge first in the blueprint to exercise order independence.
	var chain_parts: Array=[
		{"type":"hinge","x":0,"y":0,"z":-2},
		{"type":"servo","x":0,"y":0,"z":-1,"control":"B"},
		{"type":"wood_frame","x":0,"y":0,"z":-3},
		parts[0],parts[1],
	]
	var chain:=item.duplicate(true)
	chain.position=Vector3(8,2,0)
	chain.parts=chain_parts
	chain.features.battery=true
	chain.state.B=true
	chain.hinge_angles={}
	world.placed.chain=chain
	world.visuals.chain=world._create_view("chain",chain)
	var chain_joints: Array=world.visuals.chain.get_meta("joints")
	assert(chain_joints[0].chain==[1,0] and chain_joints[1].chain==[1])
	var tip: Dictionary=chain_joints[0].bindings[0]
	for i in 60:world._physics_process(1.0/60.0)
	var parent_pose:=Model.hinge_transform(Transform3D.IDENTITY,chain_joints[1].pivot,Model.HINGE_OPEN)
	var child_pose:=Model.hinge_transform(Transform3D.IDENTITY,chain_joints[0].pivot,Model.HINGE_OPEN)
	assert(tip.node.transform.is_equal_approx(parent_pose*child_pose*tip.rest))
	assert(chain_joints[0].bindings[1].node.transform.is_equal_approx(tip.node.transform))
	chain.state.B=false
	for i in 60:world._physics_process(1.0/60.0)
	assert(tip.node.transform.is_equal_approx(parent_pose*tip.rest))
	# The ancestor's clearance check must include the distant descendant tip.
	wall.global_position=tip.node.global_position
	await physics_frame
	await physics_frame
	assert(not world._hinge_clear(world.visuals.chain,chain_joints[1],Model.HINGE_OPEN))
	print("CHAINED_HINGE_PASS")
	print("ARTICULATED_HINGE_PASS")
	game.free()
