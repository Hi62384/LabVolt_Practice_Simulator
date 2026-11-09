extends RefCounted

const Board = preload("res://scripts/breadboard_model.gd")
const Custom = preload("res://scripts/custom_circuit.gd")
const Geometry = preload("res://scripts/package_editor/package_geometry.gd")
const Surface = preload("res://scripts/pcb_design/surface_layout.gd")
const PCBDesign = preload("res://scripts/pcb_design/design.gd")
const Shape = preload("res://scripts/inventory_authority/validation.gd")

var source_id := ""
var source_revision := ""
var parent_revision := ""
var board := {}
var connections: Array[Dictionary] = []
var mapping: Array[String] = []
var positions: Array[Vector2i] = []
var width := 1
var length := 1
var turns := 0
var draft := {"package": "IC", "name": "", "description": "", "marking": "", "orientation_marker": "dot",
	"footprint": {"width": 2, "height": 1, "body_height_mm": 3.0, "color": "303844"}}
var pins: Array[Dictionary] = []
var exposed: Array = []
var surface := {}
var package_kind := "IC"

func set_kind(kind: String) -> void:
	package_kind = kind
	draft.package = kind
	if kind == "PCB":
		draft.footprint.color = "216449"
		draft.footprint.thickness_mm = 1.6

static func source_error(source: Variant, definitions: Dictionary) -> String:
	if not source is Dictionary or not source.get("parts") is Array or not source.get("wires") is Array:
		return "This saved circuit cannot be read."
	if source.get("standalone", false):
		return "Choose a breadboard circuit. A standalone PCB cannot be converted here."
	if source.parts.is_empty():
		return "Add at least one component to the circuit before packaging it."
	var catalog := Board.catalog({"definitions": definitions, "parts": source.parts.filter(func(part):return part is Dictionary)})
	for part in source.parts:
		if not part is Dictionary: return "This saved circuit contains an invalid component record."
		var type := str(part.get("type", ""))
		if not catalog.has(type): return "Missing or unsupported component: " + type
		if str(definitions.get(type, {}).get("package", "")) == "PCB":
			return "Remove %s before packaging. A physical PCB cannot be used inside another package." % catalog[type].name
	var copy: Dictionary = source.duplicate()
	copy.definitions = definitions
	if not Shape.board(copy): return "This circuit has malformed wiring or component data."
	return Board.validate(copy, {}, true)

func select_source(id: String, entry: Dictionary, definitions: Dictionary) -> String:
	var source: Variant = entry.get("board")
	var error := source_error(source, definitions)
	if not error.is_empty(): return error
	if id == source_id and source_revision == JSON.stringify(source,"",true,true).sha256_text(): return ""
	source_id = id
	source_revision = JSON.stringify(source,"",true,true).sha256_text()
	parent_revision = ""
	board = source.duplicate(true)
	board.definitions = definitions.duplicate(true)
	connections.clear()
	mapping.clear()
	positions.clear()
	exposed.clear()
	surface.clear()
	draft.name = str(entry.get("name", "Custom IC")).left(40)
	turns = 0
	width = 2 if package_kind == "IC" else 1
	length = 1
	return ""

static func embedded_source(blueprint: Dictionary, definitions: Dictionary) -> Dictionary:
	if not blueprint.has("layout"): return {}
	var source := Board.empty()
	source.merge(blueprint.layout.duplicate(true), true)
	source.definitions = definitions.duplicate(true)
	source.programs = {}
	source.io_controls = {}
	for key in blueprint.get("programs", {}): source.programs["board/"+str(key)] = blueprint.programs[key].duplicate(true)
	for key in blueprint.get("io_controls", {}): source.io_controls["board/"+str(key)] = blueprint.io_controls[key].duplicate(true)
	return source

func restore(id: String, blueprint: Dictionary, definitions: Dictionary) -> String:
	var source := embedded_source(blueprint,definitions)
	if source.is_empty(): return "This legacy package does not include its original breadboard."
	set_kind(str(blueprint.get("package","IC")))
	var error := select_source(str(blueprint.get("source_circuit_id", id)), {"board":source,"name":blueprint.name}, definitions)
	if not error.is_empty(): return error
	parent_revision = id
	source_revision = str(blueprint.get("source_revision", source_revision))
	for key in ["name", "description", "marking", "orientation_marker"]:
		if blueprint.has(key): draft[key] = blueprint[key]
	exposed = blueprint.get("exposed", []).duplicate()
	for pin in blueprint.pins:
		var hole := str(pin.get("source_hole", ""))
		if hole.is_empty(): hole = _legacy_hole(str(pin.node))
		if hole.is_empty(): return "A legacy pin could not be mapped to a distinct source hole."
		connections.append({"hole":hole,"name":str(pin.name)})
	if blueprint.get("pin_grid", "") != "terminal_pitch": width = 1
	prepare_package()
	if blueprint.get("pin_grid", "") == "terminal_pitch":
		width = int(blueprint.get("width_intervals", width))
		length = int(blueprint.get("length_positions", length))
		turns = int(blueprint.get("orientation_turns", 0))
		for index in blueprint.pins.size(): positions[index] = _to_canonical(Geometry.position(blueprint.pins[index]))
	var footprint: Dictionary = blueprint.get("footprint", {})
	draft.footprint.body_height_mm = float(footprint.get("body_height_mm", 3.0))
	draft.footprint.color = str(footprint.get("color", "303844"))
	if package_kind == "PCB":
		draft.footprint.thickness_mm = float(footprint.get("thickness_mm",1.6))
		surface = blueprint.get("surface_layout",{}).duplicate(true)
	sync()
	return ""

