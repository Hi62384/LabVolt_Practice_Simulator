extends RefCounted
## One triangle surface per flexible cable, with analytic gravity sag.
const JACKET_RADIUS := .009
const END_TAPER := .028
const BOARD_APPROACH := .06
static func build(a: Vector3,b: Vector3,color: Color,obstacles:Array[AABB]=[]) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = geometry(a,b,obstacles)
	mesh.material_override = jacket_material(color)
	return mesh

static func geometry(a: Vector3,b: Vector3,obstacles:Array[AABB]=[]) -> ArrayMesh:
	var points: Array[Vector3] = []
	var distance := a.distance_to(b)
	for i in range(25):
		var t := i/24.0
		var point := a.lerp(b,t) + Vector3(0,-sin(PI*t)*(0.12+distance*0.13),sin(PI*t)*0.12)
		point.y = maxf(point.y,0.035)
		points.append(point)
	return tube(preload("res://scripts/cable_route.gd").route(points,obstacles))

static func held_geometry(anchor: Vector3,grip: Vector3,view: Basis,attached: bool,anchor_radius := JACKET_RADIUS,board_bounds: Array[AABB]=[]) -> ArrayMesh:
	var points: Array[Vector3] = []
	for i in range(25):
		var t := i/24.0
		if attached:
			points.append(anchor.lerp(grip,t)+Vector3.DOWN*sin(PI*t)*minf(.10,anchor.distance_to(grip)*.14))
		else:
			var angle := t*TAU*.89
			points.append(grip+view*Vector3(-.13*(1.0-cos(angle)),-.12*sin(angle),-.05*t))
	return tube(clear_boards(points,board_bounds),anchor_radius)

static func clear_boards(points: Array[Vector3], boards: Array[AABB]) -> Array[Vector3]:
	if points.size()<2:return points
	for board in boards:
		var footprint := AABB(Vector3(board.position.x,-1,board.position.z),Vector3(board.size.x,2,board.size.z)).grow(JACKET_RADIUS)
		var height := board.end.y+JACKET_RADIUS+.002
		var path: Array[Vector3]=[points[0]]
		for i in range(1,points.size()):
			var a := points[i-1]
			var b := points[i]
			var flat_a := Vector3(a.x,0,a.z)
			var flat_b := Vector3(b.x,0,b.z)
			if minf(a.y,b.y)<height:
				var distance := flat_a.distance_to(flat_b)
				var splits: Array[float]=[]
				if distance>.0001:
					for margin: float in [BOARD_APPROACH,BOARD_APPROACH*.5,0.0]:
						var region := footprint.grow(margin)
						for boundary in [region.intersects_segment(flat_a,flat_b),region.intersects_segment(flat_b,flat_a)]:
							if boundary is Vector3:
								var t := flat_a.distance_to(boundary)/distance
								if t>.0001 and t<.9999:splits.append(t)
					splits.sort()
				for t in splits:
					var point := _raise_over_board(a.lerp(b,t),footprint,height,points[0],points[-1])
					if not point.is_equal_approx(path[-1]):path.append(point)
				if i<points.size()-1:b=_raise_over_board(b,footprint,height,points[0],points[-1])
			if not b.is_equal_approx(path[-1]):path.append(b)
		points=path
	return points

static func _raise_over_board(point: Vector3, footprint: AABB, height: float, start: Vector3, end: Vector3) -> Vector3:
	var distance := Vector2(
		maxf(footprint.position.x-point.x,point.x-footprint.end.x),
		maxf(footprint.position.z-point.z,point.z-footprint.end.z)).max(Vector2.ZERO).length()
	for endpoint in [start,end]:
		if footprint.has_point(Vector3(endpoint.x,0,endpoint.z)):
			var from_end := Vector2(point.x-endpoint.x,point.z-endpoint.z).length()
			height=minf(height,lerpf(endpoint.y,height,smoothstep(0.0,END_TAPER,from_end)))
	point.y+=maxf(0.0,height-point.y)*(1.0-smoothstep(0.0,BOARD_APPROACH,distance))
	return point

static func tube(points: Array[Vector3],start_radius := JACKET_RADIUS,end_radius := JACKET_RADIUS) -> ArrayMesh:
	if points.size()<2:return ArrayMesh.new()
	var length := 0.0
	for i in range(1,points.size()):length+=points[i-1].distance_to(points[i])
	var samples: Array[float]=[]
	for fraction: float in [.25,.5,.75,1.0]:
		var distance := minf(END_TAPER,length*.5)*fraction
		if start_radius!=JACKET_RADIUS:samples.append(distance)
		if end_radius!=JACKET_RADIUS:samples.append(length-distance)
	samples.sort()
	var path: Array[Vector3]=[points[0]]
	var travelled := 0.0
	var sample := 0
	for i in range(1,points.size()):
		var segment := points[i-1].distance_to(points[i])
		while sample<samples.size() and samples[sample]<travelled+segment:
			var point := points[i-1].lerp(points[i],(samples[sample]-travelled)/segment)
			if not point.is_equal_approx(path[-1]):path.append(point)
			sample+=1
		if not points[i].is_equal_approx(path[-1]):path.append(points[i])
		travelled+=segment
	if path.size()<2:return ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3.ZERO
	var previous_tangent := Vector3.ZERO
	travelled=0.0
	for i in path.size():
		var incoming := (path[i]-path[maxi(i-1,0)]).normalized()
		var outgoing := (path[mini(i+1,path.size()-1)]-path[i]).normalized()
		var tangent := (incoming+outgoing).normalized()
		if tangent.is_zero_approx():tangent=incoming
		if i==0:
			normal=tangent.cross(Vector3.UP if absf(tangent.y)<.9 else Vector3.RIGHT).normalized()
		else:
			if previous_tangent.dot(tangent)>-.999:
				normal=Quaternion(previous_tangent,tangent)*normal
			normal=(normal-tangent*normal.dot(tangent)).normalized()
			travelled+=path[i-1].distance_to(path[i])
		previous_tangent=tangent
		var binormal := tangent.cross(normal).normalized()
		var radius := JACKET_RADIUS
		if start_radius!=JACKET_RADIUS:
			radius=minf(radius,lerpf(start_radius,JACKET_RADIUS,smoothstep(0.0,END_TAPER,travelled)))
		if end_radius!=JACKET_RADIUS:
			radius=minf(radius,lerpf(end_radius,JACKET_RADIUS,smoothstep(0.0,END_TAPER,length-travelled)))
		for j in range(8):
			var angle := TAU*j/8.0
			var radial := normal*cos(angle)+binormal*sin(angle)
			surface.set_normal(radial)
			surface.add_vertex(path[i]+radius*radial)
	for i in range(path.size()-1):
		for j in range(8):
			var k := (j+1)%8
			var ring := i*8
			for index in [ring+j,ring+8+j,ring+8+k,ring+j,ring+8+k,ring+k]:
				surface.add_index(index)
	return surface.commit()

static func jacket_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
