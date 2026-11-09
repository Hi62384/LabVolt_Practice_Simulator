extends SceneTree
## Authored for later isolated engine QA. Do not run during active playtesting.
const StorePanel=preload("res://scripts/electronics/component_shop_ui/store_panel.gd")
const State=preload("res://scripts/electronics/component_shop_ui/shop_state.gd")
var purchases: Array=[]
var inventory := {"r1000":3}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	assert(State.quantity_error("")!="")
	assert(State.quantity_error("-1")!="")
	assert(State.quantity_error("2.5")!="")
	assert(State.quantity_error("0")!="")
	assert(State.quantity_error("100001")!="")
	assert(State.quantity_error("42")=="")
	var panel=StorePanel.new();root.add_child(panel)
	panel.configure({"r1000":{"name":"1 kΩ resistor","kind":"R","rarity":"Common","price":1,"space":1,"rating":"0.25 W","value":1000.0}},{
		"describe":func(_id):return {"fields":[{"key":"value","label":"Resistance","unit":"Ω","default":"1 kΩ"}]},
		"quote":func(id,fields,amount):return {"ok":true,"total":amount,"unit_price":1,"intent":{"test_id":id,"test_fields":fields,"test_quantity":amount}},
		"snapshot":func():return {"inventory":inventory,"loose_inventory":{"r1000":1},"dollars":50,"economy":{"ok":true,"unlimited_purchases":true}},
	})
	panel.purchase_requested.connect(func(id,intent):purchases.append({"id":id,"intent":intent}))
	assert(panel.balance.text=="$∞")
	panel._select("r1000")
	assert("Loose 1" in panel.card_counts.r1000.text)
	assert("Loose: 1 · Total owned: 3" in panel.ownership.text)
	panel.quantity.value=12
	panel._review_or_purchase();assert(purchases.is_empty())
	# Editing after review must require a new confirmation.
	panel.quantity.value=13
	panel._review_or_purchase();assert(purchases.is_empty())
	panel._review_or_purchase();assert(purchases.size()==1)
	assert(purchases[0].intent.test_quantity==13)
	assert(is_equal_approx(float(purchases[0].intent.test_fields.value),1000.0))
	panel._review_or_purchase();assert(purchases.size()==1)
	panel.complete_purchase("stale-response",{"ok":true})
	assert(not panel.state.pending_id.is_empty())
	panel.complete_purchase(purchases[0].id,{"ok":false,"message":"Rejected by host"})
	assert(panel.state.pending_id.is_empty());assert(not panel.buy.disabled)
	assert("Rejected by host" in panel.feedback.text)
	panel.quantity.value=0;assert(panel.quantity.value==1)
	panel.queue_free();await process_frame
	print("PASS: shop quantity, review invalidation, opaque intent, pending lock and exact response correlation")
	quit()
