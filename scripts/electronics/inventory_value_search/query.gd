extends RefCounted
## Read-only projection of master stock. Values and family names come from the
## shared component_values descriptor; this module never parses units or types.
const Values = preload("res://scripts/electronics/component_values/values.gd")

static func search_owned(profile: Dictionary, catalog: Dictionary, family: String, raw_target: String, reserved: Dictionary = {}, kit_limits: Dictionary = {}) -> Dictionary:
	var descriptors := {}
	var unit := ""
	for type_id in catalog:
		var entry: Dictionary = catalog[type_id]
		if str(entry.get("kind", "")) != family:continue
		var field: Dictionary = Values.fields(entry).get("value", {})
		if field.is_empty():continue
		var value: Variant = entry.get("value")
		if not (value is int or value is float) or not is_finite(float(value)):continue
		unit = str(field.unit)
		descriptors[type_id] = {"family": family, "value": float(value), "unit": unit,
			"label": Values.format_value(float(value), unit)}
	var target: Variant = null
	if not raw_target.strip_edges().is_empty():
		var parsed: Dictionary = Values.parse(raw_target, unit)
		if not parsed.ok:return {"rows": [], "message": "", "error": str(parsed.error)}
		target = parsed.value
	return search(profile, catalog, descriptors, family, target, reserved, kit_limits)

static func search(profile: Dictionary, catalog: Dictionary, descriptors: Dictionary, family: String, target: Variant = null, reserved: Dictionary = {}, kit_limits: Dictionary = {}) -> Dictionary:
	var result := {"rows": [], "message": "", "error": ""}
	if family.is_empty():result.error = "Choose a component family";return result
	if target != null and (not (target is int or target is float) or not is_finite(float(target))):
		result.error = "Enter a finite component value";return result
	if not profile.get("inventory", {}) is Dictionary or not profile.get("component_instances", {}) is Dictionary:
		result.error = "Inventory is unavailable";return result
	var stock: Dictionary = profile.get("inventory", {})
	var instances: Dictionary = profile.get("component_instances", {})
	var held_counts: Dictionary = reserved.get("counts", {}) if reserved.get("counts", {}) is Dictionary else {}
	var held_ids: Array = reserved.get("instance_ids", []) if reserved.get("instance_ids", []) is Array else []
	var by_type := {}
	for instance_id in instances:
		var item: Variant = instances[instance_id]
		if not item is Dictionary:continue
		var type_id := str(item.get("type", ""))
		by_type[type_id] = int(by_type.get(type_id, 0)) + 1
	var ordinal := 0
	for type_id in catalog:
		if not descriptors.has(type_id):continue
		var descriptor: Variant = descriptors[type_id]
		if not descriptor is Dictionary or str(descriptor.get("family", "")) != family:continue
		var value: Variant = descriptor.get("value")
		if not (value is int or value is float) or not is_finite(float(value)):continue
		var owned := maxi(0, int(stock.get(type_id, 0)))
		var kit_count := int(kit_limits.get(type_id, 0)) if not kit_limits.is_empty() else owned
		var permitted := mini(owned, maxi(0, kit_count))
		var held := maxi(0, int(held_counts.get(type_id, 0)))
		var held_named := 0
		var named_visible := 0
		var ids: Array = instances.keys()
		ids.sort()
		for instance_id in ids:
			var item: Variant = instances[instance_id]
			if not item is Dictionary or str(item.get("type", "")) != str(type_id):continue
			var unavailable: bool = instance_id in held_ids
			if unavailable:held_named += 1
			var available := 0 if unavailable else 1
			if available > 0 and named_visible < permitted:
				var measured: Dictionary = descriptor
				var runtime: Variant = item.get("component_runtime", {})
				var root := str(item.get("root", ""))
				if runtime is Dictionary and runtime.has(root) and preload("res://scripts/physical_resistors.gd").valid(runtime[root]):
					measured = descriptor.duplicate(true)
					measured.value = float(runtime[root].actual)
					measured.label = Values.format_value(float(measured.value),str(descriptor.get("unit", ""))) + " measured"
				result.rows.append(_row(str(type_id), str(instance_id), available, catalog[type_id], measured, float(target) if target != null else null, ordinal))
				ordinal += 1;named_visible += 1
		var generic := maxi(0, permitted - int(by_type.get(type_id, 0)) - maxi(0, held - held_named))
		if generic > 0:
			result.rows.append(_row(str(type_id), "", generic, catalog[type_id], descriptor, float(target) if target != null else null, ordinal))
			ordinal += 1
	if target != null:result.rows.sort_custom(_closer)
	if result.rows.is_empty():result.message = "No available owned %s components" % family
	return result

static func _row(type_id: String, instance_id: String, quantity: int, catalog_entry: Dictionary, descriptor: Dictionary, target: Variant, ordinal: int) -> Dictionary:
	var value := float(descriptor.value)
	var distance := absf(value - float(target)) if target != null else 0.0
	return {"type": type_id, "instance_id": instance_id, "quantity": quantity,
		"family": str(descriptor.family), "value": value, "unit": str(descriptor.get("unit", "")),
		"value_label": str(descriptor.get("label", str(value) + " " + str(descriptor.get("unit", "")))),
		"name": str(catalog_entry.get("name", type_id)), "rating": str(catalog_entry.get("rating", "")),
		"rarity": str(catalog_entry.get("rarity", "Common")), "distance": distance, "ordinal": ordinal}

static func _closer(a: Dictionary, b: Dictionary) -> bool:
	if float(a.distance) != float(b.distance):return float(a.distance) < float(b.distance)
	return int(a.ordinal) < int(b.ordinal)
