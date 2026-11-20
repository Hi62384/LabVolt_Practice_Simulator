extends Control
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")

signal cell_clicked(cell: Vector3i, part_index: int)

var design: Dictionary={}
var library: Dictionary={}
var pcbs: Dictionary={}
var placement_height := 0
var _camera: Camera3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _parts: Array=[]
var _selection_bounds: Array[Dictionary]=[]
var _powered_parts: Array[MeshInstance3D]=[]
var joints: Array[Dictionary]=[]
var camera_state: Dictionary={"focus":Vector3.ZERO,"distance":4.2,"yaw":.65,"pitch":.72}
var _orbiting := false
var _panning := false

func _ready() -> void:
	mouse_filter=MOUSE_FILTER_STOP
	var container:=SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter=MOUSE_FILTER_IGNORE
	container.stretch=true
	add_child(container)
	var viewport:=SubViewport.new()
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var scene:=Node3D.new()
	viewport.add_child(scene)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("152b38")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c5deed")
	environment.environment.ambient_light_energy=.65
	scene.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-35,0)
	scene.add_child(light)
	_camera=Camera3D.new()
	scene.add_child(_camera)
	_update_camera()
	var grid:=ImmediateMesh.new()
	var grid_material:=StandardMaterial3D.new()
	grid_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color=Color("4a6b7c")
	grid.surface_begin(Mesh.PRIMITIVE_LINES,grid_material)
	for index in range(-6,8):
		var mark:=(float(index)-.5)*.3
		grid.surface_add_vertex(Vector3(mark,-.014,-1.95))
		grid.surface_add_vertex(Vector3(mark,-.014,1.95))
		grid.surface_add_vertex(Vector3(-1.95,-.014,mark))
		grid.surface_add_vertex(Vector3(1.95,-.014,mark))
	grid.surface_end()
	var floor_grid:=MeshInstance3D.new()
	floor_grid.mesh=grid
	scene.add_child(floor_grid)
	_parts=design.get("parts",[]).duplicate(true)
	# The render expands nested blueprints, so use their *visible* member
	# footprints for editor hit-testing. Keep the index of the containing
	# top-level part so selecting/moving a nested design remains intuitive.
	_selection_bounds.clear()
	for source_index in _parts.size():
		var outer: Dictionary=_parts[source_index]
		var selectable: Array=[outer]
		if outer.get("type","")=="nested" and library.has(str(outer.get("ref",""))):
			var descendants: Array=Model.flattened(str(outer.ref),library,pcbs)
			if not descendants.is_empty():
				selectable=[]
				for inner in descendants:
					var cell:=Vector3i(outer.x,outer.y,outer.z)+Model.rotate_grid(Vector3i(inner.x,inner.y,inner.z),int(outer.get("turns",0)))
					selectable.append({"x":cell.x,"y":cell.y,"z":cell.z})
		for member in selectable:
			var point:=Vector3(member.x,member.y,member.z)*.3+Vector3(-.15,-.01,-.15)
			_selection_bounds.append({"index":source_index,"bounds":AABB(point,Vector3.ONE*.3)})
	var visible_parts: Array=_parts
	if library.has("inv:preview") and Model.validate("inv:preview",library,pcbs)=="":
		visible_parts=Model.flattened("inv:preview",library,pcbs)
	Model.connect_wheels(visible_parts)
	var instances: Array[MeshInstance3D]=[]
	for part in visible_parts:
		var kind:=str(part.get("type",""))
		var instance:=MeshInstance3D.new()
		if kind=="wheel":
			var wheel:=CylinderMesh.new()
			wheel.top_radius=.14
			wheel.bottom_radius=.14
			wheel.height=.09
			instance.mesh=wheel
			instance.rotation.z=PI/2
		else:
			var part_box:=BoxMesh.new()
			part_box.size=Vector3(.24,.12,.24) if kind in ["pcb","battery","switch"] else Vector3(.28,.2,.28)
			instance.mesh=part_box
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(str(Model.PARTS.get(kind,{}).get("color","aaaaaa")))
		instance.material_override=material
		instance.position=Vector3(part.x,part.y,part.z)*.3+Vector3.UP*.14
		instance.rotation.y=float(part.get("turns",0))*PI*.5
		scene.add_child(instance)
		instances.append(instance)
		if kind=="wheel":
			instance.set_meta("kind",kind)
			instance.set_meta("channel",part.get("motor_control",""))
			instance.set_meta("roll",0.0)
			instance.set_meta("rest",instance.transform)
			_powered_parts.append(instance)
	joints=Model.hinges(visible_parts)
	for joint in joints:
		joint.angle=0.0
		joint.manual=false
		joint.bindings=[]
		for index in joint.indices:
			var instance := instances[index]
			joint.bindings.append({"node":instance,"rest":instance.transform})
	for joint in joints:
		if joint.chain.size()>1:
			var mount:=instances[joint.part_index]
			joints[joint.chain[-2]].bindings.append({"node":mount,"rest":mount.transform})
	_ghost=MeshInstance3D.new()
	var ghost_box:=BoxMesh.new()
	ghost_box.size=Vector3(.286,.286,.286)
	_ghost.mesh=ghost_box
	_ghost_material=StandardMaterial3D.new()
	_ghost_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override=_ghost_material
	_ghost.hide()
	scene.add_child(_ghost)
	mouse_exited.connect(_ghost.hide)

