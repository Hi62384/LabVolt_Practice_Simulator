extends SceneTree
const Adapter = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Catalog = preload("res://scripts/avatar_cosmetics/core/catalog.gd")

class FixtureProfile extends RefCounted:
	var data: Dictionary
	var authority_submit := Callable()
	var fail_save := false
	func save() -> Error:
		return ERR_CANT_CREATE if fail_save else OK

var checks := 0
var failures := 0
var catalog := {
	"hair.short": {"id":"hair.short", "slot":"hair", "starter":true, "price":0, "parameters":{}},
	"top.work": {"id":"top.work", "slot":"top_inner", "starter":true, "price":0, "parameters":{}},
	"head.helmet": {"id":"head.helmet", "slot":"head", "starter":false, "price":25, "parameters":{"visor":{"type":"bool", "default":false}}},
}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func resolver(_catalog: Dictionary, state: Dictionary, owned: Array) -> Dictionary:
	var entry: Dictionary = state.equipped.get("head", {})
	if not entry.is_empty() and entry.id not in owned:
		return {"state":state, "errors":["unowned"]}
	if not entry.get("parameters", {}) is Dictionary or entry.get("parameters", {}).has("bad"):
		return {"state":state, "errors":["bad parameter"]}
	return {"state":state, "errors":[]}

func base_profile() -> Dictionary:
	return {"schema":1, "dollars":100, "inventory":{"r1000":8}, "unrelated":{"course":7}}

func sanitize_fixture_body(raw: Dictionary) -> Dictionary:
	var result := {"height":clampf(float(raw.get("height", 1.0)), .65, 1.4), "width":clampf(float(raw.get("width", 1.0)), .65, 1.4)}
	result.build = raw.get("build", "average"); result.skin = raw.get("skin", "deb08c")
	return result

func real_catalog() -> Dictionary:
	var definitions: Array = []
	for category in ["footwear", "clothing", "accessories", "faces_hair"]:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cosmetics/" + category + "/catalog.json"))
		if value is Dictionary and value.get("items") is Array: definitions.append_array(value.items)
	return Catalog.collect(definitions)

