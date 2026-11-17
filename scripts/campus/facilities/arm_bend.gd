extends RefCounted
## Temporary exercise-only deformation in arm-local coordinates. Geometry is
## cached by pose and restored when the activity ends or the avatar changes.
const STEPS:=12
const ELBOW:=Vector3(0,-.22,0)
var parts: Array=[]
var hands: Array=[]
var step:=-1
var wrist_step:=-1
var side_step:=0

static func hand_for(arm: Node3D) -> Node3D:
	if not is_instance_valid(arm):return null
	for child in arm.get_children():
		if child is Node3D and str(child.name).begins_with("Hand"):return child
	return null

func bind(arms: Dictionary) -> void:
	restore()
	for data in arms.values():
		var arm: Node3D=data.node
		if not is_instance_valid(arm):continue
		for child in arm.get_children():
			if not child is Node3D:continue
			var name:=str(child.name)
			if name.begins_with("Hand") or name.begins_with("Thumb") or name.begins_with("Cuff"):
				hands.append({"node":child,"arm":arm,"original":child.transform})
			elif name.begins_with("Sleeve") or name.begins_with("Forearm") or name.begins_with("VisibleForearm"):
				var meshes: Array=[]
				if child is MeshInstance3D:meshes.append(child)
				meshes.append_array(child.find_children("*","MeshInstance3D",true,false))
				for node in meshes:
					if node.mesh!=null:parts.append({"node":node,"arm":arm,"original":node.mesh,"cache":{}})

func apply(elbow_angle: float,wrist_angle: float,side_angle: float=0.0) -> void:
	var next:=clampi(roundi(clampf(elbow_angle,-1.6,1.6)/1.6*STEPS),-STEPS,STEPS)
	var next_wrist:=clampi(roundi(clampf(wrist_angle,-1.0,1.0)*STEPS),-STEPS,STEPS)
	var next_side:=clampi(roundi(clampf(side_angle,0.0,2.0)/2.0*STEPS),0,STEPS)
	if next==step and next_wrist==wrist_step and next_side==side_step:return
	step=next;wrist_step=next_wrist;side_step=next_side
	var wrist:=Basis(Vector3.RIGHT,float(next_wrist)/float(STEPS))
	for part in parts:
		var node: MeshInstance3D=part.node
		var arm: Node3D=part.arm
		if not is_instance_valid(node) or not is_instance_valid(arm):continue
		if node.mesh!=part.original and node.mesh not in part.cache.values():
			part.original=node.mesh;part.cache.clear()
		if next==0 and next_side==0:node.mesh=part.original;continue
		var key:=Vector2i(next,next_side)
		if not part.cache.has(key):
			var frame:=arm.global_transform.affine_inverse()*node.global_transform
			part.cache[key]=_bent_mesh(part.original,frame,_bend_for(arm,next,next_side))
		node.mesh=part.cache[key]
	for hand in hands:
		var node: Node3D=hand.node
		if not is_instance_valid(node):continue
		var bend:=_bend_for(hand.arm,next,next_side)
		var base: Transform3D=hand.original
		node.transform=Transform3D(bend*base.basis*wrist,ELBOW+bend*(base.origin-ELBOW))

func _bend_for(arm: Node3D,elbow_step: int,lateral_step: int) -> Basis:
	var side: float=1.0 if str(arm.name).ends_with("R") else -1.0
	return Basis(Vector3.FORWARD,side*2.0*float(lateral_step)/float(STEPS))*Basis(Vector3.RIGHT,-1.6*float(elbow_step)/float(STEPS))

func restore() -> void:
	for part in parts:
		var node: MeshInstance3D=part.node
		if is_instance_valid(node) and node.mesh in part.cache.values():node.mesh=part.original
	for hand in hands:
		if is_instance_valid(hand.node):hand.node.transform=hand.original
	parts.clear();hands.clear();step=-1;wrist_step=-1;side_step=0

func _bent_mesh(source: Mesh,frame: Transform3D,rotation: Basis) -> ArrayMesh:
	var result:=ArrayMesh.new();var inverse:=frame.affine_inverse()
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals:=PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL]!=null:normals=arrays[Mesh.ARRAY_NORMAL].duplicate()
		for i in vertices.size():
			var point:=frame*vertices[i]
			var influence:=smoothstep(ELBOW.y+.035,ELBOW.y-.035,point.y)
			if influence<=0.0:continue
			var local_bend:=Basis.IDENTITY.slerp(rotation,influence)
			vertices[i]=inverse*(ELBOW+local_bend*(point-ELBOW))
			if i<normals.size():
				var normal_basis:=inverse.basis*local_bend*frame.basis
				normals[i]=(normal_basis.inverse().transposed()*normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices
		if not normals.is_empty():arrays[Mesh.ARRAY_NORMAL]=normals
		# The deformed mesh has no reliable original tangent frame.
		arrays[Mesh.ARRAY_TANGENT]=null
		var primitive: int=source.surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		result.add_surface_from_arrays(primitive,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result
