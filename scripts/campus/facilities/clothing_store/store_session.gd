class_name ClothingStoreSession
extends RefCounted
## Client-side browse/preview state. Only `purchase_requested` crosses to authority.

signal preview_changed(intent: Dictionary)
signal preview_cancelled
signal purchase_requested(request: Dictionary)
signal state_changed(state: Dictionary)

const ProfileAdapter = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const CatalogSource = preload("res://scripts/campus/facilities/clothing_store/store_catalog.gd")

var catalog := CatalogSource.new()
var profile: Dictionary = {}
var selected_id := ""
var selected_parameters: Dictionary = {}
var pending_request_id := ""
var message := ""
var economy_display: Dictionary = {}

func set_economy_display(authoritative_display: Dictionary) -> void:
	economy_display = authoritative_display.duplicate(true)
	_emit_state()

func unlimited_funds() -> bool:
	return economy_display.get("ok", false) == true and economy_display.get("unlimited_purchases", false) == true

func request_equip(request_id: String) -> bool:
	if selected_state().status != "owned" or not pending_request_id.is_empty() or request_id.is_empty() or request_id.length() > 128:
		return false
	pending_request_id = request_id
	message = "Saving outfit…"
	purchase_requested.emit({"op": "avatar_cosmetic", "request_id": request_id, "intent": {"op": "equip", "id": selected_id, "parameters": selected_parameters.duplicate(true)}})
	_emit_state()
	return true

func open(authoritative_snapshot: Dictionary) -> void:
	profile = ProfileAdapter.new(catalog.items).migrate(authoritative_snapshot)
	selected_id = ""
	selected_parameters = {}
	pending_request_id = ""
	message = ""
	_emit_state()

func select(item_id: String, parameters := {}) -> bool:
	var definition := catalog.item(item_id)
	if definition.is_empty() or not parameters is Dictionary:
		message = "Item unavailable"
		_emit_state()
		return false
	selected_id = item_id
	message = ""
	selected_parameters = Core.sanitize_parameters(definition, parameters)
	preview_changed.emit({"op": "equip", "id": item_id, "parameters": selected_parameters.duplicate(true), "preview_only": true})
	_emit_state()
	return true

func cancel_preview() -> void:
	selected_id = ""
	selected_parameters = {}
	preview_cancelled.emit()
	_emit_state()

func request_purchase(request_id: String) -> bool:
	if selected_id.is_empty() or not pending_request_id.is_empty() or request_id.is_empty() or request_id.length() > 128:
		return false
	var state := selected_state()
	if state.status != "available":
		message = state.message
		_emit_state()
		return false
	pending_request_id = request_id
	message = "Confirming purchase…"
	# Compact IDs only: the host resolves price and definition from its own catalog.
	purchase_requested.emit({"op": "cosmetic_purchase", "request_id": request_id, "intent": {"op": "purchase", "id": selected_id}})
	_emit_state()
	return true

func accept_authoritative_result(request_id: String, result: Dictionary, snapshot: Dictionary) -> void:
	if request_id != pending_request_id:
		return
	pending_request_id = ""
	if result.get("ok", false) == true:
		profile = ProfileAdapter.new(catalog.items).migrate(snapshot)
		message = "Saved successfully"
	else:
		message = str(result.get("error", "Purchase could not be completed"))
	_emit_state()

func selected_state() -> Dictionary:
	var definition := catalog.item(selected_id)
	if definition.is_empty():
		return {"status": "none", "message": "Select an item"}
	var owned: Array = profile.get("owned_cosmetics", [])
	if selected_id in owned:
		return {"status": "owned", "message": "Owned", "price": int(definition.get("price", 0))}
	if definition.get("locked", false) == true:
		return {"status": "locked", "message": str(definition.get("lock_reason", "Locked")), "price": int(definition.get("price", 0))}
	var price := int(definition.get("price", 0))
	var dollars := int(profile.get("dollars", 0))
	if unlimited_funds():
		return {"status": "available", "message": "Buy for $%d · unlimited playtest funds" % price, "price": price, "unlimited": true}
	if dollars < price:
		return {"status": "insufficient_funds", "message": "Need $%d more" % (price - dollars), "price": price}
	return {"status": "available", "message": "Buy for $%d" % price, "price": price}

func view() -> Dictionary:
	return {"selected_id": selected_id, "parameters": selected_parameters.duplicate(true), "balance": int(profile.get("dollars", 0)), "unlimited": unlimited_funds(), "pending": not pending_request_id.is_empty(), "message": message, "purchase": selected_state()}

func _emit_state() -> void:
	state_changed.emit(view())
