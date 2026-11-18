extends RefCounted
## Persistence/economy adapter for avatar collectibles v1.
##
## `apply_authoritative()` is deliberately persistence-agnostic: the inventory
## ledger must call it on its transaction-local ElectronicsProfile copy, then
## commit that copy with the ledger's existing receipt + store transaction.
## `commit_local()` is the offline equivalent and uses ElectronicsProfile.save().

const VERSION := 1
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const MAX_ITEMS := 4096
const MAX_BYTES := 1048576
const VALID_OPS := ["equip", "unequip", "body", "edit", "unlock", "purchase"]
const BODY_FIELDS := ["height", "width", "head", "head_width", "head_height", "neck_length", "neck_width", "shoulders", "torso_length", "torso_width", "waist", "hips", "arm_length", "arm_width", "hands", "leg_length", "leg_width", "feet"]
const BODY_KEYS := ["height", "width", "head", "head_width", "head_height", "neck_length", "neck_width", "shoulders", "torso_length", "torso_width", "waist", "hips", "arm_length", "arm_width", "hands", "leg_length", "leg_width", "feet", "build", "skin"]

var catalog: Dictionary
var resolve_equipment: Callable
var sanitize_body: Callable
var is_authority: Callable
var required_slots: Array
var seed_equipment: Callable

func _init(definitions: Dictionary = {}, resolver: Callable = Callable(), body_sanitizer: Callable = Callable(), required: Array = []) -> void:
	catalog = definitions
	resolve_equipment = resolver
	sanitize_body = body_sanitizer
	required_slots = required.duplicate()

func migrate(profile: Dictionary, legacy_character: Variant = null) -> Dictionary:
	var next := profile.duplicate(true)
	var owned: Array = []
	var seen := {}
	for source in [next.get("owned_cosmetics", []), next.get("cosmetics", [])]:
		if not source is Array:
			continue
		for value in source:
			if value is String and not value.is_empty() and value.length() <= 128 and not seen.has(value):
				seen[value] = true
				owned.append(value)
	for id in catalog:
		var definition: Variant = catalog[id]
		if definition is Dictionary and definition.get("starter", false) == true and not seen.has(id):
			seen[id] = true
			owned.append(id)
	next.owned_cosmetics = owned
	if not next.get("avatar_cosmetics") is Dictionary:
		next.avatar_cosmetics = {"version": VERSION, "body": {}, "equipped": {}}
	if not next.has("legacy_character") and legacy_character is Dictionary:
		next.legacy_character = legacy_character.duplicate(true)
	if seed_equipment.is_valid():
		var legacy: Variant = next.get("legacy_character", {})
		next.avatar_cosmetics = seed_equipment.call(catalog, next.avatar_cosmetics, owned, legacy if legacy is Dictionary else {})
	return next

func owned_ids(profile: Dictionary) -> Array:
	var result: Array = []
	for id in profile.get("owned_cosmetics", []):
		if id is String:
			result.append(id)
	return result

func equipment(profile: Dictionary) -> Dictionary:
	var value: Variant = profile.get("avatar_cosmetics", {})
	return value.duplicate(true) if value is Dictionary else {"version": VERSION, "body": {}, "equipped": {}}

func item_properties(profile: Dictionary, item_id: String) -> Dictionary:
	var state := equipment(profile)
	for entry in state.get("equipped", {}).values():
		if entry is Dictionary and entry.get("id", "") == item_id:
			return entry.get("parameters", {}).duplicate(true) if entry.get("parameters", {}) is Dictionary else {}
	return {}

