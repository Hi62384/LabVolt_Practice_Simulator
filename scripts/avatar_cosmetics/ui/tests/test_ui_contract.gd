extends SceneTree

const Adapter = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const Cache = preload("res://scripts/avatar_cosmetics/ui/thumbnail_cache.gd")
const CameraState = preload("res://scripts/avatar_cosmetics/ui/preview_camera_state.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Binding = preload("res://scripts/avatar_cosmetics/ui/ui_binding.gd")
const EditIntent = preload("res://scripts/avatar_cosmetics/ui/edit_intent_builder.gd")

var checks := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + message)
		quit(1)

func _init() -> void:
	var shoe := {"id": "shoes.test.runner", "name": "Runner", "category": "shoes", "slot": "footwear", "parameters": {
		"primary": {"type": "color", "default": "ffffff"},
		"variant": {"type": "enum", "default": "mesh", "values": ["mesh", "leather"]},
		"ignored": {"type": "mystery", "default": 12},
	}}
	var hair := {"id": "hair.test.crop", "name": "Crop", "category": "hair", "slot": "hair", "parameters": {}}
	var catalog := {shoe.id: shoe, hair.id: hair}
	var owned := [hair.id, "missing.id", shoe.id]
	var shoes := Adapter.category_items(catalog, owned, "shoes")
	expect(shoes.size() == 1 and shoes[0].id == shoe.id, "owned category filtering")
	expect(Adapter.category_items(catalog, owned, "body").is_empty(), "body is not a collectible list")
	expect(Adapter.supported_parameters(shoe).keys() == ["primary", "variant"], "only supported schema controls")
	var body_schema := Adapter.body_schema()
	expect(body_schema.size() == Core.BODY_FIELDS.size() + 2, "body UI schema derives from every core body field")
	expect(body_schema.height.min == Core.BODY_MIN and body_schema.height.max == Core.BODY_MAX, "body UI range derives from core range")
	expect(is_equal_approx(Core.sanitize_body({"height": 0.66}).height, 0.66), "legitimate legacy body values are preserved")
	var state := {"version": 1, "body": {}, "equipped": {}}
	state = Adapter.toggle_selection(state, shoe)
	expect(state.equipped.footwear.id == shoe.id and state.equipped.footwear.parameters.primary == "ffffff", "selection equips defaults")
	state = Adapter.toggle_selection(state, shoe)
	expect(not state.equipped.has("footwear"), "second click unequips")
	var key_a := Cache.cache_key(shoe.id, {"b": 2, "a": 1}, {"height": 1.0})
	var key_b := Cache.cache_key(shoe.id, {"a": 1, "b": 2}, {"height": 1.0})
	expect(key_a == key_b, "cache keys ignore dictionary insertion order")
	expect(key_a != Cache.cache_key(shoe.id, {"a": 2, "b": 2}, {"height": 1.0}), "cache keys include parameters")
	var camera := CameraState.new()
	camera.orbit(Vector2(10, 0), 1000)
	expect(not camera.focus_category("shoes", 1200), "automatic focus yields to manual camera")
	expect(camera.focus_category("shoes", 3000) and camera.target.y < 0.2, "category focus resumes after ownership window")
	camera.pan(Vector2(10, 4), 4000)
	expect(camera.owns_camera(4001), "pan establishes manual camera ownership")
	var footwear_json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cosmetics/footwear/catalog.json"))
	expect(footwear_json is Dictionary and footwear_json.get("items", []) is Array and footwear_json.items.size() >= 6, "real footwear catalog fixture loads")
	var real_catalog := {}
	for definition in footwear_json.items:
		expect(Core.validate_definition(definition).is_empty(), "real footwear definition validates: " + str(definition.get("id", "")))
		real_catalog[definition.id] = definition
	var runner: Dictionary = real_catalog["shoes.velocity_runner"]
	var real_state := Adapter.toggle_selection({"version": 1, "body": {}, "equipped": {}}, runner)
	var resolved := Core.resolve(real_catalog, real_state, [runner.id])
	expect(resolved.errors.is_empty() and resolved.state.equipped.footwear.parameters.base_color == "3e5673", "real footwear equip routes through core validation")
	expect(Binding.commit_payload(resolved.state).avatar_cosmetics == resolved.state, "binding produces exact profile state payload")
	var before_edit: Dictionary = resolved.state.duplicate(true)
	var after_edit: Dictionary = resolved.state.duplicate(true)
	after_edit.body.height = 0.66
	after_edit.equipped.erase("footwear")
	var edit := EditIntent.build(before_edit, after_edit)
	expect(edit.op == "edit" and edit.changes.size() == 2, "atomic edit groups body and unequip")
	expect(edit.changes[0].op == "body" and edit.changes[0].body.height == 0.66, "body intent preserves legitimate legacy-range value")
	expect(edit.changes[1] == {"op": "unequip", "slot": "footwear"}, "unequip intent uses persistence slot shape")
	var seen_categories := {}
	for path in ["res://assets/cosmetics/footwear/catalog.json", "res://assets/cosmetics/clothing/catalog.json", "res://assets/cosmetics/faces_hair/catalog.json", "res://assets/cosmetics/accessories/catalog.json"]:
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		expect(document is Dictionary and document.get("items", []) is Array, "real catalog document loads: " + path)
		for definition in document.items:
			expect(Core.validate_definition(definition).is_empty(), "real definition validates: " + str(definition.get("id", "")))
			seen_categories[str(definition.category)] = true
	for category in Adapter.COLLECTIBLE_CATEGORIES:
		expect(seen_categories.has(category), "real catalog covers UI category: " + category)
	var cache := Cache.new()
	root.add_child(cache)
	var abandoned_key := cache.request_thumbnail(runner.id, {}, {}, "res://missing-development-thumbnail.png")
	cache.release(abandoned_key)
	expect(cache._queue.is_empty() and not cache._references.has(abandoned_key), "abandoned thumbnail requests leave no queued work")
	print("PASS avatar cosmetic UI source contract: ", checks, " checks")
	quit()

