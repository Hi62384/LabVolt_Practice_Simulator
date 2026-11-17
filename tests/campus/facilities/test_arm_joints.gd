extends SceneTree
const Toon=preload("res://scripts/toon_character.gd")
const Activity=preload("res://scripts/campus/facilities/avatar_activity.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for outfit in ["Tee","Hoodie"]:
		for scale_value in [.85,1.15]:
			var config: Dictionary=Toon.defaults();config.outfit=outfit;config.height=scale_value
			var avatar: Node3D=Toon.build(config);root.add_child(avatar)
			var activity=Activity.new();root.add_child(activity);activity.bind_visual(avatar)
			var arm: Node3D=avatar.get_node("Body/ArmR")
			var sleeve: MeshInstance3D=arm.get_node("Sleeve")
			var hand: Node3D=arm.get_node("Hand")
			var original_mesh:=sleeve.mesh;var original_hand:=hand.transform;var original_arm:=arm.transform
			activity.apply_event({"activity":"exercise","station":"gym/curl","exercise":"curl","phase":1,"half_ms":700},false)
			for i in 90:activity._process(.02)
			if sleeve.mesh==original_mesh or hand.position.distance_to(original_hand.origin)<.1:failures.append("Elbow did not bend: "+outfit)
			if not is_equal_approx(arm.rotation.x,original_arm.basis.get_euler().x):failures.append("Curl rotated the whole upper arm: "+outfit)
			activity.apply_event({"activity":"idle"},false)
			if sleeve.mesh!=original_mesh or hand.transform!=original_hand:failures.append("Elbow pose was not restored: "+outfit)
			activity.apply_event({"activity":"exercise","station":"gym/curl","exercise":"wrist_curl","phase":1,"half_ms":700},false)
			for i in 90:activity._process(.02)
			if hand.transform.basis.is_equal_approx(original_hand.basis):failures.append("Wrist did not rotate: "+outfit)
			activity.apply_event({"activity":"idle"},false)
			if hand.transform!=original_hand:failures.append("Wrist pose was not restored: "+outfit)
			activity.apply_event({"activity":"exercise","station":"gym/curl","exercise":"upright_row","phase":1,"half_ms":700},false)
			for i in 90:activity._process(.02)
			if sleeve.mesh==original_mesh or hand.transform==original_hand:failures.append("Upright row did not bend the elbow: "+outfit)
			activity.apply_event({"activity":"idle"},false)
			if sleeve.mesh!=original_mesh or hand.transform!=original_hand:failures.append("Upright row did not restore the arm: "+outfit)
			activity.free();avatar.free()
	var coordinator=preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not coordinator.load_catalog():failures.append("Could not load the avatar clothing catalog")
	else:
		for item_id in ["tops.harbor_fitted_tee","tops.cedar_layered_hoodie"]:
			_check_exported(coordinator,item_id)
	for failure in failures:push_error(failure)
	print("ARM_JOINTS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_exported(coordinator: RefCounted,item_id: String) -> void:
	var appearance:={"body":{"height":1.15,"width":1.2},"equipped":{"top_inner":{"id":item_id,"parameters":{}}}}
	var path:="user://joint_"+item_id.get_file()+".glb"
	if preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").save_glb(appearance,coordinator.catalog,path)!=OK:
		failures.append("Could not export "+item_id);return
	var avatar: Node3D=preload("res://scripts/avatar_model.gd").build(FileAccess.get_file_as_bytes(path))
	if avatar==null:failures.append("Could not load "+item_id);return
	root.add_child(avatar)
	var arm:=avatar.get_node_or_null("Body/ArmR") as Node3D
	var hand: Node3D=preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(arm)
	if not is_instance_valid(hand):failures.append("No exported hand for "+item_id);avatar.free();return
	var original:=hand.transform
	var clothing: Array=[]
	for child in arm.get_children():
		if child is MeshInstance3D and (str(child.name).begins_with("Sleeve") or str(child.name).begins_with("VisibleForearm")):
			clothing.append({"node":child,"mesh":child.mesh})
	if clothing.is_empty():failures.append("No exported arm clothing for "+item_id)
	var activity=Activity.new();root.add_child(activity);activity.bind_visual(avatar)
	activity.apply_event({"activity":"exercise","station":"gym/curl","exercise":"curl","phase":1,"half_ms":700},false)
	for i in 90:activity._process(.02)
	if hand.position.distance_to(original.origin)<.1:failures.append("Exported elbow did not bend: "+item_id)
	for part in clothing:
		if part.node.mesh==part.mesh:failures.append("Exported arm clothing did not bend: "+item_id)
	activity.apply_event({"activity":"idle"},false)
	if hand.transform!=original:failures.append("Exported hand did not restore: "+item_id)
	for part in clothing:
		if part.node.mesh!=part.mesh:failures.append("Exported arm clothing did not restore: "+item_id)
	activity.free();avatar.free()
