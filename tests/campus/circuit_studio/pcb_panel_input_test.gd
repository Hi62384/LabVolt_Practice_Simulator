extends SceneTree
## Exercises the mounted-PCB controls through their real Window signals, and
## verifies the host-side joystick lease releases to neutral on expiry.
const PCBPanel=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_panel.gd")
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")

class FakeWorld extends Node:
	var placed: Dictionary={}
	var requests: Array=[]
	func request_pcb_input(invention_key: String,device_id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> void:
		requests.append({"key":invention_key,"id":device_id,"pressed":pressed,"reverse":reverse,"command":command.duplicate(true)})

class FakeGame extends Node:
	var invention_world: Node
	var front: Dictionary={"in_game":false}
	func release_mouse() -> void:pass
	func capture() -> void:pass

class CapturingRuntime extends RefCounted:
	var commands: Array=[]
	func input(device_id: String,pressed: bool,reverse: bool,command: Dictionary) -> bool:
		commands.append({"id":device_id,"pressed":pressed,"command":command.duplicate(true)})
		return true

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var game:=FakeGame.new()
	var world:=FakeWorld.new()
	world.placed={"fixture":{
		"pcb_inputs":[
			{"kind":"xpt2046","id":"board/touch","name":"Touch panel"},
			{"kind":"io_slider","id":"board/slider","name":"Analog slider"},
			{"kind":"io_joystick","id":"board/joy","name":"Joystick"}],
		"pcb_error":"","pcb_voltage":{"A":0.0,"B":0.0}}}
	game.invention_world=world
	root.add_child(game)
	game.add_child(world)
	var panel:=PCBPanel.new()
	root.add_child(panel)
	panel.open_board(game,"fixture")
	await process_frame

	var sliders: Array=panel.find_children("*","HSlider",true,false)
	assert(sliders.size()==5,"Touch X/Y, analog slider and joystick X/Y must be present")
	var touch_buttons: Array=panel.find_children("*","Button",true,false).filter(func(button):return button.text=="Touch on/off")
	assert(touch_buttons.size()==1 and touch_buttons[0].toggle_mode,"Touch control must latch so its sliders remain usable")
	var touch: Button=touch_buttons[0]
	var touch_x: HSlider=sliders[0]
	var touch_y: HSlider=sliders[1]
	var analog: HSlider=sliders[2]
	var joy_x: HSlider=sliders[3]
	var joy_y: HSlider=sliders[4]
	var start_events: int=world.requests.size()
	touch_x.value=.75
	assert(world.requests.size()==start_events,"Moving an unpressed touch point must not generate a touch event")
	touch.button_pressed=true
	assert(panel.held.has("board/touch:") and world.requests.back().command.get("op")=="touch"
		and world.requests.back().pressed,"Toggling Touch on must begin a held contact")
	touch_y.value=.2
	assert(absf(float(world.requests.back().command.get("y",0))-.2)<.01 and world.requests.back().command.pressed,
		"Moving a touch coordinate must send live pressed coordinates")
	var before_renew: int=world.requests.size()
	panel._process(.26)
	assert(world.requests.size()==before_renew+1
		and absf(float(world.requests.back().command.get("x",0))-.75)<.01
		and absf(float(world.requests.back().command.get("y",0))-.2)<.01,
		"Lease renewal must retain the most recent touchscreen position")
	touch.button_pressed=false
	assert(panel.held.is_empty() and not world.requests.back().pressed
		and world.requests.back().command.get("op")=="release",
		"Toggling Touch off must release the host touch lease")
	analog.value=.35
	assert(world.requests.back().command.get("op")=="move"
		and absf(float(world.requests.back().command.get("x",0))-.35)<.01,
		"Analog slider movements must update the circuit without requiring drag-end")
	var press_buttons: Array=panel.find_children("*","Button",true,false).filter(func(button):return button.text=="Press")
	assert(press_buttons.size()==1,"Joystick press control must be present")
	press_buttons[0].button_down.emit()
	assert(panel.held.has("board/joy:") and world.requests.back().command.get("op")=="press")
	joy_x.value=.9
	joy_y.value=.1
	assert(world.requests.back().command.get("op")=="move"
		and absf(float(world.requests.back().command.get("y",0))-.1)<.01,
		"Joystick must report live changes while pressed")
	press_buttons[0].button_up.emit()
	assert(not panel.held.has("board/joy:") and not world.requests.back().pressed
		and world.requests.back().command.get("op")=="release",
		"Releasing joystick must request its return to center")
	assert(is_equal_approx(joy_x.value,.5) and is_equal_approx(joy_y.value,.5),
		"Joystick UI must re-center after release")

	var invention:=World.new()
	var runtime:=CapturingRuntime.new()
	invention.simulators["fixture"]={"runtime":runtime}
	invention.pcb_holders["fixture|board/joy:"]={"peer":1,"key":"fixture","id":"board/joy","expiry":1,
		"command":{"op":"press","pressed":true}}
	invention._release_pcb("fixture|board/joy:")
	assert(runtime.commands.size()==1 and not runtime.commands[0].pressed
		and runtime.commands[0].command.get("op")=="release"
		and invention.pcb_holders.is_empty(),
		"Expired host joystick leases must release and center rather than stick at their last coordinates")
	invention.free()
	panel._close()
	game.queue_free()
	await process_frame
	print("PCB_PANEL_INPUT PASS")
	quit()
