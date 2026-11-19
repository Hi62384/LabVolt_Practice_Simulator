extends RefCounted
## Temporary cosmetic bend for the independently animated toon legs.
## Meshes are cached per phase and restored when the exercise ends.
const STEPS:=6
const KNEE:=Vector3(0,-.37,0)
const MAX_ANGLE:=-1.05
var parts: Array=[]
var feet: Array=[]
var step:=-1

func bind(legs: Dictionary) -> void:
	restore()
	for data in legs.values():
		var leg: Variant=data.node
		if not is_instance_valid(leg):continue
		for child in leg.get_children():
			if not child is Node3D:continue
			var name:=str(child.name)
			if name.begins_with("Trouser") or name.begins_with("Calf") or name.begins_with("Leg"):
				var meshes: Array=[]
				if child is MeshInstance3D:meshes.append(child)
				meshes.append_array(child.find_children("*","MeshInstance3D",true,false))
				for node in meshes:
					if node.mesh==null:continue
					parts.append({"node":node,"leg":leg,"original":node.mesh,"cache":{}})
			else:
				feet.append({"node":child,"original":child.transform})

func apply(phase: float, reverse := false) -> void:
	var next:=clampi(roundi(clampf(phase,0.0,1.0)*STEPS),0,STEPS)*(-1 if reverse else 1)
	if next==step:return
	step=next
	var angle:=MAX_ANGLE*float(next)/float(STEPS)
	if reverse:angle*=1.45
	var rotation:=Basis(Vector3.RIGHT,angle)
	for part in parts:
		var node: Variant=part.node
		var leg: Variant=part.leg
		if not is_instance_valid(node) or not is_instance_valid(leg):continue
		if node.mesh!=part.original and node.mesh not in part.cache.values():
			part.original=node.mesh;part.cache.clear()
		if next==0:node.mesh=part.original;continue
		if not part.cache.has(next):
			var frame: Transform3D=leg.global_transform.affine_inverse()*node.global_transform
			part.cache[next]=_bent_mesh(part.original,frame,rotation)
		node.mesh=part.cache[next]
	for foot in feet:
		var node: Variant=foot.node
		if not is_instance_valid(node):continue
		var base: Transform3D=foot.original
		# Translate the shoes with the shin while keeping their soles level.
		node.transform=Transform3D(base.basis,KNEE+rotation*(base.origin-KNEE)) if next!=0 else base

func restore() -> void:
	for part in parts:
		var node: Variant=part.node
		if is_instance_valid(node) and node.mesh in part.cache.values():node.mesh=part.original
	for foot in feet:
		if is_instance_valid(foot.node):foot.node.transform=foot.original
	parts.clear();feet.clear();step=-1

func _bent_mesh(source: Mesh,frame: Transform3D,rotation: Basis) -> ArrayMesh:
	var result:=ArrayMesh.new();var inverse:=frame.affine_inverse()
	var deformation_basis:=inverse.basis*rotation*frame.basis
	var normal_rotation:=deformation_basis.inverse().transposed()
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals:=PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL]!=null:normals=arrays[Mesh.ARRAY_NORMAL].duplicate()
		var tangents:=PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT]!=null:tangents=arrays[Mesh.ARRAY_TANGENT].duplicate()
		for i in vertices.size():
			var point:=frame*vertices[i]
			if point.y>=KNEE.y:continue
			vertices[i]=inverse*(KNEE+rotation*(point-KNEE))
			if i<normals.size():normals[i]=(normal_rotation*normals[i]).normalized()
			if i*4+3<tangents.size():
				var tangent: Vector3=(deformation_basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
				tangents[i*4]=tangent.x;tangents[i*4+1]=tangent.y;tangents[i*4+2]=tangent.z
		arrays[Mesh.ARRAY_VERTEX]=vertices
		if not normals.is_empty():arrays[Mesh.ARRAY_NORMAL]=normals
		if not tangents.is_empty():arrays[Mesh.ARRAY_TANGENT]=tangents
		var primitive: int=source.surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		result.add_surface_from_arrays(primitive,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result
