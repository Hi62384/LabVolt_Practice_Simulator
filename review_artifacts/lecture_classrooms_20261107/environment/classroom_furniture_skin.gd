extends RefCounted
## Visual skin for existing authoritative desk bodies. No new collision or seat state.
const WOOD := Color("ac8864")
const NAVY := Color("344955")
const STEEL := Color("667780")
static var mats: Dictionary={}

static func dress_desk(desk: StaticBody3D) -> bool:
	if not is_instance_valid(desk) or desk.get_meta("role","")!="table":return false
	var collision: CollisionShape3D=null
	for child in desk.get_children():
		if child is CollisionShape3D:collision=child
	if collision==null or not collision.shape is BoxShape3D:return false
	var shape: BoxShape3D=collision.shape
	if not shape.size.is_equal_approx(Vector3(1.7,.07,.8)):return false
	if desk.has_node("ClassroomDeskSkin"):return true
	var visual:=Node3D.new();visual.name="ClassroomDeskSkin";desk.add_child(visual)
	# Existing collision retains tabletop y=.8; top is visually flush.
	_box(visual,Vector3.ZERO,Vector3(1.70,.07,.80),WOOD)
	_box(visual,Vector3(0,-.08,.29),Vector3(1.42,.065,.04),NAVY)
	for x in [-.68,.68]:
		for z in [-.28,.28]:
			# World bottom .765-.385-.37=.010; no floor penetration.
			_box(visual,Vector3(x,-.385,z),Vector3(.05,.74,.05),STEEL)
	for child in desk.get_children():
		if child!=visual and child is MeshInstance3D:child.hide()
	return true

static func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var key:=color.to_html()
	if not mats.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.83;mats[key]=material
	var mesh:=BoxMesh.new();mesh.size=size
	var inst:=MeshInstance3D.new();inst.mesh=mesh;inst.position=at;inst.material_override=mats[key];inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(inst)
