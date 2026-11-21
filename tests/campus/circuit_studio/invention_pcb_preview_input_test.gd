extends SceneTree
## The invention test preview must expose the same live PCB input semantics as
## the fabricated world's mounted PCB panel.
const Studio=preload("res://scripts/campus/facilities/circuit_studio/assembly_window.gd")

class FakePCB extends RefCounted:
	var inputs: Array=[
		{"kind":"xpt2046","id":"board/touch","name":"Touch panel"},
		{"kind":"io_slider","id":"board/slider","name":"Analog slider"},
		{"kind":"io_joystick","id":"board/joy","name":"Joystick"}]
	var requests: Array=[]
	func input(id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> bool:
		requests.append({"id":id,"pressed":pressed,"reverse":reverse,"command":command.duplicate(true)})
		return true

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var window:=Studio.new()
	root.add_child(window)
	var controls:=VBoxContainer.new()
	window.add_child(controls)
	var runtime:=FakePCB.new()
	window.test_pcb=runtime
	window._test_pcb_controls(controls)
	var sliders: Array=window.find_children("*","HSlider",true,false)
	assert(sliders.size()==5,"Preview must have touch X/Y, slider and joystick X/Y")
	var touch_x: HSlider=sliders[0]
	var touch_y: HSlider=sliders[1]
	var analog: HSlider=sliders[2]
	var joy_x: HSlider=sliders[3]
	var joy_y: HSlider=sliders[4]
	var buttons: Array=window.find_children("*","Button",true,false)
	var touch_buttons: Array=buttons.filter(func(button):return button.text=="Touch on/off")
	var joystick_buttons: Array=buttons.filter(func(button):return button.text=="Press")
	assert(touch_buttons.size()==1 and touch_buttons[0].toggle_mode,
		"Preview touch must toggle so the pointer sliders can move while pressed")
	assert(joystick_buttons.size()==1,"Preview must show a joystick Press input")
	var touch: Button=touch_buttons[0]
	touch_x.value=.75
	assert(runtime.requests.is_empty(),"Unpressed touch movement must be inert")
	touch.button_pressed=true
	assert(runtime.requests.size()==1 and runtime.requests.back().command.get("op")=="touch"
		and runtime.requests.back().pressed,"Touch-on must start a real PCB touch command")
	touch_y.value=.2
	assert(runtime.requests.size()==2 and runtime.requests.back().command.get("op")=="touch"
		and runtime.requests.back().command.pressed
		and absf(float(runtime.requests.back().command.get("y",0))-.2)<.01,
		"Touch movement must update live PCB input while pressed")
	touch.button_pressed=false
	assert(not runtime.requests.back().pressed and runtime.requests.back().command.get("op")=="release",
		"Touch-off must release the preview PCB contact")
	analog.value=.35
	assert(runtime.requests.back().command.get("op")=="move"
		and absf(float(runtime.requests.back().command.get("x",0))-.35)<.01,
		"Analog preview slider must update circuit on value change")
	joystick_buttons[0].button_down.emit()
	assert(runtime.requests.back().command.get("op")=="press" and runtime.requests.back().command.pressed)
	joy_x.value=.9
	joy_y.value=.1
	assert(runtime.requests.back().command.get("op")=="move"
		and absf(float(runtime.requests.back().command.get("y",0))-.1)<.01,
		"Joystick must send live X/Y changes before dragging ends")
	joystick_buttons[0].button_up.emit()
	assert(runtime.requests.back().command.get("op")=="release" and not runtime.requests.back().pressed,
		"Preview joystick release must trigger hardware neutral")
	assert(is_equal_approx(joy_x.value,.5) and is_equal_approx(joy_y.value,.5),
		"Preview joystick sliders must visibly recenter")
	window.queue_free()
	await process_frame
	print("INVENTION_PCB_PREVIEW_INPUT PASS")
	quit()
