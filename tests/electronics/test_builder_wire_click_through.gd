extends SceneTree
## Real GUI input events on the Circuit Maker canvas. Occupied holes must not
## silently lift components/jumpers when Wire or Place is selected.
const Board=preload("res://scripts/breadboard_model.gd")
const Maker=preload("res://scripts/electronics/circuit_workspace/maker_canvas.gd")

func _click(point: Vector2, alternate := false) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.position=point
	event.pressed=true
	event.alt_pressed=alternate
	return event

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var design: Dictionary=Board.empty()
	design.parts=[{"id":"resistor","type":"r1000","a":"A1","b":"F1"}]
	design.wires=[["F1","F2"]]
	assert(Board.validate(design,{},true)=="")
	var canvas:=Maker.new()
	canvas.board=design.duplicate(true)
	canvas.inventory_catalog=Board.catalog(design)
	canvas.stock_limits={}
	canvas.unlimited=true
	canvas.custom_minimum_size=Vector2(1000,690)
	root.add_child(canvas)
	await process_frame
	canvas.zoom=1.0
	canvas.pan=Vector2.ZERO
	assert(canvas.hole_at(canvas.at("A1"))=="A1","Could not hit component lead hole")
	assert(canvas.hole_at(canvas.at("F2"))=="F2","Could not hit existing wire endpoint")

	canvas.selected_type="wire"
	canvas._gui_input(_click(canvas.at("A1")))
	assert(canvas.first=="A1" and canvas.grabbed_hole.is_empty() and canvas.hidden_wire_index<0,
		"Wire click at a component pin mistakenly picked up the component")
	canvas._gui_input(_click(canvas.at("A2")))
	assert(design.wires.size()+1==canvas.board.wires.size()
		and canvas.board.wires.has(["A1","A2"]),
		"Two clicks across a component lead must make one straight jumper")
	canvas.first=""
	canvas._gui_input(_click(canvas.at("F2")))
	assert(canvas.first=="F2" and canvas.hidden_wire_index<0 and canvas.grabbed_hole.is_empty(),
		"Wire click at an existing jumper endpoint mistakenly began moving it")
	canvas.first=""
	canvas._gui_input(_click(canvas.at("F2"),true))
	assert(canvas.hidden_wire_index>=0 and canvas.grabbed_hole=="F2",
		"Explicit Alt-click should still permit moving an existing jumper endpoint")
	canvas.cancel_grab()

	canvas.selected_type="select"
	canvas._gui_input(_click(canvas.at("A1")))
	assert(canvas.grabbed_hole.is_empty(),
		"Select must use component bodies, not unexpectedly grab a pin")
	canvas.selected_type="r1000"
	canvas._gui_input(_click(canvas.at("A1")))
	assert(canvas.grabbed_hole.is_empty(),
		"Place mode must not steal an existing component through its pin")
	canvas.queue_free()
	await process_frame
	print("BUILDER_WIRE_CLICK_THROUGH PASS")
	quit()
