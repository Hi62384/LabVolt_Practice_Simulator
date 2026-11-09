extends RefCounted
## Geometry only. Physical/electrical contact point is the socket opening.
const PLUG := preload("res://review_artifacts/m103_dc_rebuild_20261107/physical_models/meshes/plug.obj")
static func attach(parent: Node3D,socket_opening: Vector3, outward_normal: Vector3, jacket_color: Color) -> MeshInstance3D:
	var plug := MeshInstance3D.new();plug.mesh=PLUG
	parent.add_child(plug)
	plug.global_position=socket_opening
	plug.quaternion=Quaternion(Vector3.BACK,outward_normal.normalized())
	# The conductor starts at local Z=0, the strain relief ends at Z=.16.
	# A renderer may bend the cable from plug.to_global(Vector3(0,0,.16)).
	plug.set_meta("electrical_contact",socket_opening)
	plug.set_meta("cable_tail_local",Vector3(0,0,.16))
	plug.set_meta("jacket_color",jacket_color)
	return plug
