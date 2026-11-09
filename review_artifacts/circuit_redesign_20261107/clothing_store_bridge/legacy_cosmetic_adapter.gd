extends RefCounted
## Candidate for scripts/campus/facilities/clothing_store/legacy_cosmetic_adapter.gd.
## Uses the exact existing electronics profile catalog and ownership namespace.
const Profile = preload("res://scripts/electronics_profile.gd")

static func rows(profile_data: Dictionary) -> Array:
	var result: Array = []
	var owned: Array = profile_data.get("cosmetics", [])
	for id in Profile.COSMETICS:
		var item: Dictionary = Profile.COSMETICS[id]
		result.append({"id": id, "name": item.name, "price": item.price,
			"owned": id in owned, "category": "Laboratory wear", "settings": item.settings.duplicate(true)})
	return result

static func purchase_request(id: String, request_id: String) -> Dictionary:
	if not Profile.COSMETICS.has(id) or request_id.is_empty(): return {}
	# Existing ledger op retains its own replay, host price, atomic debit and ownership.
	return {"op": "cosmetic", "request_id": request_id, "args": [id]}

static func wear_settings(id: String, profile_data: Dictionary) -> Dictionary:
	if not Profile.COSMETICS.has(id) or id not in profile_data.get("cosmetics", []): return {}
	return Profile.COSMETICS[id].settings.duplicate(true)