func _legacy_hole(node: String) -> String:
	for column in Board.hole_letters(board):
		for row in range(1, int(board.rows)+1):
			var hole := column+str(row)
			if Board.node(hole, int(board.rows)) == node and connection_index(hole) == -1: return hole
	return ""

func connection_index(hole: String) -> int:
	for index in connections.size():
		if connections[index].hole == hole: return index
	return -1

func choose_hole(hole: String, replace := -1) -> String:
	if not Board.valid_hole(board,hole): return "Choose a breadboard hole."
	if connection_index(hole) != -1: return "That hole already has an external pin."
	if replace >= 0 and replace < connections.size():
		var previous: String = connections[replace].hole
		connections[replace].hole = hole
		var index := mapping.find(previous)
		if index >= 0: mapping[index] = hole
		return ""
	if connections.size() >= Geometry.MAX_PINS: return "Packages support up to 64 external pins."
	var number := connections.size()+1
	while connections.any(func(pin):return pin.name == "Pin %d" % number): number += 1
	connections.append({"hole":hole,"name":"Pin %d" % number})
	return ""

func prepare_package() -> void:
	if mapping.size() != connections.size() or mapping.any(func(hole):return connection_index(hole) < 0):
		mapping.clear()
		for connection in connections: mapping.append(connection.hole)
		length = maxi(length, left_count())
		if package_kind == "PCB": length = maxi(length,2)
		_reset_positions()
	sync()

func left_count() -> int:
	return ceili(connections.size() * .5)

func chip_body_inset() -> Vector2:
	# Older one-interval chips retain their original pin spacing.
	var inset := 1.0 if width >= 2 else .75
	return Vector2(inset, 0) if turns % 2 == 0 else Vector2(0, inset)

func resize_package(new_width: int, new_length: int) -> void:
	if package_kind == "PCB":
		var minimum := surface_minimum()
		new_width = maxi(new_width,minimum.x)
		new_length = maxi(new_length,minimum.y)
	var old_width := width
	width = new_width
	length = new_length
	for index in positions.size():
		if positions[index].x == old_width: positions[index].x = width
	if positions.any(func(point):return point.x > width or point.y >= length):
		_reset_positions()
	if _positions_overlap(): _reset_positions()
	sync()

func _positions_overlap() -> bool:
	var seen := {}
	for point in positions:
		if seen.has(point): return true
		seen[point] = true
	return false

func _reset_positions() -> void:
	positions.clear()
	var left := left_count()
	for index in mapping.size():
		positions.append(Vector2i(0,index) if index < left else Vector2i(width,mapping.size()-1-index))

func _offset() -> Vector2i:
	match turns:
		1: return Vector2i(length-1,0)
		2: return Vector2i(width,length-1)
		3: return Vector2i(0,width)
	return Vector2i.ZERO

func _to_canonical(point: Vector2i) -> Vector2i:
	return Geometry.rotate(point-_offset(), -turns)

func move_pin(index: int, grid_point: Vector2i) -> bool:
	var point := _to_canonical(grid_point)
	if not Rect2i(0,0,width+1,length).has_point(point): return false
	if package_kind == "IC" and point.x != 0 and point.x != width: return false
	var occupant := positions.find(point)
	if occupant != -1 and occupant != index: return false
	for id in surface:
		if Surface.rect(surface[id],surface_type(id),board.definitions).has_point(point): return false
	positions[index] = point
	sync()
	return true

func remap(pin_index: int, hole: String) -> void:
	var other := mapping.find(hole)
	if other < 0 or pin_index == other: return
	mapping[other] = mapping[pin_index]
	mapping[pin_index] = hole
	sync()

func sync() -> void:
	draft.footprint.width = width+1 if turns % 2 == 0 else length
	draft.footprint.height = length if turns % 2 == 0 else width+1
	pins.clear()
	for index in mapping.size():
		var connection := connections[connection_index(mapping[index])]
		var point := Geometry.rotate(positions[index], turns)+_offset()
		pins.append({"id":"pin_%d" % (index+1),"number":index+1,"name":str(connection.name).strip_edges(),
			"node":Board.node(connection.hole,int(board.rows)),"source_hole":connection.hole,
			"position":{"x":point.x,"y":point.y},"connector":"through_hole","role":"unspecified"})

func surface_type(id: String) -> String:
	for part in board.parts:
		if part.id == id: return str(part.type)
	return ""

