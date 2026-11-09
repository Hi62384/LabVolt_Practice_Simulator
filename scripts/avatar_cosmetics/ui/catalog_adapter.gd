class_name CosmeticCatalogAdapter
extends RefCounted

const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")

const DISPLAY_CATEGORIES := ["body", "faces", "hair", "facial_hair", "tops", "bottoms", "shoes", "accessories"]
const COLLECTIBLE_CATEGORIES := ["faces", "hair", "facial_hair", "tops", "bottoms", "shoes", "accessories"]

static func body_schema() -> Dictionary:
	var schema := {}
	for key in Core.BODY_FIELDS:
		schema[key] = {"type": "float", "default": 1.0, "min": Core.BODY_MIN, "max": Core.BODY_MAX}
	schema.build = {"type": "enum", "default": "average", "values": ["slim", "average", "heavy", "muscular"]}
	schema.skin = {"type": "color", "default": "deb08c"}
	return schema

static func category_items(catalog: Dictionary, owned: Array, category: String) -> Array:
	if category == "body" or category not in COLLECTIBLE_CATEGORIES:
		return []
	var rows: Array = []
	for raw_id in owned:
		var item_id := str(raw_id)
		var definition: Dictionary = catalog.get(item_id, {})
		if not definition.is_empty() and not definition.get("legacy", false) and str(definition.get("category", "")) == category:
			rows.append(definition)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if category == "hair":
			return int(a.get("catalog_order", 0)) < int(b.get("catalog_order", 0))
		return str(a.get("name", a.get("id", ""))).naturalnocasecmp_to(str(b.get("name", b.get("id", "")))) < 0)
	return rows

static func supported_parameters(definition: Dictionary) -> Dictionary:
	var result := {}
	var schema: Variant = definition.get("parameters", {})
	if schema is not Dictionary:
		return result
	for raw_key in schema:
		var key := str(raw_key)
		var spec: Variant = schema[raw_key]
		if spec is not Dictionary:
			continue
		var kind := str(spec.get("type", ""))
		if kind in ["float", "int"] and spec.has("min") and spec.has("max") and spec.has("default"):
			result[key] = spec
		elif kind == "bool" and spec.has("default"):
			result[key] = spec
		elif kind == "color" and spec.has("default"):
			result[key] = spec
		elif kind == "enum" and spec.get("values", []) is Array and not spec.values.is_empty():
			result[key] = spec
	return result

static func equipped_slot_for(state: Dictionary, item_id: String) -> String:
	var equipped: Dictionary = state.get("equipped", {})
	for raw_slot in equipped:
		var entry: Variant = equipped[raw_slot]
		if entry is Dictionary and str(entry.get("id", "")) == item_id:
			return str(raw_slot)
	return ""

static func toggle_selection(state: Dictionary, definition: Dictionary, allow_unequip := true) -> Dictionary:
	var draft := state.duplicate(true)
	if not draft.has("version"):
		draft.version = 1
	if not draft.get("equipped", {}) is Dictionary:
		draft.equipped = {}
	var item_id := str(definition.get("id", ""))
	var slot := str(definition.get("slot", ""))
	if item_id.is_empty() or slot.is_empty():
		return draft
	var current: Dictionary = draft.equipped.get(slot, {})
	if str(current.get("id", "")) == item_id:
		if allow_unequip:
			draft.equipped.erase(slot)
	else:
		var parameters := {}
		for key in supported_parameters(definition):
			parameters[key] = definition.parameters[key].get("default")
		Core.equip(draft, definition, parameters)
	return draft

