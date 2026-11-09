extends SubViewportContainer
const Surface = preload("res://scripts/pcb_design/surface_layout.gd")
const Board = preload("res://scripts/breadboard_model.gd")
## A local projection of the editable package model, with a world isolated from campus.
var model: RefCounted
var viewport: SubViewport
var geometry: Node3D
var camera: Camera3D
var signature := 0
var azimuth := .72
var elevation := .48
var zoom := 1.0
var package_span := 10.0
var focal_height := 0.0

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(320, 290)
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("172b3d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce7ff")
	environment.environment.ambient_light_energy = .62
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-54, -34, 0)
	light.light_energy = .95
	viewport.add_child(light)
	geometry = Node3D.new()
	viewport.add_child(geometry)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	viewport.add_child(camera)
	resized.connect(func():viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			signature = 0
			refresh())

func refresh() -> void:
	if model == null or not is_instance_valid(camera) or not is_visible_in_tree():return
	var next := hash([model.draft.package, model.draft.footprint, model.draft.get("marking"), model.draft.get("orientation_marker"), model.pins,model.get("surface")])
	if next == signature:return
	signature = next
	for child in geometry.get_children():
		geometry.remove_child(child)
		child.queue_free()
	var footprint: Dictionary = model.draft.footprint
	var columns := float(footprint.width)
	var rows := float(footprint.height)
	var is_pcb: bool = model.draft.package == "PCB"
	var body_height := float(footprint.get("thickness_mm", 1.6) if is_pcb else footprint.get("body_height_mm", 3.0))
	var inset := Vector2.ZERO
	if not is_pcb and model.has_method("chip_body_inset"):
		inset = model.chip_body_inset() * 2.54
	var body := Vector3(columns * 2.54 - 2 * inset.x, body_height, rows * 2.54 - 2 * inset.y)
	var color := Color.from_string(str(footprint.get("color", "24775b" if is_pcb else "353b44")), Color("353b44"))
	_box(body, Vector3(0, body.y * .5, 0), color)
	for pin in model.pins:
		var grid: Dictionary = pin.position
		var at := Vector3((float(grid.x) - (columns - 1) * .5) * 2.54, 0, (float(grid.y) - (rows - 1) * .5) * 2.54)
		var exposed: bool = is_pcb or pin.get("connector") == "test_pad"
		var pin_height := .24 if exposed else 3.3
		at.y = body.y + pin_height * .5 if exposed else -pin_height * .5
		_box(Vector3(.85, pin_height, .85), at, Color("d6be84") if exposed else Color("9eaab5"))
		var side := Vector2(at.x, at.z)
		var edge := side.clamp(-Vector2(body.x, body.z) * .5, Vector2(body.x, body.z) * .5)
		var lead := (side - edge).abs()
		if inset != Vector2.ZERO and lead != Vector2.ZERO:
			var midpoint := (side + edge) * .5
			_box(Vector3(.85, body.y * .5 + .35, .85), Vector3(at.x, body.y * .25, at.z), Color("9eaab5"))
			_box(Vector3(lead.x + .85, .35, lead.y + .85), Vector3(midpoint.x, body.y * .5, midpoint.y), Color("9eaab5"))
		if is_pcb:
			at.y = -1.65
			_box(Vector3(.65,3.3,.65),at,Color("b8b5a7"))
	if is_pcb and model.get("surface") is Dictionary: _mount_parts(body)
	var mark := str(model.draft.get("marking", ""))
	if not mark.is_empty():
		var ink := Label3D.new()
		ink.text = mark
		ink.font_size = 52
		ink.pixel_size = minf(body.x, body.z) * .003
		ink.rotation.x = -PI / 2
		ink.position.y = body.y + .07
		ink.modulate = Color("e2e7ec")
		geometry.add_child(ink)
	if model.draft.get("orientation_marker", "none") != "none":
		var marker := Vector3(-body.x * .40, body.y + .04, -body.z * .40)
		if not model.pins.is_empty():
			var first: Dictionary = model.pins[0].position
			marker.x = clampf((float(first.x)-(columns-1)*.5)*2.54, -body.x*.5, body.x*.5)*.72
			marker.z = clampf((float(first.y)-(rows-1)*.5)*2.54, -body.z*.5, body.z*.5)*.72
		_box(Vector3(.85,.08,.85),marker,Color("becad1"))
	package_span = maxf(columns * 2.54, maxf(body.y, rows * 2.54))
	focal_height = body.y * .35
	_update_camera()

