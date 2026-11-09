class_name ClothingStoreLedgerBridge
extends RefCounted
## Host-only seam. The shared ledger owns authentication, replay receipts and persistence.

const ProfileAdapter = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const StoreCatalog = preload("res://scripts/campus/facilities/clothing_store/store_catalog.gd")

var adapter: RefCounted

func _init() -> void:
	var catalog := StoreCatalog.new()
	adapter = ProfileAdapter.new(catalog.items, Core.resolve, Core.sanitize_body)
	adapter.is_authority = func() -> bool: return true

func apply_to_transaction_profile(profile: Dictionary, request: Dictionary) -> Dictionary:
	if request.get("op") != "cosmetic_purchase" or not request.get("intent") is Dictionary:
		return {"ok": false, "error": "Malformed clothing-store request"}
	var intent: Dictionary = request.intent
	if intent.get("op") != "purchase" or not intent.get("id") is String or intent.size() != 2:
		return {"ok": false, "error": "Malformed clothing-store purchase"}
	return adapter.apply_authoritative(profile, intent)