func preview_power(delta: float, channels: Dictionary, battery: bool) -> void:
	for instance in _powered_parts:
		instance.transform=instance.get_meta("rest")
	for joint in joints:
		if joint.chain.is_empty():continue
		if joint.control=="":
			joint.angle=move_toward(float(joint.angle),Model.HINGE_OPEN if joint.manual else 0.0,Model.HINGE_SPEED*delta)
		else:
			joint.angle=Model.hinge_angle(joint.angle,joint.control,channels,battery,delta)
	for joint in joints:
		var pose:=Model.hinge_pose(joints,joint.chain)
		for binding in joint.bindings:binding.node.transform=pose*binding.rest
	for instance in _powered_parts:
		var active: bool=battery and channels.get(instance.get_meta("channel"),false)
		var roll: float=instance.get_meta("roll")
		if active:roll=wrapf(roll+delta*.5/.14,0.0,TAU)
		instance.set_meta("roll",roll)
		instance.rotate_object_local(Vector3.UP,roll)

func _update_camera() -> void:
	var pitch:=float(camera_state.pitch)
	var yaw:=float(camera_state.yaw)
	var focus: Vector3=camera_state.focus
	var direction:=Vector3(cos(pitch)*sin(yaw),sin(pitch),cos(pitch)*cos(yaw))
	_camera.position=focus+direction*float(camera_state.distance)
	_camera.look_at(focus)

func _grid_cell(at: Vector2) -> Vector3i:
	var origin:=_camera.project_ray_origin(at)
	var direction:=_camera.project_ray_normal(at)
	var plane:=Plane(Vector3.UP,float(placement_height)*.3)
	var hit: Variant=plane.intersects_ray(origin,direction)
	if hit==null:return Vector3i(99,0,99)
	return Vector3i(roundi(hit.x/.3),placement_height,roundi(hit.z/.3))

func _inside_grid(cell: Vector3i) -> bool:
	return absi(cell.x)<=6 and absi(cell.z)<=6

func _pick_part(at: Vector2) -> int:
	var origin:=_camera.project_ray_origin(at)
	var direction:=_camera.project_ray_normal(at)
	var nearest:=INF
	var found:=-1
	for entry in _selection_bounds:
		var bounds: AABB=entry.bounds
		var hit: Variant=bounds.intersects_ray(origin,direction)
		if hit==null:continue
		var depth:=origin.distance_squared_to(hit)
		if depth<nearest:
			found=int(entry.index)
			nearest=depth
	return found

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: _orbiting=event.pressed
			MOUSE_BUTTON_MIDDLE: _panning=event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					camera_state.distance=clampf(float(camera_state.distance)*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.11),1.0,12.0)
					_update_camera()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					var cell:=_grid_cell(event.position)
					var index:=_pick_part(event.position)
					if _inside_grid(cell) or index>=0:cell_clicked.emit(cell,index)
			_: return
		accept_event()
	elif event is InputEventMouseMotion:
		if _orbiting:
			camera_state.yaw-=event.relative.x*.009
			camera_state.pitch=clampf(float(camera_state.pitch)+event.relative.y*.009,.13,1.52)
			_update_camera()
		elif _panning:
			var camera_scale:=float(camera_state.distance)*.002
			camera_state.focus-=_camera.basis.x*event.relative.x*camera_scale
			camera_state.focus+=_camera.basis.y*event.relative.y*camera_scale
			_update_camera()
		var cell:=_grid_cell(event.position)
		_ghost.visible=_inside_grid(cell) and not _orbiting and not _panning
		if _ghost.visible:
			_ghost.position=Vector3(cell)*.3+Vector3.UP*.14
			_ghost_material.albedo_color=Color(1,.32,.25,.42) if _pick_part(event.position)>=0 else Color(.23,.92,.77,.42)
		accept_event()
