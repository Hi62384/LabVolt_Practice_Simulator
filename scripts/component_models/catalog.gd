extends RefCounted
## Optional fragment. Caller explicitly merges this with the established catalog.
static func all() -> Dictionary:
	return preload("res://scripts/component_models/catalog_data.gd").ENTRIES.duplicate(true)
