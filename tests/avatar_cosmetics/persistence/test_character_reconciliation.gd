extends SceneTree
const Adapter = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
const Reconcile = preload("res://scripts/avatar_cosmetics/persistence/character_reconciliation.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Catalog = preload("res://scripts/avatar_cosmetics/core/catalog.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL ", label)
func resolve(_catalog: Dictionary, state: Dictionary, owned: Array) -> Dictionary:
	var safe := state.duplicate(true); safe.equipped = {}
	var errors := []
	for slot in state.get("equipped", {}):
		var entry = state.equipped[slot]
		if entry is Dictionary and entry.get("id") in owned and _catalog.has(entry.id): safe.equipped[slot] = entry
		else: errors.append("Unavailable item")
	return {"state":safe,"errors":errors}
func _initialize() -> void:
	var adapter := Adapter.new({"hair.a":{"starter":true,"slot":"hair","price":0,"parameters":{}}}, resolve)
	adapter.is_authority = func(): return true
	var bridge := Reconcile.new(adapter); bridge.is_authority = func(): return true
	var a := {"dollars":31,"cosmetics":["old.a"],"avatar_cosmetics":{"version":1,"body":{"height":1.2},"equipped":{"hair":{"id":"deleted.hair","parameters":{}}}}}
	var b := {"dollars":90,"avatar_cosmetics":{"version":1,"body":{"height":.8},"equipped":{}}}
	var profiles := {"character-A":a,"character-B":b}
	var one := bridge.switch_selected("", "character-A", profiles, {"character-A":{"name":"Old A"}})
	check(one.ok and one.appearance.body.height == 1.2 and one.appearance.equipped.is_empty() and one.profile.avatar_cosmetics.equipped.hair.id == "deleted.hair", "unknown catalog ID safely hidden but saved")
	check(one.profile.dollars == 31 and "old.a" in one.profile.owned_cosmetics and one.profile.legacy_character.name == "Old A", "legacy ownership and balance retained")
	check(adapter.migrate(one.profile) == one.profile, "starter migration idempotent")
	var two := bridge.switch_selected("character-A", "character-B", profiles)
	check(two.ok and two.appearance.body.height == .8 and two.profile.dollars == 90 and not two.profile.has("legacy_character"), "selection hydrates only target character")
	var missing := bridge.switch_selected("character-B", "missing", profiles)
	check(not missing.ok and missing.selected == "character-B", "failed switch preserves selection")
	check(profiles["character-A"] == a and profiles["character-B"] == b, "hydration does not mutate source profiles")
	bridge.is_authority = func(): return false
	check(not bridge.switch_selected("character-A", "character-B", profiles).ok, "unauthorized hydration denied")
	var definitions: Array = []
	for category in ["footwear", "clothing", "accessories", "faces_hair"]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cosmetics/" + category + "/catalog.json"))
		check(parsed is Dictionary and parsed.get("items") is Array, "real catalog JSON " + category)
		if parsed is Dictionary and parsed.get("items") is Array: definitions.append_array(parsed.items)
	var collected: Dictionary = Catalog.collect(definitions)
	if not collected.errors.is_empty(): printerr("CATALOG VALIDATION ERRORS: ", JSON.stringify(collected.errors))
	if collected.items.size() != 41: printerr("CATALOG VALIDATION COUNT: ", collected.items.size())
	check(collected.errors.is_empty() and collected.items.size() == 41, "41 unique real catalog definitions validate")
	var actual := Adapter.new(collected.items, Core.resolve, Core.sanitize_body); actual.is_authority = func(): return true
	var real_bridge := Reconcile.new(actual); real_bridge.is_authority = func(): return true
	var first: Dictionary = real_bridge.hydrate("character-A", {"dollars":31,"avatar_cosmetics":{"version":1,"body":{"height":1.3},"equipped":{}}}, {"name":"A"})
	var second: Dictionary = real_bridge.hydrate("character-B", {"dollars":90,"avatar_cosmetics":{"version":1,"body":{"height":.7},"equipped":{}}}, {"name":"B"})
	check(first.ok and second.ok and first.appearance.body.height == 1.3 and second.appearance.body.height == .7 and first.profile.dollars == 31 and second.profile.dollars == 90, "real core hydrates distinct characters without balance or body bleed")
	var expected_starters: Array = Core.starter_ids(collected.items)
	check(first.profile.owned_cosmetics.size() == expected_starters.size() and actual.migrate(first.profile) == first.profile, "real defaults granted once")
	var unknown: Dictionary = first.profile.duplicate(true)
	unknown.avatar_cosmetics.equipped.hair = {"id":"hair.deleted", "parameters":{}}
	var unavailable: Dictionary = real_bridge.hydrate("character-A", unknown)
	check(unavailable.ok and unavailable.appearance.equipped.is_empty() and unavailable.profile.avatar_cosmetics.equipped.hair.id == "hair.deleted", "removed catalog item remains saved but not rendered")
	var compact: Dictionary = Core.resolve(collected.items, first.appearance, first.profile.owned_cosmetics)
	check(compact.errors.is_empty() and var_to_bytes(compact.state).size() < 65536 and not compact.state.has("dollars") and not compact.state.has("owned_cosmetics"), "compact sanitized appearance fits replication bound without private economy")
	print("CHARACTER_RECONCILIATION failures=", failures)
	quit(1 if failures else 0)