func apply_authoritative(profile: Dictionary, intent: Variant, legacy_character: Variant = null) -> Dictionary:
	if not is_authority.is_valid() or is_authority.call() != true:
		return _failure("Authority required")
	if not intent is Dictionary or var_to_bytes(intent).size() > MAX_BYTES:
		return _failure("Malformed cosmetic intent")
	var op: Variant = intent.get("op")
	if not op is String or op not in VALID_OPS:
		return _failure("Malformed cosmetic intent")
	var next := migrate(profile, legacy_character)
	if next.owned_cosmetics.size() > MAX_ITEMS:
		return _failure("Cosmetic collection exceeds limit")
	var changed := _apply_one(next, intent)
	if not changed.ok:
		return changed
	next = changed.profile
	if var_to_bytes(next).size() > MAX_BYTES:
		return _failure("Profile exceeds persistence limit")
	return {"ok": true, "profile": next, "equipment": equipment(next), "owned": owned_ids(next)}

func _apply_one(profile: Dictionary, intent: Dictionary) -> Dictionary:
	var op: String = intent.op
	if op == "edit":
		if not intent.get("changes") is Array or intent.changes.is_empty() or intent.changes.size() > 64:
			return _failure("Invalid editor transaction")
		var edited := profile.duplicate(true)
		for change in intent.changes:
			if not change is Dictionary or change.get("op") not in ["equip", "unequip", "body"]:
				return _failure("Invalid editor transaction")
			var result := _apply_one(edited, change)
			if not result.ok:
				return result
			edited = result.profile
		return {"ok": true, "profile": edited}
	if op == "body":
		var raw: Variant = intent.get("body")
		if not raw is Dictionary or not sanitize_body.is_valid():
			return _failure("Body sanitizer unavailable")
		var body_error := _body_error(raw)
		if body_error != "":
			return _failure(body_error)
		var current_body: Variant = equipment(profile).get("body", {})
		var merged_body: Dictionary = current_body.duplicate(true) if current_body is Dictionary else {}
		merged_body.merge(raw, true)
		var body: Variant = sanitize_body.call(merged_body)
		if not body is Dictionary:
			return _failure("Body sanitizer failed")
		var draft := equipment(profile); draft.body = body.duplicate(true)
		return _resolve(profile, draft)
	if op == "unequip":
		var slot: Variant = intent.get("slot")
		if not slot is String or not _known_slot(slot):
			return _failure("Unknown cosmetic slot")
		if slot in required_slots:
			return _failure("Required cosmetic slot cannot be empty")
		var draft := equipment(profile)
		if not draft.get("equipped", {}) is Dictionary:
			return _failure("Invalid equipment state")
		draft.equipped.erase(slot)
		return _resolve(profile, draft)
	var item_id: Variant = intent.get("id")
	if not item_id is String or item_id.is_empty() or item_id.length() > 128:
		return _failure("Malformed cosmetic intent")
	if not catalog.has(item_id) or not catalog[item_id] is Dictionary:
		return _failure("Unknown cosmetic")
	var definition: Dictionary = catalog[item_id]
	if op == "purchase":
		if item_id in profile.owned_cosmetics:
			return _failure("Already owned")
		var price: Variant = definition.get("price")
		var balance: Variant = profile.get("dollars")
		if not _whole_nonnegative(price, 1000000000) or not _whole_nonnegative(balance, 1000000000):
			return _failure("Invalid price or balance")
		var debit := preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(int(balance),int(price),true)
		if not debit.ok:return _failure(debit.error)
		var purchased := profile.duplicate(true)
		purchased.dollars = debit.next_balance
		purchased.owned_cosmetics.append(item_id)
		return {"ok": true, "profile": purchased}
	if op == "unlock":
		var source: Variant = intent.get("source")
		if not source is String or source.is_empty() or source.length() > 256:
			return _failure("Invalid unlock source")
		var unlocked := profile.duplicate(true)
		if item_id not in unlocked.owned_cosmetics:
			unlocked.owned_cosmetics.append(item_id)
		return {"ok": true, "profile": unlocked}
	if item_id not in profile.owned_cosmetics:
		return _failure("Cosmetic is not owned")
	var parameters: Variant = intent.get("parameters", {})
	if not parameters is Dictionary:
		return _failure("Invalid item parameters")
	var parameter_error := _parameter_error(definition, parameters)
	if parameter_error != "":
		return _failure(parameter_error)
	var draft := equipment(profile)
	var slot: Variant = definition.get("slot")
	if not slot is String or not _known_slot(slot):
		return _failure("Invalid cosmetic slot")
	if not draft.get("equipped", {}) is Dictionary:
		return _failure("Invalid equipment state")
	Core.equip(draft, definition, parameters)
	return _resolve(profile, draft)

