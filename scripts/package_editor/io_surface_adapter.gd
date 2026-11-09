extends RefCounted
## Optional view-only bridge to the separately owned I/O package.
signal command_requested(id: String,command: Dictionary)
var owner_canvas: Control
var views := {}
var local_holds := {}
var surface_script: Script
var controls_script: Script
var catalog_script: Script
func setup(canvas: Control) -> void:
	owner_canvas=canvas
	if ResourceLoader.exists("res://scripts/io_devices/surface.gd") and ResourceLoader.exists("res://scripts/io_devices/catalog.gd") and ResourceLoader.exists("res://scripts/io_devices/controls.gd"):
		surface_script=load("res://scripts/io_devices/surface.gd");controls_script=load("res://scripts/io_devices/controls.gd");catalog_script=load("res://scripts/io_devices/catalog.gd")
func supported(kind: String) -> bool:
	return catalog_script!=null and catalog_script.surfaces().has(kind)
func sync(entries: Array,states: Dictionary,inputs: Dictionary,interacting: bool,zoom: float) -> void:
	if surface_script==null:return
	var found := {}
	for entry in entries:
		var kind := str(entry.type);var id := str(entry.id)
		if not supported(kind):continue
		found[id]=true
		if not views.has(id):
			var view: Control=surface_script.new();owner_canvas.add_child(view);views[id]=view
			view.command_requested.connect(func(command):
				if command.get("op","") in ["key","press","touch"]:local_holds[id]=bool(command.get("pressed",false))
				elif command.get("op","")=="move" and kind=="io_joystick":local_holds[id]=true
				elif command.get("op","")=="release":local_holds[id]=false
				command_requested.emit(id,command)
			)
		var view: Control=views[id]
		var extent := Vector2(40,40)*zoom
		if kind in ["hd44780","hd44780_20x4"]:extent=Vector2(256,128)*zoom
		elif kind=="ssd1306":extent=Vector2(256,128)*zoom
		elif kind=="ili9341":extent=Vector2(192,256)*zoom
		elif kind=="io_keypad":extent=Vector2(60,80)*zoom
		elif kind=="io_graphic" or kind=="io_matrix":extent=Vector2(64,64)*zoom
		elif kind in ["io_bar","io_pixels","io_slider","io_selector"]:extent=Vector2(72,40)*zoom
		if entry.has("surface_size"):
			extent = entry.surface_size*.90
			if posmod(roundi(float(entry.rotation)/(PI/2)),2) == 1: extent = Vector2(extent.y,extent.x)
		view.size=extent;view.position=Vector2(entry.center)-extent*.5;view.pivot_offset=extent*.5
		view.rotation=float(entry.get("rotation",0.0))
		view.z_index=3
		if view.interact and not interacting:release(id)
		view.interact=interacting and not controls_script.defaults(kind).is_empty()
		view.mouse_filter=Control.MOUSE_FILTER_PASS if view.interact else Control.MOUSE_FILTER_IGNORE
		view.present(kind,states.get(id,{}),inputs.get(id,{}))
	for id in views.keys():
		if found.has(id):continue
		release(id);views[id].queue_free();views.erase(id);local_holds.erase(id)
func release(id: String) -> void:
	if not views.has(id):return
	var view: Control=views[id]
	if view.held_key>=0 or view.dragging or local_holds.get(id,false):view.release_capture()
	local_holds[id]=false
func release_all() -> void:
	for id in views:release(id);views[id].interact=false;views[id].mouse_filter=Control.MOUSE_FILTER_IGNORE
func pending() -> bool:
	for view in views.values():
		if view.awaiting_revision>=0 or not view.pending.is_empty():return true
	return false
func acknowledge(id: String,input: Dictionary) -> void:
	if views.has(id):views[id].acknowledge(input)
