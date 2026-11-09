class_name StudentAppearanceProvider
extends RefCounted
## Deterministic, read-only NPC appearance data. This never touches player profiles,
## ownership, inventory, or the scene tree.

const VERSION := 1
const DEFAULT_CACHE_LIMIT := 128
const CATALOG_PATHS := [
	"res://assets/cosmetics/footwear/catalog.json",
	"res://assets/cosmetics/clothing/catalog.json",
	"res://assets/cosmetics/accessories/catalog.json",
	"res://assets/cosmetics/faces_hair/catalog.json",
]
const SKINS := ["f3cbb1", "deb08c", "c78e64", "a86c49", "805037", "54382e"]
const HAIR_COLORS := ["241d29", "352b31", "5a3b2b", "704832", "9b744e", "2d3039"]
const EYE_COLORS := ["397a83", "4d7047", "6b4d35", "596a8a", "34343b"]
const TOP_COLORS := ["376676", "8f4f5b", "4d6b45", "6b5b91", "b06b3f", "d5d9d4"]
const ACCENT_COLORS := ["e5af3d", "79a9a1", "d98269", "b790c4", "e0d6b8"]
const BOTTOM_COLORS := ["293951", "303843", "54463d", "493b58", "31504e"]
const SHOE_COLORS := ["f3e9d6", "29303b", "62452f", "aeb8bf"]
const FACES := ["faces.friendly", "faces.serious", "faces.sleepy", "faces.bright", "faces.determined", "faces.goofy"]
const HAIR := ["hair.buzz", "hair.crop", "hair.bob", "hair.long_waves", "hair.ponytail", "hair.curly", "hair.bun"]
const FACIAL_HAIR := ["facial_hair.clean", "facial_hair.clean", "facial_hair.clean", "facial_hair.stubble", "facial_hair.short_beard", "facial_hair.goatee"]
const BOTTOMS := ["bottoms.indigo_straight_jeans", "bottoms.campus_work_shorts", "bottoms.harbour_pleated_skirt"]
const FOOTWEAR := ["shoes.velocity_runner", "shoes.beacon_hightop", "shoes.foundry_boot", "shoes.oxford", "shoes.trail_sandal"]

var cache_limit: int
var _state_cache := {}
var _lru: Array[int] = []
var _catalog := {}

func _init(max_cached_appearances := DEFAULT_CACHE_LIMIT) -> void:
	cache_limit = clampi(int(max_cached_appearances), 8, 512)

## Lifecycle hook for the crowd owner: call once when a stable student identity is
## created or received. Repeated calls are cached and never reroll per frame.
func appearance_for_student(identity: Variant, campus_seed := 0) -> Dictionary:
	var appearance_id := appearance_id_for(identity, campus_seed)
	if _state_cache.has(appearance_id):
		_touch(appearance_id)
		return (_state_cache[appearance_id] as Dictionary).duplicate(true)
	var state := _build_state(appearance_id)
	_state_cache[appearance_id] = state
	_touch(appearance_id)
	while _lru.size() > cache_limit:
		_state_cache.erase(_lru.pop_front())
	return state.duplicate(true)

## Compact authoritative representation for spawn/snapshot messages. Peers derive
## exactly the same state; meshes, textures, and player-owned item lists stay local.
func network_packet(identity: Variant, campus_seed := 0) -> Dictionary:
	return {"v": VERSION, "appearance_id": appearance_id_for(identity, campus_seed)}

func appearance_from_packet(packet: Dictionary) -> Dictionary:
	if int(packet.get("v", -1)) != VERSION:
		return {}
	var appearance_id := int(packet.get("appearance_id", 0))
	if appearance_id <= 0 or appearance_id > 2147483646:
		return {}
	return appearance_for_id(appearance_id)

func appearance_for_id(appearance_id: int) -> Dictionary:
	return appearance_for_student("packet:%d" % appearance_id, -appearance_id) if appearance_id <= 0 else _appearance_for_valid_id(appearance_id)

func _appearance_for_valid_id(appearance_id: int) -> Dictionary:
	if _state_cache.has(appearance_id):
		_touch(appearance_id)
		return (_state_cache[appearance_id] as Dictionary).duplicate(true)
	var state := _build_state(appearance_id)
	_state_cache[appearance_id] = state
	_touch(appearance_id)
	while _lru.size() > cache_limit:
		_state_cache.erase(_lru.pop_front())
	return state.duplicate(true)

func catalog() -> Dictionary:
	if _catalog.is_empty():
		for path in CATALOG_PATHS:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Dictionary:
				continue
			for item in parsed.get("items", []):
				if item is Dictionary and item.has("id"):
					_catalog[str(item.id)] = item
	return _catalog

func cache_size() -> int:
	return _state_cache.size()

func clear_cache() -> void:
	_state_cache.clear()
	_lru.clear()

static func appearance_id_for(identity: Variant, campus_seed := 0) -> int:
	# Explicit small hash avoids relying on randomized process hashes.
	var value := 216613626
	var text := "%s|%s" % [str(campus_seed), str(identity)]
	for byte in text.to_utf8_buffer():
		value = int((value * 16777619 + int(byte)) % 2147483647)
	return maxi(1, value)

