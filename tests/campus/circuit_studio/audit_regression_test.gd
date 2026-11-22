extends SceneTree
## Read-only regression probes for physical assemblies and board-editor edge cases.
const Model = preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const World = preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Canvas = preload("res://scripts/breadboard_canvas.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Student = preload("res://scripts/campus/npcs/student_behavior.gd")

func _initialize() -> void:
	call_deferred("_run")

func _event(button: int, point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = point
	return event

func _run() -> void:
	var connected := Model.empty("Joined")
	connected.parts.append({"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""})
	var designs := {"inv:joined":connected}
	assert(Model.structure_error("inv:joined",designs,{}).is_empty(), "Adjacent parts must be constructible")
	var floating := connected.duplicate(true)
	floating.parts.append({"type":"wheel","x":6,"y":0,"z":0,"control":"","ref":""})
	designs["inv:floating"] = floating
	assert(Model.validate("inv:floating",designs,{}).is_empty(), "Legacy disconnected profiles must remain readable")
	assert(not Model.structure_error("inv:floating",designs,{}).is_empty(), "New floating inventions must not be fabricated")

	var profile := Profile.new()
	profile.open("audit_inventory_" + Crypto.new().generate_random_bytes(6).hex_encode())
	profile.authority_submit = func(_op,_args): return ""
	assert(profile.save() == ERR_BUSY, "A rejected inventory queue was treated as a successful save")
	profile.authority_submit = func(_op,_args): return "queued"
	assert(profile.save() == OK, "An accepted inventory queue must remain backward-compatible")
	profile.authority_submit = Callable()

	var box := Vector3(.28,.2,.28)
	var origin := Transform3D.IDENTITY
	assert(World._box_overlap(origin,box,Transform3D(Basis.IDENTITY,Vector3(.1,0,0)),box), "Intersecting chassis boxes missed")
	assert(not World._box_overlap(origin,box,Transform3D(Basis.IDENTITY,Vector3(.5,0,0)),box), "Separate chassis boxes falsely overlap")
	var world := World.new()
	root.add_child(world)
	var solid := StaticBody3D.new()
	world.add_child(solid)
	for x in [0.0,.75]:
		var shape := CollisionShape3D.new()
		var body := BoxShape3D.new()
		body.size=box
		shape.shape=body
		shape.position=Vector3(x,0,0)
		solid.add_child(shape)
	var bounds: Dictionary=world._live_bounds(solid)
	assert(float(bounds.size.x)>.9 and float(bounds.size.x)<1.1,"Dynamic collision bounds failed to include multiple components")

	var behavior := Student.new()
	var classroom := {"kind":"lecture","center":[0,5,50],"floor":1}
	var seat: Vector3=behavior._work_point(classroom,0,0)
	assert(is_equal_approx(seat.y,5.0) and seat.x in [-6.0,-2.0,2.0,6.0], "Ambient student must use an authored lecture seat")
	var npc := {"state":"to_room","room_kind":"lecture","id":0,"cycle":0,"moving":true}
	behavior._arrived(npc)
	assert(npc.seated and npc.state=="working","Student must transition to seated lecture work")

	var canvas := Canvas.new()
	root.add_child(canvas)
	await process_frame
	canvas.board=Board.empty()
	canvas.board.wires=[["A1","A2"],["A1","A3"]]
	canvas.selected_type="wire"
	canvas._gui_input(_event(MOUSE_BUTTON_RIGHT,canvas.at("A2")))
	assert(canvas.board.wires.size()==1,"Right-click should remove only the selected jumper")
	canvas.first="A5"
	canvas._gui_input(_event(MOUSE_BUTTON_RIGHT,canvas.at("A2")))
	assert(canvas.first.is_empty() and canvas.board.wires.size()==1,"Right-click with a pending wire must cancel only")
	canvas.board.wires=[["A1","A2"],["A1","A3"]]
	canvas.selected_type="remove"
	canvas._gui_input(_event(MOUSE_BUTTON_LEFT,canvas.at("A1")))
	assert(canvas.board.wires.size()==1,"Removing a shared junction must preserve other wires")
	canvas.board=Board.empty()
	canvas.history.clear()
	canvas.future.clear()
	canvas.selected_type="hc08"
	canvas.first="A29"
	canvas._gui_input(_event(MOUSE_BUTTON_LEFT,canvas.at("F29")))
	assert(canvas.board.parts.is_empty() and canvas.history.is_empty(),"Invalid multi-pin placement must not modify board or Undo")
	canvas.selected_type="wire"
	canvas.first="A1"
	canvas._gui_input(_event(MOUSE_BUTTON_LEFT,canvas.at("A2")))
	assert(canvas.board.wires.size()==1 and canvas.history.size()==1,"Valid jumper must remain undoable")
	print("AUDIT_CIRCUIT_REGRESSIONS PASS")
	quit()