func _mount_parts(board_size: Vector3) -> void:
	var bp := {"footprint":model.draft.footprint,"orientation_turns":model.turns,"width_intervals":model.width,"length_positions":model.length}
	var outline := Rect2(Vector2(-board_size.x,-board_size.z)*.5,Vector2(board_size.x,board_size.z))
	var catalog := Board.catalog(model.board)
	for id in model.surface:
		var type: String = model.surface_type(id)
		var record: Dictionary = model.surface[id]
		var bounds := Surface.view_rect(bp,record,type,model.board.definitions,outline)
		var center := bounds.get_center()
		var kind := str(catalog.get(type,{}).get("kind",""))
		var height := minf(3.8,minf(bounds.size.x,bounds.size.y)*.55)
		var host := Node3D.new()
		host.position = Vector3(center.x,board_size.y,center.y)
		var turns := int(record.turns)+int(model.turns)
		host.rotation.y = -turns*PI/2
		geometry.add_child(host)
		var dimensions := bounds.size*.78 if turns%2==0 else Vector2(bounds.size.y,bounds.size.x)*.78
		var tint := Surface.part_color(type)
		var top := Vector3(0,height*.5,0)
		match kind:
			"LED", "C", "pot", "buzzer", "speaker":
				_box(Vector3(dimensions.x,.35,dimensions.y),Vector3(0,.175,0),Color("363e45"),host)
				_cylinder(minf(dimensions.x,dimensions.y)*.38,height,top,tint,host)
			"R", "D":
				var axial := _cylinder(dimensions.y*.27,dimensions.x*.78,Vector3(0,dimensions.y*.27,0),tint,host)
				axial.rotation.z = PI/2
				if kind == "R":
					var spec: Dictionary = catalog[type]
					var bands := preload("res://scripts/electronics/component_shop_ui/resistor_bands.gd").bands(float(spec.value),float(spec.get("resistance_tolerance",.05)))
					for i in bands.size():
						var band := _cylinder(dimensions.y*.275,dimensions.x*.075,Vector3(dimensions.x*(-.26+i*.15),dimensions.y*.27,0),Color(bands[i].color),host)
						band.rotation.z = PI/2
			"button", "toggle":
				_box(Vector3(dimensions.x,height*.48,dimensions.y),top*.48,Color("333c43"),host)
				_cylinder(minf(dimensions.x,dimensions.y)*.25,height*.65,Vector3(0,height*.69,0),Color("c6594c"),host)
			_:
				_box(Vector3(dimensions.x,height,dimensions.y),top,tint,host)
				if kind.contains("display") or kind in ["hd44780","ssd1306","ili9341","seven_segment"]:
					_box(Vector3(dimensions.x*.82,.09,dimensions.y*.73),Vector3(0,height+.045,0),Color("688079"),host)
				else:
					for side in [-1,1]:
						for pin in 4:
							_box(Vector3(dimensions.x*.10,.20,dimensions.y*.17),Vector3(dimensions.x*(pin-1.5)*.24,.10,dimensions.y*.54*side),Color("ccb98e"),host)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		azimuth -= event.relative.x * .009
		elevation = clampf(elevation + event.relative.y * .009, -.9, 1.38)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (.89 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12), .48, 2.3)
	else: return
	_update_camera()
	accept_event()

func _update_camera() -> void:
	var look := Vector3(0,focal_height,0)
	camera.position = look + Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation)) * package_span * 2.8
	camera.look_at(look)
	camera.far = package_span * 8.0
	camera.size = package_span * 1.70 * zoom
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _box(dimensions: Vector3, at: Vector3, color: Color, host: Node3D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	_shape(mesh,at,color,host)

func _cylinder(radius: float, height: float, at: Vector3, color: Color, host: Node3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	return _shape(mesh,at,color,host)

func _shape(mesh: Mesh, at: Vector3, color: Color, host: Node3D) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .67
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	(geometry if host == null else host).add_child(instance)
	return instance