func _resolve(profile: Dictionary, draft: Dictionary) -> Dictionary:
	if not resolve_equipment.is_valid():
		return _failure("Equipment resolver unavailable")
	if seed_equipment.is_valid():
		draft = seed_equipment.call(catalog, draft, profile.owned_cosmetics, {})
	var resolved: Variant = resolve_equipment.call(catalog, draft, profile.owned_cosmetics)
	if not resolved is Dictionary or not resolved.get("state") is Dictionary or not resolved.get("errors", []) is Array:
		return _failure("Equipment resolver failed")
	if not resolved.errors.is_empty():
		return _failure("Invalid equipment", resolved.errors)
	var next := profile.duplicate(true); next.avatar_cosmetics = resolved.state.duplicate(true)
	return {"ok": true, "profile": next}

func _known_slot(slot: String) -> bool:
	for definition in catalog.values():
		if definition is Dictionary and definition.get("slot") == slot:
			return true
	return false

static func _body_error(raw: Dictionary) -> String:
	for key in raw:
		if key not in BODY_KEYS:
			return "Unknown body property"
	for key in BODY_FIELDS:
		if raw.has(key) and not ((raw[key] is int or raw[key] is float) and is_finite(float(raw[key]))):
			return "Invalid body property"
	if raw.has("build") and (not raw.build is String or raw.build not in ["slim", "average", "heavy", "muscular"]):
		return "Invalid body build"
	if raw.has("skin") and (not raw.skin is String or raw.skin.length() != 6 or not raw.skin.is_valid_hex_number()):
		return "Invalid skin color"
	return ""

static func _parameter_error(definition: Dictionary, raw: Dictionary) -> String:
	var schema: Variant = definition.get("parameters")
	if not schema is Dictionary:
		return "Invalid cosmetic definition"
	for key in raw:
		if not schema.has(key):
			return "Unknown item parameter"
		var spec: Variant = schema[key]
		if not spec is Dictionary:
			return "Invalid cosmetic definition"
		var value: Variant = raw[key]
		match spec.get("type"):
			"float":
				if not (value is int or value is float) or not is_finite(float(value)): return "Invalid item parameter"
			"int":
				if not value is int: return "Invalid item parameter"
			"bool":
				if not value is bool: return "Invalid item parameter"
			"color":
				if not value is String or value.length() != 6 or not value.is_valid_hex_number(): return "Invalid item parameter"
			"enum":
				if not spec.get("values", []) is Array or value not in spec.get("values", []): return "Invalid item parameter"
			_: return "Invalid cosmetic definition"
	return ""

func commit_local(profile_object: RefCounted, intent: Variant, legacy_character: Variant = null) -> Dictionary:
	if profile_object == null or not profile_object.get("data") is Dictionary or not profile_object.has_method("save"):
		return _failure("Profile adapter unavailable")
	if profile_object.get("authority_submit") is Callable and profile_object.authority_submit.is_valid():
		return _failure("Online profiles require the host ledger")
	var before: Dictionary = profile_object.data.duplicate(true)
	var result := apply_authoritative(before, intent, legacy_character)
	if not result.ok:
		return result
	profile_object.data = result.profile
	if profile_object.save() != OK:
		profile_object.data = before
		return _failure("Save failed; cosmetic transaction rolled back")
	return result

static func _whole_nonnegative(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0.0 and float(value) <= maximum

static func _failure(message: String, details: Array = []) -> Dictionary:
	return {"ok": false, "error": message, "details": details.duplicate(true)}
