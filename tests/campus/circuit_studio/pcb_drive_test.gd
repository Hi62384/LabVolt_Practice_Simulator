extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")

class MockGame extends Node:
	var session := {"online":false,"roster":{1:true,2:true},"poses":{2:{"position":Vector3.ZERO}}}
	var player := Node3D.new()

class InputProbe extends RefCounted:
	var accept := true
	var calls: Array=[]
	func input(id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> bool:
		calls.append({"id":id,"pressed":pressed,"reverse":reverse,"command":command.duplicate(true)})
		return accept

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
	# Identical PCB nets on different pins are still a direct source short.
	var bad_bp: Dictionary=bp.duplicate(true)
	bad_bp.pins[1].node=bad_bp.pins[0].node
	var bad_definitions: Dictionary={"ic:short_supply":bad_bp}
	assert(Custom.validate("ic:short_supply",bad_definitions)=="")
	var valid_map: Dictionary={"power":0,"ground":1,"A":2,"B":-1}
	assert(Model.validate_pcb_pin_map(bad_bp,valid_map).contains("electrical nets"))
	assert(not Runtime.new().configure("ic:short_supply",bad_definitions,valid_map))
	# Two independently named external pins can still share one electrical
	# net through a straight internal jumper; the solver sees an ideal short.
	var wired_short: Dictionary=bp.duplicate(true)
	wired_short.wires=[["L1","R1"]]
	var wired_definitions: Dictionary={"ic:wired_short":wired_short}
	assert(Custom.validate("ic:wired_short",wired_definitions)=="")
	assert(Model.validate_pcb_pin_map(wired_short,valid_map).contains("electrical nets"),
		"A direct internal jumper must count as a supply short")
	assert(not Runtime.new().configure("ic:wired_short",wired_definitions,valid_map),
		"Mounted PCB must refuse a supply short through internal wiring")
	assert(not Runtime.new().configure("ic:drive_test",defs,{"power":0,"ground":1,"A":99,"B":-1}))
	var invention: Dictionary=Model.empty("PCB-controlled machine")
	invention.parts.append_array([
		{"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""},
		{"type":"servo","x":0,"y":1,"z":0,"control":"A","ref":""},
		{"type":"pcb","x":2,"y":0,"z":0,"control":"","ref":"ic:short_supply","pin_map":valid_map.duplicate()}
	])
	invention.drive.A="pcb"
	assert(Model.validate("inv:short",{"inv:short":invention},bad_definitions).contains("electrical nets"),
		"Fabrication allowed PCB power and ground on the same conductive net")
	invention.parts[-1].ref="ic:drive_test"
	assert(Model.validate("inv:working",{"inv:working":invention},defs)=="",
		"Valid PCB-driven servo invention should still be manufacturable")
	# Two physical switches on the same channel are valid invention parts.
	# Both must be clickable and animate instead of only the first one.
	var dual: Dictionary=Model.empty("Dual-channel switches")
	dual.parts.append_array([
		{"type":"switch","x":1,"y":0,"z":0,"control":"A","ref":""},
		{"type":"switch","x":2,"y":0,"z":0,"control":"A","ref":""}
	])
	assert(Model.validate("inv:dual",{"inv:dual":dual},{})=="",
		"Multiple switches for the same channel must remain manufacturable")
	var switch_game:=MockGame.new()
	root.add_child(switch_game)
	switch_game.add_child(switch_game.player)
	var switch_world:=World.new()
	switch_game.add_child(switch_world)
	switch_world.game=switch_game
	switch_world.set_process(false)
	switch_world.set_physics_process(false)
	var dual_item: Dictionary={
		"name":"Dual-channel switches","position":Vector3.ZERO,
		"parts":Model.flattened("inv:dual",{"inv:dual":dual},{}),
		"drive":dual.drive.duplicate(true),"controls":dual.controls.duplicate(true),
		"state":{"A":false,"B":false},"effective":{"A":false,"B":false},
		"features":{"switch_a":true,"switch_b":false,"battery":false},
		"yaw":0.0,"angle":0.0,"hinge_angles":{}
	}
	switch_world.placed["dual"]=dual_item
	var physical: StaticBody3D=switch_world._create_view("dual",dual_item)
	switch_world.visuals["dual"]=physical
	var buttons: Array=physical.find_children("ControlA*","",true,false)
	assert(buttons.size()==2,"Second channel-A switch is invisible or cannot be clicked")
	for button in buttons:
		assert(button.get_meta("role")=="invention_control" and button.get_meta("control")=="A"
			and button.get_meta("invention_key")=="dual",
			"Both physical switches must route to their real channel and instance")
	dual_item.state.A=true
	switch_world._process(0.02)
	for button in buttons:
		assert(is_equal_approx(button.position.y,.10),
			"All switches on a shared control channel must show the pressed state")
	switch_game.queue_free()
	var runtime:=Runtime.new()
	assert(runtime.configure("ic:drive_test",defs,{"power":0,"ground":1,"A":2,"B":-1}))
	var rejected:=Runtime.new()
	assert(rejected.configure("ic:drive_test",defs,valid_map))
	assert(not rejected.configure("ic:drive_test",defs,{"power":0,"ground":0,"A":2,"B":-1}))
	assert(not rejected.tick(.01).get("ok",false) and rejected.inputs.is_empty(),
		"A rejected remap must disable the previously running PCB and its controls")
	assert(not rejected.input("board/pcb/gate",true),"Stale PCB inputs remained live after a rejected remap")
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
	_check_pcb_servo_integration(defs)
	_check_input_leases()
	_check_disconnect_releases()
	await _check_hinge()
	print("PCB_DRIVE_PASS")
	quit()


func _check_pcb_servo_integration(definitions: Dictionary) -> void:
	# Exercise a real PCB's electrical toggle, a valid nested power mapping,
	# the authoritative multiplayer input reducer, and the physical servo
	# hinge through the same placed-world physics loop as actual gameplay.
	var game:=MockGame.new()
	root.add_child(game)
	game.add_child(game.player)
	game.player.position=Vector3(12,2,0)
	var world:=World.new()
	game.add_child(world)
	world.game=game
	world.set_process(false)
	world.set_physics_process(false)
	var design: Dictionary=Model.empty("PCB servo end-to-end")
	design.parts=[
		{"type":"servo","x":0,"y":0,"z":1,"control":"A","ref":""},
		{"type":"hinge","x":0,"y":0,"z":0,"control":"","ref":""},
		{"type":"wood_frame","x":0,"y":0,"z":-1,"control":"","ref":""},
		{"type":"plastic_shell","x":0,"y":0,"z":-2,"control":"","ref":""},
		{"type":"battery","x":2,"y":0,"z":0,"control":"","ref":""},
		{"type":"pcb","x":3,"y":0,"z":0,"control":"","ref":"ic:drive_test",
			"pin_map":{"power":0,"ground":1,"A":2,"B":-1}}
	]
	design.drive.A="pcb"
	var designs: Dictionary={"inv:integrated":design}
	assert(Model.validate("inv:integrated",designs,definitions)=="",
		"PCB-controlled mechanical invention must validate before fabrication")
	var parts: Array=Model.flattened("inv:integrated",designs,definitions)
	var runtime:=Runtime.new()
	assert(runtime.configure("ic:drive_test",definitions,{"power":0,"ground":1,"A":2,"B":-1}))
	var item: Dictionary={
		"owner":1,"id":"inv:integrated","name":design.name,"parts":parts,
		"position":Vector3(12,2,0),"yaw":0.0,"angle":0.0,"hinge_angles":{},
		"controls":design.controls.duplicate(true),"drive":design.drive.duplicate(true),
		"state":{"A":false,"B":false},"effective":{"A":false,"B":false},
		"pcb_voltage":{"A":0.0,"B":0.0},"pcb_error":"",
		"pcb_inputs":runtime.inputs.duplicate(true),
		"features":{"battery":true,"switch_a":false,"switch_b":false}
	}
	world.placed["integrated"]=item
	world.visuals["integrated"]=world._create_view("integrated",item)
	world.simulators["integrated"]={"runtime":runtime,"clock":0.0}
	var joints: Array=world.visuals["integrated"].get_meta("joints",[])
	assert(joints.size()==1 and joints[0].control=="A",
		"The fabricated servo must connect to the moving hinge")
	for step in 20:world._physics_process(.05)
	assert(not item.effective.A and absf(float(item.hinge_angles.get(0,0)))<.01,
		"The unpressed PCB switch must not move the hinge")
	var press: Dictionary={"op":"pcb_input","key":"integrated",
		"id":"board/pcb/gate","pressed":true}
	world._apply(1,press)
	for step in 20:world._physics_process(.05)
	assert(item.effective.A and float(item.pcb_voltage.A)>2.5
		and float(item.hinge_angles.get(0,0))>Model.HINGE_OPEN-.01,
		"PCB output must actually open the placed invention's servo hinge")
	world._apply(1,press)
	for step in 20:world._physics_process(.05)
	assert(not item.effective.A and float(item.pcb_voltage.A)<1.0
		and absf(float(item.hinge_angles.get(0,0)))<.01,
		"Switching the PCB off must close the placed invention's hinge")
	game.free()
	print("PCB_SERVO_INTEGRATION_PASS")

func _check_input_leases() -> void:
	var game:=MockGame.new()
	root.add_child(game)
	game.add_child(game.player)
	var world:=World.new()
	game.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.game=game
	var probe:=InputProbe.new()
	world.placed["fixture"]={
		"position":Vector3.ZERO,
		"pcb_inputs":[{"kind":"io_joystick","id":"board/joy"}]
	}
	world.simulators["fixture"]={"runtime":probe}
	var press: Dictionary={"op":"pcb_input","key":"fixture","id":"board/joy","pressed":true,
		"command":{"op":"press","pressed":true}}
	probe.accept=false
	world._apply(1,press)
	assert(world.pcb_holders.is_empty(),"A rejected PCB input must not acquire an exclusive control lease")
	probe.accept=true
	var contradictory: Dictionary=press.duplicate(true)
	contradictory.command={"op":"press","pressed":false}
	world._apply(1,contradictory)
	assert(probe.calls.is_empty() and world.pcb_holders.is_empty(),
		"Released joystick hardware must not acquire an exclusive pressed lease")
	world._apply(1,press)
	assert(world.pcb_holders.has("fixture|board/joy:"),"Valid joystick press did not acquire a lease")
	var move: Dictionary={"op":"pcb_input","key":"fixture","id":"board/joy","pressed":true,
		"command":{"op":"move","x":0.9,"y":0.1}}
	var before: int=probe.calls.size()
	world._apply(2,move)
	assert(probe.calls.size()==before,"A second player moved another player's held joystick")
	world._apply(1,move)
	assert(probe.calls.size()==before+1,"The joystick's holder could not move its own axes")
	var forged_release: Dictionary={"op":"pcb_input","key":"fixture","id":"board/joy","pressed":true,
		"command":{"op":"release"}}
	before=probe.calls.size()
	world._apply(2,forged_release)
	assert(probe.calls.size()==before and world.pcb_holders.has("fixture|board/joy:"),
		"A forged release bypassed another player's joystick lease")
	var release: Dictionary={"op":"pcb_input","key":"fixture","id":"board/joy","pressed":false,
		"command":{"op":"release"}}
	probe.accept=false
	world._apply(1,release)
	assert(world.pcb_holders.has("fixture|board/joy:"),"Rejected release incorrectly erased the live control lease")
	probe.accept=true
	world._apply(1,release)
	assert(world.pcb_holders.is_empty(),"Successful joystick release did not free the lease")
	before=probe.calls.size()
	world._apply(2,move)
	assert(probe.calls.size()==before+1,"Another player must regain input access after release")
	world.placed["fixture"].pcb_inputs.append({"kind":"io_keypad","id":"board/keys"})
	before=probe.calls.size()
	world._apply(2,{"op":"pcb_input","key":"fixture","id":"board/keys","pressed":true,
		"command":{"op":"release"}})
	assert(probe.calls.size()==before,"Remote keypad-wide release could clear another player's held keys")
	world.placed["fixture"].pcb_inputs.append({"kind":"xpt2046","id":"board/touch"})
	before=probe.calls.size()
	world._apply(1,{"op":"pcb_input","key":"fixture","id":"board/touch","pressed":true,
		"command":{"op":"touch","x":0.2,"y":0.4,"pressed":false}})
	assert(probe.calls.size()==before and not world.pcb_holders.has("fixture|board/touch:"),
		"A contradictory released touch must not lock another player out")
	world._apply(1,{"op":"pcb_input","key":"fixture","id":"board/touch","pressed":true,
		"command":{"op":"touch","x":0.2,"y":0.4,"pressed":true}})
	assert(world.pcb_holders.has("fixture|board/touch:"))
	before=probe.calls.size()
	world._apply(2,{"op":"pcb_input","key":"fixture","id":"board/touch","pressed":true,
		"command":{"op":"release"}})
	assert(probe.calls.size()==before,"Another player released an active touchscreen contact")
	world._apply(1,{"op":"pcb_input","key":"fixture","id":"board/touch","pressed":false,
		"command":{"op":"release"}})
	assert(not world.pcb_holders.has("fixture|board/touch:"))
	game.free()
	print("PCB_INPUT_LEASE_PASS")

func _check_disconnect_releases() -> void:
	# When a peer disconnects and a Both-mode PCB drive is already off,
	# effective motion stays false. Other clients must still see the released
	# physical switch (and the host must drop its stale input lease).
	var game:=MockGame.new()
	root.add_child(game)
	game.add_child(game.player)
	var world:=World.new()
	game.add_child(world)
	world.game=game
	world.set_process(false)
	world.set_physics_process(false)
	world.placed["fixture"]={
		"owner":1,
		"controls":{"A":"hold","B":"toggle"},
		"state":{"A":true,"B":false},
		"holder":{"A":2,"B":0},
		"expiry":{"A":Time.get_ticks_msec()+10000,"B":0},
		"effective":{"A":false,"B":false},
		"drive":{"A":"both","B":"manual"},
		"pcb_voltage":{"A":0.0,"B":0.0}
	}
	game.session.roster.erase(2)
	world._roster_changed()
	assert(not world.placed["fixture"].state.A
		and world.placed["fixture"].holder.A==0
		and world.placed["fixture"].expiry.A==0,
		"Disconnect must release a held invention control and its lease")
	assert(world.pending_motion.has("fixture"),
		"Disconnect must replicate button release even when effective drive was already inactive")
	game.free()
	print("INVENTION_DISCONNECT_CONTROL_PASS")

func _check_world_clock() -> void:
	var world:=World.new()
	var game:=MockGame.new()
	get_root().add_child(game)
	game.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.game=game
	world.placed["test"]={
		# Clock tests call the full live-world physics loop. A placed invention
		# must have the same structural fields as one fabricated by the host,
		# even when this fixture intentionally has no moving parts.
		"parts":[],"position":Vector3.ZERO,"yaw":0.0,"angle":0.0,
		"hinge_angles":{},
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
	# A decorative/unmapped PCB cannot open the live controls of the one
	# separately mapped PCB that drives the invention.
	var mixed: Dictionary={
		"name":"Mapped and unmapped PCBs", "position":Vector3(0,2,0),
		"parts":[
			{"type":"pcb","x":0,"y":0,"z":0,
				"pin_map":{"power":0,"ground":1,"A":2,"B":-1}},
			{"type":"pcb","x":1,"y":0,"z":0}
		],
		"drive":{"A":"pcb","B":"manual"},
		"controls":{"A":"hold","B":"toggle"},
		"features":{"battery":false}
	}
	var mixed_view:=world._create_view("mixed_pcb",mixed)
	var inspect_targets:=mixed_view.find_children("*","StaticBody3D",true,false).filter(
		func(node):return node.get_meta("role","")=="invention_pcb")
	assert(inspect_targets.size()==1,
		"Unmapped PCB must not open a different mounted PCB's live circuit controls")
	mixed_view.queue_free()
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