func surface_minimum() -> Vector2i:
	var minimum := Vector2i(1,maxi(2,left_count()))
	for id in surface:
		var box := Surface.rect(surface[id],surface_type(id),board.definitions)
		minimum = minimum.max(box.end+Vector2i(0,1))
	for point in positions:
		if point.x != width: minimum.x = maxi(minimum.x,point.x+1)
		minimum.y = maxi(minimum.y,point.y+1)
	return minimum

func surface_transform(id: String, point: Vector2i, rotation: int, grow: bool) -> bool:
	if not can_place_surface(id,point,rotation,grow): return false
	surface[id] = {"x":point.x,"y":point.y,"turns":rotation}
	if grow:
		var minimum := surface_minimum()
		resize_package(maxi(width,minimum.x),maxi(length,minimum.y))
	return true

func can_place_surface(id: String, point: Vector2i, rotation: int, grow: bool) -> bool:
	var item := {"x":point.x,"y":point.y,"turns":rotation}
	var shape := Surface.rect(item,surface_type(id),board.definitions)
	if shape.position.x < 1 or shape.position.y < 1 or shape.end.x > 39 or shape.end.y > 39: return false
	if not grow and (shape.end.x > width or shape.end.y >= length): return false
	for other in surface:
		if other != id and shape.intersects(Surface.rect(surface[other],surface_type(other),board.definitions)): return false
	for pin in positions:
		if grow and pin.x == width and shape.end.x > width: continue
		if shape.has_point(pin): return false
	return true

func toggle_surface(id: String, grow: bool) -> bool:
	if surface.has(id):
		surface.erase(id)
		return true
	var type := surface_type(id)
	if type.is_empty() or surface.size() >= 48: return false
	var dimensions := Surface.extent(type,board.definitions,0)
	var limits := Vector2i(maxi(width,dimensions.x+1),maxi(length,dimensions.y+2))
	if grow: limits = Vector2i(39,39)
	for y in range(1,length):
		for x in range(1,width):
			if surface_transform(id,Vector2i(x,y),0,false): return true
	if grow:
		var placement := Vector2i.ZERO
		var best_area := 1601
		for y in range(1,limits.y):
			for x in range(1,limits.x):
				var cost := maxi(width,x+dimensions.x)*maxi(length,y+dimensions.y+1)
				if cost < best_area and can_place_surface(id,Vector2i(x,y),0,true):
					best_area = cost
					placement = Vector2i(x,y)
		if placement != Vector2i.ZERO: return surface_transform(id,placement,0,true)
	return false

func pin_error() -> String:
	if connections.size() < 2: return "Choose at least two external holes."
	var names := {}
	for connection in connections:
		var name := str(connection.name).strip_edges()
		if name.is_empty(): return "Enter a name for every external hole."
		if names.has(name.to_lower()): return "Use a different name for each external pin."
		names[name.to_lower()] = true
	return ""

func prepare_blueprint(profile: RefCounted) -> Dictionary:
	var error := pin_error()
	if not error.is_empty(): return {"error":error}
	if str(draft.name).strip_edges().is_empty(): return {"error":"Enter a %s name." % package_kind}
	if not profile.data.get("pending_trade", {}).is_empty(): return {"error":"Finish the pending trade first."}
	sync()
	if Board.Debug.contains(board):return {"error":"Remove simulation instruments before building an IC or PCB."}
	var bp := Board.blueprint(board, str(draft.name).strip_edges())
	bp.merge(draft.duplicate(true),true)
	bp.name = str(bp.name).strip_edges()
	bp.layout = {"rows":board.rows,"parts":board.parts.duplicate(true),"wires":board.wires.duplicate(true),"ports":board.ports.duplicate()}
	if board.get("expanded",false):bp.layout.expanded=true
	for part in bp.parts:
		var control: Dictionary = board.get("controls", {}).get("board/"+str(part.id), {})
		part.merge(control,true)
	bp.pins = pins.duplicate(true)
	bp.exposed = exposed.duplicate()
	if package_kind == "PCB": bp.surface_layout = surface.duplicate(true)
	bp.pin_grid = "terminal_pitch"
	bp.width_intervals = width
	bp.length_positions = length
	bp.orientation_turns = turns
	bp.source_circuit_id = source_id
	bp.source_revision = source_revision
	bp.parent_revision = parent_revision
	var definitions: Dictionary = profile.data.get("blueprints", {}).duplicate(true)
	var previous: Dictionary = definitions.get(parent_revision,{})
	bp.revision = int(previous.get("revision", 0))+1
	if previous.has("pcb_design"):
		bp.pcb_design = previous.pcb_design.duplicate(true)
		if not PCBDesign.validate(bp).is_empty():
			return {"error":"The revised circuit changes the routed PCB layout. Create a new PCB blueprint to route this circuit."}
	var id := "ic:"+JSON.stringify(bp,"",true,true).sha256_text().left(24)
	definitions[id] = bp
	error = Custom.validate(id, definitions)
	if not error.is_empty(): return {"error":error}
	if not Shape.definitions(definitions): return {"error":"The package contains unsupported saved data."}
	return {"id":id,"definitions":definitions}