func _build_state(appearance_id: int) -> Dictionary:
	var cursor := appearance_id
	var skin: String = SKINS[_pick(cursor, SKINS.size())]; cursor = _next(cursor)
	var hair_color: String = HAIR_COLORS[_pick(cursor, HAIR_COLORS.size())]; cursor = _next(cursor)
	var eye_color: String = EYE_COLORS[_pick(cursor, EYE_COLORS.size())]; cursor = _next(cursor)
	var top_color: String = TOP_COLORS[_pick(cursor, TOP_COLORS.size())]; cursor = _next(cursor)
	var accent: String = ACCENT_COLORS[_pick(cursor, ACCENT_COLORS.size())]; cursor = _next(cursor)
	var pants: String = BOTTOM_COLORS[_pick(cursor, BOTTOM_COLORS.size())]; cursor = _next(cursor)
	var shoes: String = SHOE_COLORS[_pick(cursor, SHOE_COLORS.size())]; cursor = _next(cursor)
	var body := {
		"height": _range(cursor, 0.82, 1.18), "width": _range(_next(cursor), 0.78, 1.24),
		"head": _range(_advance(cursor, 2), 0.90, 1.10), "head_width": _range(_advance(cursor, 3), 0.86, 1.14),
		"head_height": _range(_advance(cursor, 4), 0.90, 1.12), "neck_length": 1.0, "neck_width": 1.0,
		"shoulders": _range(_advance(cursor, 5), 0.82, 1.22), "torso_length": 1.0, "torso_width": 1.0,
		"waist": _range(_advance(cursor, 6), 0.82, 1.20), "hips": 1.0,
		"arm_length": _range(_advance(cursor, 7), 0.90, 1.10), "arm_width": 1.0, "hands": _range(_advance(cursor, 8), 0.90, 1.10),
		"leg_length": _range(_advance(cursor, 9), 0.88, 1.13), "leg_width": 1.0, "feet": _range(_advance(cursor, 10), 0.92, 1.08),
		"build": ["slim", "average", "heavy", "muscular"][_pick(_advance(cursor, 11), 4)], "skin": skin,
	}
	var hair_id: String = HAIR[_pick(_advance(cursor, 12), HAIR.size())]
	var equipped := {}
	_add(equipped, "face", FACES[_pick(_advance(cursor, 13), FACES.size())], {"iris_color": eye_color})
	_add(equipped, "hair", hair_id, {"color": hair_color, "highlight": _shift_color(hair_color, 0.16)})
	_add(equipped, "facial_hair", FACIAL_HAIR[_pick(_advance(cursor, 14), FACIAL_HAIR.size())], {"color": hair_color})
	_add(equipped, "top_inner", "tops.harbor_fitted_tee", {"primary_color": top_color})
	if _pick(_advance(cursor, 15), 4) != 0:
		var outer: String = ["tops.cedar_layered_hoodie", "tops.workshop_field_jacket", "tops.practical_lab_coat"][_pick(_advance(cursor, 16), 3)]
		_add(equipped, "top_outer", outer, {"primary_color": top_color, "secondary_color": accent, "detail_color": accent})
	_add(equipped, "bottom", BOTTOMS[_pick(_advance(cursor, 17), BOTTOMS.size())], {"primary_color": pants, "detail_color": accent})
	_add(equipped, "footwear", FOOTWEAR[_pick(_advance(cursor, 18), FOOTWEAR.size())], {"primary_color": shoes, "accent_color": accent})
	if _pick(_advance(cursor, 19), 3) == 0:
		_add(equipped, "eyewear", "accessory.face.round_study", {"primary_color": hair_color})
	if _pick(_advance(cursor, 20), 4) == 0:
		_add(equipped, "wrist_left", "accessory.wrist.bench_timer", {"primary_color": pants})
	if _pick(_advance(cursor, 21), 5) == 0 and hair_id not in ["hair.curly", "hair.bun"]:
		var head_id: String = ["accessory.head.campus_cap", "accessory.head.harbor_beanie"][_pick(_advance(cursor, 22), 2)]
		_add(equipped, "head", head_id, {"primary_color": top_color, "accent_color": accent})
	var legacy := {
		"name": "Student %d" % appearance_id, "skin": skin, "hair_color": hair_color, "eye_color": eye_color,
		"top": top_color, "accent": accent, "pants": pants, "shoes": shoes,
		"hair": ["Sweep", "Crop", "Bob", "Bun", "Spikes", "Curls", "Bald"][_pick(_advance(cursor, 23), 7)],
		"outfit": ["Varsity", "Hoodie", "Workwear", "Lab coat", "Tee"][_pick(_advance(cursor, 24), 5)],
		"expression": ["Smile", "Calm", "Grin", "Curious", "Stern"][_pick(_advance(cursor, 25), 5)],
		"glasses": "Round" if equipped.has("eyewear") else "None",
	}
	return {"version": VERSION, "appearance_id": appearance_id, "body": body, "equipped": equipped, "legacy_character": legacy}

func _add(equipped: Dictionary, slot: String, item_id: String, parameters: Dictionary) -> void:
	# Renderer/core sanitizes parameters against the real catalog; unsupported color
	# keys are discarded, keeping this forward compatible with legacy definitions.
	if catalog().has(item_id):
		equipped[slot] = {"id": item_id, "parameters": parameters}

func _touch(appearance_id: int) -> void:
	_lru.erase(appearance_id)
	_lru.append(appearance_id)

static func _next(value: int) -> int:
	return int((value * 48271 + 1) % 2147483647)

static func _advance(value: int, count: int) -> int:
	for unused in count:
		value = _next(value)
	return value

static func _pick(value: int, count: int) -> int:
	return posmod(value, count)

static func _range(value: int, low: float, high: float) -> float:
	return snappedf(lerpf(low, high, float(posmod(value, 10001)) / 10000.0), 0.01)

static func _shift_color(value: String, amount: float) -> String:
	return Color(value).lightened(amount).to_html(false)
