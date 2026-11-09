extends RefCounted
## DC-only renderer; no M101 geometry or resource changes.
const Plug = preload("res://review_artifacts/m103_dc_rebuild_20261107/physical_models/plug.gd")

static func from_ports(lab: Node,a_index: int,a_id: String,a: Vector3,b_index: int,b_id: String,b: Vector3,color: Color,obstacles: Array[AABB]) -> Node3D:
	var frames: Array[Transform3D]=[Transform3D(Basis.IDENTITY,a),Transform3D(Basis.IDENTITY,b)]
	var plugged := [false,false]
	var indexes := [a_index,b_index];var ids := [a_id,b_id]
	for i in 2:
		if indexes[i]<0 or indexes[i]>=3:continue
		var fixture: Node=lab.instrument_fixtures[indexes[i]]
		if fixture.binding.sockets.openings.has(ids[i]):
			frames[i]=fixture.binding.sockets.anchor(ids[i]);plugged[i]=true
	return build(a,b,color,obstacles,frames[0],frames[1],plugged[0],plugged[1])

static func build(a: Vector3,b: Vector3,color: Color,obstacles: Array[AABB],a_frame: Transform3D,b_frame: Transform3D,a_plug := true,b_plug := true) -> Node3D:
	var root := Node3D.new()
	# Geometry is authored in world coordinates, as in existing cable_mesh.build.
	var a_tail := a+a_frame.basis.z.normalized()*.16 if a_plug else a
	var b_tail := b+b_frame.basis.z.normalized()*.16 if b_plug else b
	root.add_child(preload("res://scripts/cable_mesh.gd").build(a_tail,b_tail,color,obstacles))
	for pair in [[a,a_frame,a_plug],[b,b_frame,b_plug]]:
		if not pair[2]:continue
		# Construct locally before parenting to the live tree; no global transform calls.
		var plug := MeshInstance3D.new();plug.mesh=Plug.PLUG
		plug.transform=Transform3D(Basis(Quaternion(Vector3.BACK,pair[1].basis.z.normalized())),pair[0])
		plug.set_meta("electrical_contact",pair[0]);plug.set_meta("cable_tail_local",Vector3(0,0,.16))
		root.add_child(plug)
	return root
