extends SceneTree

const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const ProfileAdapter = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
const Catalog = preload("res://scripts/campus/facilities/clothing_store/store_catalog.gd")
const Session = preload("res://scripts/campus/facilities/clothing_store/store_session.gd")
const Bridge = preload("res://scripts/campus/facilities/clothing_store/ledger_bridge.gd")
const Room = preload("res://scripts/campus/facilities/clothing_store/room_builder.gd")

var failed := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed += 1; printerr("FAIL " + label)

func _initialize() -> void:
	var catalog := Catalog.new()
	check(catalog.errors.is_empty() and catalog.items.size() > 20, "four real catalogs validate")
	var jacket: Dictionary = catalog.item("tops.workshop_field_jacket")
	check(jacket.price == 320 and not jacket.scene.is_empty(), "real definition and price")
	check(catalog.supported_parameters(jacket.id).has("primary_color"), "supported parameters exposed")

	var session := Session.new()
	var previews: Array = []
	var requests: Array = []
	session.preview_changed.connect(func(intent): previews.append(intent))
	session.purchase_requested.connect(func(request): requests.append(request))
	session.open({"dollars": 400, "owned_cosmetics": []})
	check(session.select(jacket.id, {"fit": 99.0}), "selection")
	check(previews.size() == 1 and previews[0].preview_only == true and previews[0].parameters.fit == 1.08, "preview is local and sanitized")
	check(session.request_purchase("req-1") and requests[0].intent == {"op": "purchase", "id": jacket.id}, "compact authoritative request")
	check(not session.request_purchase("req-2"), "one pending request")
	session.accept_authoritative_result("req-1", {"ok": true}, {"dollars": 80, "owned_cosmetics": [jacket.id]})
	check(session.selected_state().status == "owned", "success consumes authoritative snapshot")

	session.open({"dollars": 0, "owned_cosmetics": []})
	session.select(jacket.id)
	check(session.selected_state().status == "insufficient_funds", "insufficient funds state")
	session.open({"dollars": 0, "owned_cosmetics": [], "purchasing_power_unlimited": true})
	session.select(jacket.id)
	check(session.selected_state().status == "available" and session.selected_state().unlimited, "authoritative unlimited-funds capability")
	session.cancel_preview()
	check(session.selected_state().status == "none", "cancel restores selection state")

	var bridge := Bridge.new()
	var profile := {"dollars": 400, "owned_cosmetics": [], "avatar_cosmetics": {"version": 1, "body": {}, "equipped": {}}}
	var bought := bridge.apply_to_transaction_profile(profile, {"op": "cosmetic_purchase", "intent": {"op": "purchase", "id": jacket.id}})
	check(bought.ok and bought.profile.dollars == 80 and jacket.id in bought.profile.owned_cosmetics, "atomic debit and ownership")
	var duplicate := bridge.apply_to_transaction_profile(bought.profile, {"op": "cosmetic_purchase", "intent": {"op": "purchase", "id": jacket.id}})
	check(not duplicate.ok and duplicate.error == "Already owned" and bought.profile.dollars == 80, "duplicate cannot debit")
	var denied := bridge.apply_to_transaction_profile({"dollars": 1, "owned_cosmetics": []}, {"op": "cosmetic_purchase", "intent": {"op": "purchase", "id": jacket.id}})
	check(not denied.ok and denied.error == "Not enough dollars", "authority denies unaffordable purchase")

	var room := Room.new()
	var record := room.registry_record(Vector3(40, 0, 20))
	check(record.bounds_min == [31.0, 0.0, 12.0] and record.bounds_max == [49.0, 4.2, 28.0], "translated room bounds")
	for anchor in record.interactions.values():
		check(anchor[0] >= record.bounds_min[0] and anchor[0] <= record.bounds_max[0] and anchor[2] >= record.bounds_min[2] and anchor[2] <= record.bounds_max[2], "interaction inside room")

	print("CLOTHING STORE checks=", checks, " failures=", failed)
	quit(1 if failed else 0)
