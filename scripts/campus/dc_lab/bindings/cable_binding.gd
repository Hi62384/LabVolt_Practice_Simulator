extends RefCounted
## Seat the shared banana plugs on the DC fixture's actual socket faces.

const CableMesh = preload("res://scripts/cable_mesh.gd")
const PLUG_LENGTH := .095
const SEAT_OFFSET := .038

static func end_radius(lab: Node, index: int, id: String) -> float:
	if index in range(lab.physical_boards.size()) and (id in ["B1","B2","B3","B4"] or id.begins_with("X")):
		return .010*float(lab.physical_boards[index].display_scale)
	return CableMesh.JACKET_RADIUS

static func add_end(root: Node3D, lab: Node, index: int, id: String, point: Vector3, color: Color, layer: int = 0) -> Vector3:
	var axis := Vector3.UP
	var opening: Marker3D
	if index >= 0 and index < lab.instrument_fixtures.size():
		opening = lab.instrument_fixtures[index].binding.sockets.openings.get(id)
	elif index >= lab.physical_boards.size():
		axis = Vector3.BACK
		point += axis * .08
	if is_instance_valid(opening):
		axis = opening.global_basis.z.normalized()
		point = opening.global_position + axis * (SEAT_OFFSET + layer * PLUG_LENGTH)

	if not is_instance_valid(opening) and index in range(lab.physical_boards.size()) and (id.begins_with("B") or id.begins_with("X")):
		var radius := end_radius(lab,index,id)
		var sleeve: MeshInstance3D = lab.game._cylinder(root, point + Vector3.UP * radius*1.8, radius*1.25, radius*3.8, color, .25)
		sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return point + Vector3.UP * radius*3.6

	var basis := Basis(Quaternion(Vector3.UP, axis))
	var connector: MeshInstance3D = lab.game._cylinder(root, point, .023, PLUG_LENGTH, color, .3)
	connector.basis = basis
	var pin: MeshInstance3D = lab.game._cylinder(root, point - axis * .045, .009, .045, Color("b5b8ae"), .8)
	pin.basis = basis
	if is_instance_valid(opening):
		var socket := StaticBody3D.new()
		socket.collision_layer = 4
		socket.collision_mask = 0
		socket.position = point + axis * .048
		var target: Node = opening.get_child(0)
		for key in ["role", "dc_station", "dc_port", "label", "dc_opening", "dc_hover_visual"]:
			if target.has_meta(key):socket.set_meta(key, target.get_meta(key))
		var hit := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = .032
		hit.shape = shape
		socket.add_child(hit)
		root.add_child(socket)
		var cap: MeshInstance3D = lab.game._cylinder(socket, Vector3.ZERO, .012, .003, Color("101519"))
		cap.basis = basis
	return point

static func from_ports(lab: Node, a_index: int, a_id: String, a: Vector3, b_index: int, b_id: String, b: Vector3, color: Color, obstacles: Array[AABB], layers: Dictionary) -> Node3D:
	var root := Node3D.new()
	var a_key := "%d:%s" % [a_index, a_id]
	var b_key := "%d:%s" % [b_index, b_id]
	a = add_end(root, lab, a_index, a_id, a, color, int(layers.get(a_key, 0)))
	layers[a_key] = int(layers.get(a_key, 0)) + 1
	b = add_end(root, lab, b_index, b_id, b, color, int(layers.get(b_key, 0)))
	layers[b_key] = int(layers.get(b_key, 0)) + 1
	var cable := MeshInstance3D.new()
	var route := CableMesh.clear_boards(_surface_route(a,b,obstacles),lab.breadboard_cable_bounds)
	cable.mesh = CableMesh.tube(route,end_radius(lab,a_index,a_id),end_radius(lab,b_index,b_id))
	cable.material_override = CableMesh.jacket_material(color)
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cable)
	return root


static func _surface_route(a: Vector3, b: Vector3, obstacles: Array[AABB]) -> Array[Vector3]:
	var envelope := AABB(a, Vector3.ZERO).expand(b).grow(.6)
	var blockers: Array[AABB] = []
	var worktops: Array[AABB] = []
	for obstacle in obstacles:
		if not envelope.intersects(obstacle):
			continue
		if obstacle.size.y <= .16 and minf(a.y,b.y) >= obstacle.end.y - .015:
			worktops.append(obstacle.grow(.023))
		else:
			blockers.append(obstacle)
	var points: Array[Vector3] = []
	var sag := minf(.36, .09 + a.distance_to(b) * .10)
	for i in range(21):
		var t := i/20.0
		var point := a.lerp(b,t) + Vector3(0,-sag,.08)*sin(PI*t)
		if i>0 and i<20:
			point.y=maxf(point.y,.035)
			for table in worktops:
				if point.x >= table.position.x and point.x <= table.end.x and point.z >= table.position.z and point.z <= table.end.z:
					var blend := maxf(.018-absf(point.y-table.end.y),0.0)/.018
					point.y=maxf(point.y,table.end.y)+.0045*blend*blend
		points.append(point)
	return preload("res://scripts/cable_route.gd").route(points,blockers)
