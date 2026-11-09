extends RefCounted
## One adapter per electronics UI lifetime, retained across page reconstruction.
## Existing fixed components use profile.buy. The canonical rating owner injects
## describe/quote/submit for configurable components; no rating schema lives here.
const StorePanel = preload("res://scripts/electronics/component_shop_ui/store_panel.gd")
const Ratings = preload("res://scripts/electronics/component_values/shop_services.gd")
const Dorm = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Custom = preload("res://scripts/custom_circuit.gd")
var owner_ui: Node
var panel: VBoxContainer
var services := {}
var active_request := ""
var transport_request := ""
var submitting := false
var outcome := {}

func build(ui: Node, parent: Node, canonical_services: Dictionary = {}) -> void:
	owner_ui=ui;services=canonical_services
	panel=StorePanel.new();parent.add_child(panel)
	panel.theme=services.get("theme",preload("res://scripts/ui/design_system/theme.gd").create())
	var entries: Dictionary = ui.profile.catalog()
	for id in ui.profile.data.get("blueprints", {}):
		if not entries.has(id): continue
		if entries[id].get("archived", false):
			entries.erase(id)
		else:
			entries[id].price = Custom.price(id, ui.profile.data.blueprints)
	panel.configure(entries,{
		"describe":services.get("describe",_describe),
		"quote":services.get("quote",_quote),
		"restock_quote":_fixed_quote,
		"snapshot":_snapshot,
		"balance":services.get("balance"),
		"modal_host":ui.screen,
		"blueprints":ui.profile.data.get("blueprints",{}),
		"close":services.get("close",Callable()),
	},ui.shop_search)
	panel.search_changed.connect(func(value: String):owner_ui.shop_search=value)
	panel.purchase_requested.connect(_purchase)
	if not active_request.is_empty():
		# Never offer another purchase while a prior host request is unresolved.
		panel.state.pending_id=active_request
		panel._set_pending(true)
	if not outcome.is_empty():panel._message(str(outcome.get("message","")),not outcome.get("ok",false))

func _snapshot() -> Dictionary:
	if services.get("snapshot",Callable()).is_valid():return services.snapshot.call()
	var data: Dictionary=owner_ui.profile.data
	# Only integration may supply the authenticated policy snapshot.
	return {"inventory":data.get("inventory",{}),"loose_inventory":Dorm.loose_stock(data),"dollars":data.get("dollars",0),"economy":services.get("economy",{})}

func _describe(id: String) -> Dictionary:
	if id.begins_with("ic:"):return {"fields":[]}
	return Ratings.describe(id,owner_ui.profile.catalog())

func _quote(id: String, fields: Dictionary, quantity: int) -> Dictionary:
	if not owner_ui.profile.data.get("pending_trade",{}).is_empty():return {"ok":false,"error":"Finish the pending trade first."}
	if id.begins_with("ic:"):return _fixed_quote(id,fields,quantity)
	return Ratings.quote(id,fields,quantity,owner_ui.profile.catalog(),owner_ui.profile.data.get("inventory",{}))

func _fixed_quote(id: String, fields: Dictionary, quantity: int) -> Dictionary:
	var catalog: Dictionary=owner_ui.profile.catalog()
	if not fields.is_empty() or not catalog.has(id) or quantity<1 or quantity>100:return {"ok":false,"error":"Unsupported component specification."}
	if not owner_ui.profile.data.get("pending_trade",{}).is_empty():return {"ok":false,"error":"Finish the pending trade first."}
	var price := int(catalog[id].get("price",0))
	if id.begins_with("ic:"):
		if catalog[id].get("archived", false):return {"ok":false,"error":"This blueprint is archived."}
		price=Custom.price(id,owner_ui.profile.data.get("blueprints",{}))
	# Display estimate only. Existing profile/ledger derives the price again.
	return {"ok":true,"id":id,"unit_price":price,"total":price*quantity,"intent":{"op":"buy","args":[id,quantity]}}

func _purchase(id: String, intent: Dictionary) -> void:
	if not active_request.is_empty():return
	active_request=id;transport_request="";outcome={};submitting=true
	if services.get("submit",Callable()).is_valid():
		# submit(id,intent,completion) must route via the authenticated ledger.
		services.submit.call(id,intent,complete)
		submitting=false
		return
	if not intent.get("args") is Array:
		submitting=false;complete(id,{"ok":false,"message":"Purchase service unavailable."});return
	var asynchronous: bool=owner_ui.profile.authority_submit.is_valid()
	var message := "Purchase service unavailable."
	if intent.get("op")=="buy" and intent.args.size()==2:
		message=owner_ui.profile.buy(str(intent.args[0]),int(intent.args[1]))
	elif intent.get("op")=="buy_configured" and intent.args.size()==3 and owner_ui.profile.has_method("buy_configured"):
		message=owner_ui.profile.buy_configured(str(intent.args[0]),intent.args[1],int(intent.args[2]),not asynchronous)
	else:
		submitting=false;complete(id,{"ok":false,"message":message});return
	submitting=false
	if not asynchronous:complete(id,{"ok":owner_ui.profile.operation_succeeded,"message":message})
	elif transport_request.is_empty():complete(id,{"ok":false,"message":"Host queue unavailable. Purchase was not sent."})

func submitted(id: String, op: String) -> void:
	# Hook immediately after network.pending.append and before flush (host can
	# respond synchronously). Never match by inventory deltas or message strings.
	if submitting and op in ["buy","buy_configured"] and transport_request.is_empty():transport_request=id

func received(id: String, result: Dictionary) -> bool:
	if id.is_empty() or id!=transport_request:return false
	complete(active_request,{"ok":result.get("ok",false),"message":result.get("message",result.get("error","Purchase saved."))})
	return true

func complete(id: String, result: Dictionary) -> void:
	if id.is_empty() or id!=active_request:return
	outcome=result.duplicate(true)
	active_request="";transport_request=""
	if is_instance_valid(panel):panel.complete_purchase(id,result)

func disconnected() -> void:
	# The host may already have committed. Keep blocked until its existing queue
	# resolves the same receipt; do not retry with a fresh transaction ID.
	if not active_request.is_empty() and is_instance_valid(panel):panel._message("Connection interrupted. Reconnect to the same host to recover this purchase.",true)
