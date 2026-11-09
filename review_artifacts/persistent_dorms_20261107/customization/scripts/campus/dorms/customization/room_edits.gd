class_name DormRoomEdits
extends RefCounted

const Rules = preload("res://scripts/campus/dorms/customization/placement_rules.gd")
const STYLE_CHOICES := {
	"wall":["classic", "sage", "sand", "slate"],
	"floor":["tile", "warm_tile", "wood"],
	"bedding":["teal", "blue", "cream", "rust"],
	"furniture":["oak", "birch", "painted"]
}
const MAX_INTENT_BYTES := 2048

## Host service calls this after deriving the stable owner from the authenticated
## ledger binding. `eligible` must check actual catalog + owned inventory, unique
## item reservation, display definition, and surface attachment. A client may not
## supply the owner identity or room state.
static func apply(current: Dictionary, intent: Dictionary, side: String, eligible: Callable) -> Dictionary:
	if var_to_bytes(intent).size() > MAX_INTENT_BYTES: return _error("intent_too_large")
	if not eligible.is_valid(): return _error("catalog_unavailable")
	var next: Dictionary = current.duplicate(true)
	if not next.has("items"): next.items = []
	if not next.has("styles"): next.styles = {}
	if not next.items is Array or not next.styles is Dictionary: return _error("invalid_saved_room")
	var op := str(intent.get("op", ""))
	match op:
		"style":
			var category := str(intent.get("category", ""))
			var variant := str(intent.get("variant", ""))
			if not STYLE_CHOICES.has(category) or variant not in STYLE_CHOICES[category]: return _error("invalid_style")
			if not bool(eligible.call({"op":"style", "category":category, "variant":variant}, next)): return _error("style_not_owned")
			next.styles[category] = variant
		"place", "move":
			var item: Dictionary = intent.get("item", {}) if intent.get("item", {}) is Dictionary else {}
			var id := str(item.get("id", ""))
			if id.is_empty(): return _error("invalid_item")
			var index := _index(next.items, id)
			if op == "place" and index >= 0: return _error("already_placed")
			if op == "move" and index < 0: return _error("missing_item")
			if op == "move" and str(next.items[index].get("kind", "")) != str(item.get("kind", "")): return _error("item_kind_changed")
			if not bool(eligible.call({"op":op, "item":item}, next)): return _error("item_not_owned_or_ineligible")
			if index >= 0: next.items[index] = item.duplicate(true)
			else: next.items.append(item.duplicate(true))
		"pickup":
			var id := str(intent.get("id", ""))
			var index := _index(next.items, id)
			if index < 0: return _error("missing_item")
			if not bool(eligible.call({"op":"pickup", "item":next.items[index]}, next)): return _error("pickup_rejected")
			next.items.remove_at(index)
		_: return _error("unsupported_edit")
	var geometry_error := Rules.validate(next.items, side)
	if not geometry_error.is_empty(): return _error(geometry_error)
	return {"ok":true, "state":next}

static func _index(items: Array, id: String) -> int:
	for index in items.size():
		if items[index] is Dictionary and str(items[index].get("id", "")) == id: return index
	return -1

static func _error(message: String) -> Dictionary:
	return {"ok":false, "error":message}
