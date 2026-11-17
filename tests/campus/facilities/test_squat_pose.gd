extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var actor:=Node3D.new();root.add_child(actor)
	var avatar: Node3D=preload("res://scripts/toon_character.gd").build(preload("res://scripts/toon_character.gd").defaults());actor.add_child(avatar)
	var leg: Node3D=avatar.get_node("LegL")
	var trouser: MeshInstance3D=leg.get_node("Trouser")
	var shoe: Node3D=leg.get_node("Sneaker")
	var original_mesh:=trouser.mesh;var original_shoe:=shoe.transform
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();actor.add_child(activity);activity.bind_visual(avatar)
	activity.apply_event({"activity":"exercise","station":"gym/squat","exercise":"squat","phase":1,"half_ms":700},false)
	for i in 120:activity._process(.02)
	var changed:=trouser.mesh!=original_mesh and shoe.transform!=original_shoe and absf(shoe.global_position.y)<.15
	activity.apply_event({"activity":"idle"},false)
	var restored:=trouser.mesh==original_mesh and shoe.transform==original_shoe
	var exported: Node3D=preload("res://scripts/avatar_model.gd").build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	actor.add_child(exported)
	var exported_leg: Node3D=exported.get_node("LegR")
	var exported_trouser: MeshInstance3D=exported_leg.get_node("Trouser2")
	var exported_original:=exported_trouser.mesh
	activity.bind_visual(exported)
	activity.apply_event({"activity":"exercise","station":"gym/squat","exercise":"squat","phase":1,"half_ms":700},false)
	for i in 120:activity._process(.02)
	changed=changed and exported_trouser.mesh!=exported_original
	activity.apply_event({"activity":"idle"},false)
	restored=restored and exported_trouser.mesh==exported_original
	var coordinator=preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not coordinator.load_catalog():push_error("Cosmetics catalog unavailable");quit(1);return
	for item_id in ["bottoms.indigo_straight_jeans","bottoms.campus_work_shorts"]:
		var appearance:={"body":{"height":1.15,"width":1.2,"leg_width":1.25},"equipped":{"bottom":{"id":item_id,"parameters":{}}}}
		var path:="user://squat_%s.glb" % item_id.get_file()
		if preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").save_glb(appearance,coordinator.catalog,path)!=OK:
			push_error("Could not export customized clothing");quit(1);return
		var clothed: Node3D=preload("res://scripts/avatar_model.gd").build(FileAccess.get_file_as_bytes(path))
		if clothed==null:push_error("Could not load customized clothing");quit(1);return
		actor.add_child(clothed)
		var candidates:=[]
		for side in ["LegL","LegR"]:
			var clothed_leg: Node3D=clothed.get_node(side)
			for child in clothed_leg.get_children():
				if not (str(child.name).begins_with("Leg") or str(child.name).begins_with("Calf")):continue
				if child is MeshInstance3D:candidates.append(child)
				candidates.append_array(child.find_children("*","MeshInstance3D",true,false))
		if candidates.is_empty():push_error("No exported clothing geometry for " + item_id);quit(1);return
		var originals:=[]
		for mesh in candidates:originals.append(mesh.mesh)
		activity.bind_visual(clothed)
		activity.apply_event({"activity":"exercise","station":"gym/squat","exercise":"squat","phase":1,"half_ms":700},false)
		for i in 120:activity._process(.02)
		for i in candidates.size():changed=changed and candidates[i].mesh!=originals[i]
		activity.apply_event({"activity":"idle"},false)
		for i in candidates.size():restored=restored and candidates[i].mesh==originals[i]
		clothed.free()
	if not changed or not restored:push_error("Squat did not bend the leg, plant the foot, or restore the original appearance")
	actor.free()
	print("SQUAT_POSE ","PASS" if changed and restored else "FAIL")
	quit(0 if changed and restored else 1)
