extends RefCounted
## Pure selection seam. Each stable character ID owns its existing profile file;
## no balance, ownership or appearance is copied between IDs.
var adapter: RefCounted
var is_authority: Callable

func _init(profile_adapter: RefCounted) -> void:
	adapter = profile_adapter

func hydrate(character_id: String, profile: Dictionary, legacy: Variant = null) -> Dictionary:
	if not _valid_id(character_id) or not is_authority.is_valid() or is_authority.call() != true:
		return {"ok": false, "error": "Invalid character authority"}
	var migrated: Dictionary = adapter.migrate(profile, legacy)
	var raw: Dictionary = adapter.equipment(migrated)
	var resolved: Variant = adapter.resolve_equipment.call(adapter.catalog, raw, adapter.owned_ids(migrated)) if adapter.resolve_equipment.is_valid() else {}
	if not resolved is Dictionary or not resolved.get("state") is Dictionary:
		return {"ok": false, "error": "Appearance resolver unavailable"}
	# Preserve unknown saved IDs verbatim for later catalog restoration. Consumers
	# receive only the safe resolved appearance, never a cross-character fallback.
	return {"ok": true, "character_id": character_id, "profile": migrated, "appearance": resolved.state, "errors": resolved.get("errors", [])}

func switch_selected(current_id: String, target_id: String, profiles: Dictionary, legacy_by_id: Dictionary = {}) -> Dictionary:
	if not _valid_id(target_id) or not profiles.has(target_id) or not profiles[target_id] is Dictionary:
		return {"ok": false, "error": "Character profile unavailable", "selected": current_id}
	var result := hydrate(target_id, profiles[target_id], legacy_by_id.get(target_id))
	if not result.ok:
		result.selected = current_id
		return result
	result.selected = target_id
	return result

func commit_selected(character_id: String, profile_object: RefCounted, intent: Dictionary, legacy: Variant = null) -> Dictionary:
	if not _valid_id(character_id) or profile_object == null:
		return {"ok": false, "error": "Character profile unavailable"}
	return adapter.commit_local(profile_object, intent, legacy)

static func _valid_id(value: String) -> bool:
	return not value.is_empty() and value.length() <= 128 and not value.contains("/") and not value.contains("\\") and not value.contains("..")
