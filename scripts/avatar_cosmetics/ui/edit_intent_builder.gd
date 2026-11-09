class_name CosmeticEditIntentBuilder
extends RefCounted

# Converts one accepted editor draft into the persistence adapter's atomic edit
# shape. It does not authorize, save, resolve, or mutate either input.
static func build(before: Dictionary, after: Dictionary) -> Dictionary:
	var changes: Array = []
	var before_body: Dictionary = before.get("body", {}) if before.get("body", {}) is Dictionary else {}
	var after_body: Dictionary = after.get("body", {}) if after.get("body", {}) is Dictionary else {}
	if before_body != after_body:
		changes.append({"op": "body", "body": after_body.duplicate(true)})
	var old_equipped: Dictionary = before.get("equipped", {}) if before.get("equipped", {}) is Dictionary else {}
	var new_equipped: Dictionary = after.get("equipped", {}) if after.get("equipped", {}) is Dictionary else {}
	var slots: Array = old_equipped.keys()
	for slot in new_equipped:
		if slot not in slots:
			slots.append(slot)
	slots.sort()
	for raw_slot in slots:
		var slot := str(raw_slot)
		var old_entry: Variant = old_equipped.get(slot)
		var new_entry: Variant = new_equipped.get(slot)
		if old_entry == new_entry:
			continue
		if not new_entry is Dictionary:
			changes.append({"op": "unequip", "slot": slot})
			continue
		changes.append({
			"op": "equip",
			"id": str(new_entry.get("id", "")),
			"parameters": new_entry.get("parameters", {}).duplicate(true) if new_entry.get("parameters", {}) is Dictionary else {},
		})
	return {"op": "edit", "changes": changes}

