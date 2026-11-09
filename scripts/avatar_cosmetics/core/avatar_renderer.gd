extends RefCounted
const BodyFit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")
const BodyDeformation = preload("res://scripts/avatar_cosmetics/body_deformation/rig_adapter.gd")
const Toon = preload("res://scripts/toon_character.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Footwear = preload("res://scripts/avatar_cosmetics/footwear/footwear_provider.gd")
const Clothing = preload("res://scripts/avatar_cosmetics/clothing/clothing_provider.gd")
const Accessories = preload("res://scripts/avatar_cosmetics/accessories/accessory_provider.gd")
const FacesHair = preload("res://scripts/avatar_cosmetics/faces_hair/faces_hair_provider.gd")

static func render_avatar(state: Dictionary,catalog: Dictionary, live := false, fit_cache := {}) -> Node3D:
	var body := Core.sanitize_body(state.get("body",{}))
	var legacy: Dictionary=state.get("legacy_character",{}).duplicate(true)
	for pair in [["height","height"],["width","build"],["head","head"],["head_width","face_width"],["head_height","face_height"],["shoulders","shoulders"],["waist","waist"],["arm_length","arm_length"],["hands","hand_size"],["leg_length","leg_length"],["feet","shoe_size"],["skin","skin"]]:legacy[pair[1]]=body[pair[0]]
	body["__live_preview"] = live
	var avatar := Toon.build(legacy,body)
	body = BodyFit.provider_context(body,Toon.sanitize(legacy))
	var shape := BodyFit.parameters(body)
	var colors := {}
	var entry = state.get("equipped",{}).get("footwear",{})
	if entry is Dictionary and catalog.has(entry.get("id","")):
		var definition: Dictionary=catalog[entry.id]
		var pair := Footwear.instantiate(definition,Core.sanitize_parameters(definition,entry.get("parameters",{})),body)
		if pair!=null:
			if live: _bind_colors(pair, definition, colors)
			if Footwear.attach_to_avatar(avatar,pair):
				for leg_name in ["LegL","LegR"]:
					_hide_matching(avatar.get_node(leg_name),["Sneaker","Sole","ShoeLace"])
			pair.free()
	for slot in Core.SLOTS:
		if slot=="footwear":continue
		if slot == "top_inner" and catalog.has(state.get("equipped", {}).get("top_outer", {}).get("id", "")):continue
		var equipped = state.get("equipped",{}).get(slot,{})
		if not equipped is Dictionary or not catalog.has(equipped.get("id","")):continue
		var definition: Dictionary=catalog[equipped.id]
		var parameters := Core.sanitize_parameters(definition,equipped.get("parameters",{}))
		var is_clothing: bool=slot in ["top_inner","top_outer","bottom"]
		var is_face_hair: bool=slot in ["face","hair","facial_hair"]
		var instance: Node3D
		if is_clothing:instance=Clothing.instantiate(definition,parameters,body,fit_cache if live else {})
		elif is_face_hair:instance=FacesHair.instantiate(definition,parameters,body)
		else:instance=Accessories.instantiate(definition,parameters,body)
		if instance==null:continue
		if live: _bind_colors(instance, definition, colors)
		var attached: bool=false
		if is_clothing:attached=Clothing.attach_to_avatar(avatar,instance)
		elif is_face_hair:attached=FacesHair.attach_to_avatar(avatar,instance,definition)
		else:attached=Accessories.attach_to_avatar(avatar,instance,definition)
		if not attached:instance.free();continue
		if is_clothing:
			if slot=="bottom":
				for leg in ["LegL","LegR"]:_hide_matching(avatar.get_node(leg),["Trouser"])
				if "exposes_lower_leg" in definition.get("tags", []):
					var skin := Toon.material(str(legacy.skin))
					for leg in ["LegL", "LegR"]:
						var calf := Toon.ellipsoid(avatar.get_node(leg), Vector3(0, -.49, 0), Vector3(.063, .274, .069), skin, "Calf")
						calf.scale.x *= BodyFit.leg_factor(shape)
			else:
				_hide_matching(avatar.get_node("Body"),["TailoredTop","Hem","Badge","Collar","Button","ChestPocket","CoatPocket","KangarooPocket","Hood","ClothingDetail","BowTie"])
				for arm in ["Body/ArmL","Body/ArmR"]:_hide_matching(avatar.get_node(arm),["Sleeve","Cuff"])
				if "short_sleeve" in definition.get("tags", []):
					var skin := Toon.material(str(legacy.skin))
					for path in ["Body/ArmL", "Body/ArmR"]:
						var arm := avatar.get_node(path)
						_hide_matching(arm, ["Forearm"])
						var forearm := Toon.ellipsoid(arm, Vector3(0, -.288, 0), Vector3(.060, .184, .063), skin, "VisibleForearm")
						forearm.scale.x *= BodyFit.arm_factor(shape)
			instance.free()
		if "hair_covering" in definition.get("tags",[]):
			for child in avatar.get_node("Body/Head").get_children():
				if child.name == "Hair" or child.get_meta(FacesHair.CATEGORY_META, "") == "hair":
					child.hide()
	BodyDeformation.finish(avatar)
	if live:
		for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
			var part := str(mesh.get_meta("toon_part", ""))
			var material := mesh.material_override as StandardMaterial3D
			if material == null:
				continue
			if part == "InnerEar":
				_add_color(colors, "skin_shade", material)
			elif part in ["Face", "Ear", "Nose", "Neck", "Forearm", "VisibleForearm", "Hand", "Thumb", "Calf", "SandalFoot", "SandalAnkle"] and material.albedo_color.is_equal_approx(Color(str(legacy.skin))):
				_add_color(colors, "skin", material)
		avatar.set_meta("preview_colors", colors)
	return avatar

static func _add_color(colors: Dictionary, key: String, material: StandardMaterial3D) -> void:
	if not colors.has(key):
		colors[key] = []
	if material not in colors[key]:
		colors[key].append(material)

static func _bind_colors(root: Node3D, definition: Dictionary, colors: Dictionary) -> void:
	var region_keys := {}
	match str(definition.category):
		"faces", "hair", "facial_hair":
			region_keys = {"hair":"color", "hair_highlight":"highlight", "hair_tip":"tip_color", "iris":"eye_color", "brow":"eyebrow_color", "lip":"lip_color", "skin_detail":"skin"}
		_:
			var keys := {"primary_regions":"primary_color", "secondary_regions":"secondary_color", "detail_regions":"detail_color", "accent_regions":"accent_color", "metal_regions":"metal_color"}
			if definition.category == "shoes":
				keys = {"primary_regions":"base_color", "secondary_regions":"accent_color", "sole_regions":"sole_color"}
			for region_group in keys:
				for region in definition.get("materials", {}).get(region_group, []):
					region_keys[region] = keys[region_group]
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			var source: Material = mesh.mesh.surface_get_material(surface)
			if material == null or source == null or not region_keys.has(source.resource_name):
				continue
			var key: String = region_keys[source.resource_name]
			_add_color(colors, key if key == "skin" else "%s/%s" % [definition.id, key], material)

static func update_preview_color(avatar: Node3D, key: String, value: String) -> bool:
	if not avatar.has_meta("preview_colors") or not Color.html_is_valid(value):
		return false
	var color := Color(value)
	var colors: Dictionary = avatar.get_meta("preview_colors")
	for material in colors.get(key, []):
		material.albedo_color = color
	if key == "skin":
		for material in colors.get("skin_shade", []):
			material.albedo_color = color.darkened(.18)
	return true

static func save_glb(state: Dictionary,catalog: Dictionary,path: String) -> Error:
	var model := render_avatar(state,catalog)
	_remove_hidden_meshes(model)
	var player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null:
		var animation_root := player.get_node(player.root_node)
		for key in player.get_animation_list():
			var animation := player.get_animation(key)
			for index in range(animation.get_track_count() - 1, -1, -1):
				var path_to_node := NodePath(animation.track_get_path(index).get_concatenated_names())
				if not animation_root.has_node(path_to_node):
					animation.remove_track(index)
	var document := GLTFDocument.new(); var gltf_state := GLTFState.new()
	var error := document.append_from_scene(model,gltf_state)
	if error==OK: error=document.write_to_filesystem(gltf_state,path)
	model.free()
	return error

static func _remove_hidden_meshes(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D and not child.visible:
			parent.remove_child(child)
			child.free()
		else:
			_remove_hidden_meshes(child)

static func _hide_matching(parent: Node,prefixes: Array) -> void:
	for child in parent.get_children():
		var label := str(child.get_meta("toon_part", ""))
		for prefix in prefixes:
			if label.begins_with(prefix) and child is GeometryInstance3D:child.hide()