func _initialize() -> void:
	var adapter := Adapter.new(catalog, resolver, sanitize_fixture_body)
	adapter.is_authority = func(): return true
	var legacy := {"name":"Original", "hair":"old_hair", "custom":{"keep":true}}
	var migrated: Dictionary = adapter.migrate(base_profile(), legacy)
	check(migrated.owned_cosmetics == ["hair.short", "top.work"], "missing starter items granted")
	check(migrated.legacy_character == legacy and migrated.unrelated.course == 7 and migrated.dollars == 100, "legacy and unrelated profile fields preserved")
	check(adapter.migrate(migrated, {"name":"replacement"}) == migrated, "migration is idempotent and never overwrites legacy snapshot")

	var old := base_profile(); old.cosmetics = ["copper_hat", "head.helmet"]; old.owned_cosmetics = ["event.old"]
	var old_migrated: Dictionary = adapter.migrate(old)
	check(old_migrated.cosmetics == old.cosmetics and old_migrated.owned_cosmetics == ["event.old", "copper_hat", "head.helmet", "hair.short", "top.work"], "legacy cosmetics remain owned without data loss")

	var purchased := adapter.apply_authoritative(base_profile(), {"op":"purchase", "id":"head.helmet"})
	check(purchased.ok and purchased.profile.dollars == 100 and "head.helmet" in purchased.profile.owned_cosmetics, "temporary unlimited purchase preserves stored balance while granting ownership")
	var duplicate := adapter.apply_authoritative(purchased.profile, {"op":"purchase", "id":"head.helmet"})
	check(not duplicate.ok and duplicate.error == "Already owned" and purchased.profile.dollars == 100, "duplicate permanent purchase rejected without debit")
	check(not adapter.apply_authoritative(base_profile(), {"op":"purchase", "id":"missing"}).ok, "unknown ID rejected")
	check(not adapter.apply_authoritative(base_profile(), {"op":"equip", "id":"head.helmet", "parameters":{}}).ok, "unowned equip rejected")
	var equipped := adapter.apply_authoritative(purchased.profile, {"op":"equip", "id":"head.helmet", "parameters":{"bad":false}})
	check(not equipped.ok, "malformed item parameter rejected by shared resolver")
	var equipped_ok := adapter.apply_authoritative(purchased.profile, {"op":"equip", "id":"head.helmet", "parameters":{"visor":true}})
	check(equipped_ok.ok and adapter.equipment(equipped_ok.profile).equipped.head.id == "head.helmet" and adapter.item_properties(equipped_ok.profile, "head.helmet").visor, "shared equipment and item properties exposed")
	var body_only := adapter.apply_authoritative(equipped_ok.profile, {"op":"body", "body":{"height":.4, "width":1.8, "build":"muscular", "skin":"AABBCC"}})
	check(body_only.ok and body_only.profile.avatar_cosmetics.body.height == .65 and body_only.profile.avatar_cosmetics.body.width == 1.4, "body-only edit uses current 0.65-1.4 core-compatible bounds")
	var partial_body := adapter.apply_authoritative(body_only.profile, {"op":"body", "body":{"height":1.1}})
	check(partial_body.ok and partial_body.profile.avatar_cosmetics.body.height == 1.1 and partial_body.profile.avatar_cosmetics.body.width == 1.4 and partial_body.profile.avatar_cosmetics.body.build == "muscular", "partial body edit preserves unspecified body values")
	check(not adapter.apply_authoritative(equipped_ok.profile, {"op":"body", "body":{"height":"wide"}}).ok, "type-invalid body rejected")
	var unequipped := adapter.apply_authoritative(equipped_ok.profile, {"op":"unequip", "slot":"head"})
	check(unequipped.ok and not unequipped.profile.avatar_cosmetics.equipped.has("head"), "optional slot unequips through resolver")
	var required := Adapter.new(catalog, resolver, sanitize_fixture_body, ["hair"]); required.is_authority = func(): return true
	check(not required.apply_authoritative(migrated, {"op":"unequip", "slot":"hair"}).ok, "required slot cannot be emptied")
	var before_mixed: Dictionary = equipped_ok.profile.duplicate(true)
	var mixed := adapter.apply_authoritative(equipped_ok.profile, {"op":"edit", "changes":[{"op":"body", "body":{"height":1.2}}, {"op":"equip", "id":"missing", "parameters":{}}]})
	check(not mixed.ok and equipped_ok.profile == before_mixed, "mixed editor transaction rolls back every partial change")
	var mixed_ok := adapter.apply_authoritative(equipped_ok.profile, {"op":"edit", "changes":[{"op":"body", "body":{"height":1.2}}, {"op":"unequip", "slot":"head"}]})
	check(mixed_ok.ok and mixed_ok.profile.avatar_cosmetics.body.height == 1.2 and not mixed_ok.profile.avatar_cosmetics.equipped.has("head"), "atomic multi-change editor intent commits one resolved state")

	var denied := Adapter.new(catalog, resolver, sanitize_fixture_body); denied.is_authority = func(): return false
	check(not denied.apply_authoritative(base_profile(), {"op":"unlock", "id":"head.helmet", "source":"course:x"}).ok, "non-authority intent rejected")
	check(not adapter.apply_authoritative(base_profile(), {"op":"unlock", "id":"head.helmet", "source":""}).ok, "malformed unlock source rejected")

	var disk := FixtureProfile.new(); disk.data = base_profile()
	var saved := adapter.commit_local(disk, {"op":"purchase", "id":"head.helmet"})
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(disk.data))
	check(saved.ok and roundtrip is Dictionary and roundtrip.dollars == 100 and "head.helmet" in roundtrip.owned_cosmetics, "JSON save roundtrip retains ownership and stored balance")
	var failing := FixtureProfile.new(); failing.data = base_profile(); failing.fail_save = true
	check(not adapter.commit_local(failing, {"op":"purchase", "id":"head.helmet"}).ok and failing.data == base_profile(), "failed save rolls back balance and ownership")
	var failing_edit := FixtureProfile.new(); failing_edit.data = equipped_ok.profile.duplicate(true); failing_edit.fail_save = true
	var original_edit: Dictionary = failing_edit.data.duplicate(true)
	check(not adapter.commit_local(failing_edit, {"op":"edit", "changes":[{"op":"body", "body":{"height":1.3}}, {"op":"unequip", "slot":"head"}]}).ok and failing_edit.data == original_edit, "failed editor save restores body and equipment together")
	var online := FixtureProfile.new(); online.data = base_profile(); online.authority_submit = func(): pass
	check(not adapter.commit_local(online, {"op":"purchase", "id":"head.helmet"}).ok and online.data == base_profile(), "online mirror cannot bypass ledger purchase")
	var collected := real_catalog()
	if not collected.errors.is_empty(): printerr("CATALOG VALIDATION ERRORS: ", JSON.stringify(collected.errors))
	if collected.items.size() != 41: printerr("CATALOG VALIDATION COUNT: ", collected.items.size())
	check(collected.errors.is_empty() and collected.items.size() == 41, "actual footwear, clothing, accessory, face and hair catalogs validate")
	var actual := Adapter.new(collected.items, Core.resolve, Core.sanitize_body); actual.is_authority = func(): return true
	var actual_profile := actual.migrate(base_profile())
	var actual_body := actual.apply_authoritative(actual_profile, {"op":"body", "body":{"height":.65, "width":1.4, "skin":"deb08c"}})
	check(actual_body.ok and actual_body.profile.avatar_cosmetics.body.height == .65 and actual_body.profile.avatar_cosmetics.body.width == 1.4, "adapter callable seam accepts real AvatarCore APIs and catalog")

	print("AVATAR_PERSISTENCE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
