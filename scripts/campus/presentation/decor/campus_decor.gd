class_name CampusDecor
extends Node3D
## Additive, non-interactive dressing. No physics, lights, process loops or save state.

const DATA_PATH := "res://assets/campus/decor/room_dressing.json"
const MESH_ROOT := "res://assets/campus/decor/meshes/"
var data: Dictionary = {}
var room_roots: Dictionary = {}
var materials: Dictionary = {}

func _init() -> void:
	var file := FileAccess.open(DATA_PATH,FileAccess.READ)
	if file:
		var parsed: Variant=JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:data=parsed

func has_room(room_id: String) -> bool:
	return data.get("rooms",{}).has(room_id)

func build_room(room_id: String,parent: Node3D) -> Node3D:
	if not has_room(room_id) or not is_instance_valid(parent):return null
	if room_roots.has(room_id) and is_instance_valid(room_roots[room_id]):return room_roots[room_id]
	var profile: Dictionary=data.rooms[room_id]
	var root:=Node3D.new();root.name="Decor_"+room_id;root.set_meta("room_id",room_id);root.set_meta("theme",profile.theme);parent.add_child(root)
	for group in profile.get("groups",[]):_add_batch(root,group)
	for sign_data in profile.get("signs",[]):_add_sign(root,sign_data)
	room_roots[room_id]=root
	return root

func build_all(registry: Object,parent: Node3D,include_ids: Array=[]) -> Dictionary:
	var result:={"built":[],"missing":[]}
	if not is_instance_valid(registry):return result
	for room_id in data.get("rooms",{}):
		if not include_ids.is_empty() and not room_id in include_ids:continue
		var room: Dictionary=registry.call("get_room",room_id) if registry.has_method("get_room") else {}
		if room.is_empty():result.missing.append(room_id)
		else:
			build_room(room_id,parent);result.built.append(room_id)
	return result

func register_streamed(campus: Node,include_ids: Array=[]) -> int:
	# Preferred integration: one bounded loader per existing campus room.
	if not is_instance_valid(campus) or not campus.has_method("register_loader"):return 0
	var count:=0
	for room_id in data.get("rooms",{}):
		if not include_ids.is_empty() and not room_id in include_ids:continue
		var id:=str(room_id)
		var loader:=Callable(self,"_load_streamed").bind(id,campus)
		if campus.call("register_loader",id,loader):count+=1
	return count

func _load_streamed(room_id: String,campus: Node) -> bool:
	var root:=build_room(room_id,campus)
	if root==null:return true # Invalid catalog entries must not churn the loader queue.
	return bool(campus.call("register_content",room_id,root)) if campus.has_method("register_content") else true

func remove_room(room_id: String) -> void:
	if room_roots.has(room_id) and is_instance_valid(room_roots[room_id]):room_roots[room_id].queue_free()
	room_roots.erase(room_id)

func _add_batch(parent: Node3D,group: Dictionary) -> void:
	var mesh_path:=MESH_ROOT+str(group.get("mesh",""))+".obj"
	var mesh: Mesh=load(mesh_path)
	if mesh==null:return
	var items: Array=group.get("items",[])
	var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=mesh;multimesh.instance_count=items.size()
	for i in items.size():
		var t: Array=items[i]
		var basis:=Basis(Vector3.UP,deg_to_rad(float(t[3]))).scaled(Vector3(float(t[4]),float(t[5]),float(t[6])))
		multimesh.set_instance_transform(i,Transform3D(basis,Vector3(float(t[0]),float(t[1]),float(t[2]))))
	var instance:=MultiMeshInstance3D.new();instance.name=str(group.mesh).to_pascal_case();instance.multimesh=multimesh;instance.material_override=_material(str(group.material));instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;parent.add_child(instance)

func _add_sign(parent: Node3D,entry: Dictionary) -> void:
	var values: Array=entry.position
	var label:=Label3D.new();label.text=str(entry.text);label.font_size=48;label.pixel_size=.0035;label.outline_size=8;label.modulate=_color(str(entry.color));label.outline_modulate=Color("19232a");label.position=Vector3(float(values[0]),float(values[1]),float(values[2]));label.rotation.y=deg_to_rad(float(entry.get("yaw",0)));label.no_depth_test=false;parent.add_child(label)

func _material(id: String) -> StandardMaterial3D:
	if materials.has(id):return materials[id]
	var material:=StandardMaterial3D.new();material.albedo_color=_color(id);material.roughness=.72;material.metallic=.18 if id in ["steel","gold"] else .03
	materials[id]=material;return material

func _color(id: String) -> Color:
	return Color(str(data.get("palette",{}).get(id,"b8b8b8")))
