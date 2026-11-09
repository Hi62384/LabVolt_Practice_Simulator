extends RefCounted
## Bundle/equipment presentation. Prices and receipt actions use existing profile methods.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Catalog = preload("res://scripts/electronics_catalog.gd")

static func products(profile: Node) -> Array:
	var result: Array=[]
	for bundle in [
		{"name":"Resistor box","items":{"r1000":10,"r220":10,"r10000":10}},
		{"name":"Capacitor box","items":{"c0.1":4,"c1.0":4,"c10.0":4}},
		{"name":"Semiconductor starter","items":{"diode":6,"led":6}}
	]:
		var price := 0
		var count := 0
		for id in bundle.items:
			price+=int(Catalog.all()[id].price)*int(bundle.items[id])
			count+=int(bundle.items[id])
		result.append({"kind":"guaranteed","name":bundle.name,"items":bundle.items,"price":ceili(price*.8),"count":count})
	for name in profile.BOXES:
		var box: Dictionary=profile.BOXES[name]
		result.append({"kind":"random","name":name,"pool":box.pool,"price":int(box.price),"count":int(box.draws)})
	result.append({"kind":"analyzer","name":"Circuit Analyzer","price":75,"owned":bool(profile.data.get("analyzer",false))})
	result.append({"kind":"capacity","name":"Kit capacity +20","price":50,"capacity":int(profile.data.capacity)})
	return result

static func populate(parent: Node, profile: Node, refresh: Callable, status: Label, section: String) -> void:
	# The shell mounts Bundles and Equipment in separate section containers.
	assert(section in ["bundles", "equipment"])
	var grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	grid.maximum_columns=3
	parent.add_child(grid)
	for product in products(profile):
		var kind: String=product.kind
		if section=="bundles" and kind not in ["guaranteed","random"]:continue
		if section=="equipment" and kind not in ["analyzer","capacity"]:continue
		var detail := "Owned" if product.get("owned",false) else "$%d · %s"%[product.price,"%d guaranteed items"%product.count if kind=="guaranteed" else "%d random draws"%product.count if kind=="random" else "Permanent unlock" if kind=="analyzer" else "Current capacity %d"%product.capacity]
		var card := UI.card(product.name,detail,"circuit" if kind=="analyzer" else "plus" if kind=="capacity" else "inventory")
		grid.add_child(card)
		var button := UI.action("Details","info",func():details(parent,profile,product,refresh,status))
		card.get_node("Content/Copy").add_child(button)

static func details(parent: Node, profile: Node, product: Dictionary, refresh: Callable, status: Label) -> void:
	var dialog := ConfirmationDialog.new()
	parent.add_child(dialog)
	dialog.title=product.name
	var kind: String=product.kind
	var description := ""
	if kind=="guaranteed":
		for id in product.items:description+="%d × %s\n"%[product.items[id],Catalog.all()[id].name]
	elif kind=="random":
		description="%d independent draws. Per-draw odds:\n"%product.count
		for id in product.pool:description+="%s: %d%%\n"%[Catalog.all()[id].name,product.pool[id]]
	elif kind=="analyzer":description="Unlock the Circuit Analyzer for all kits."
	else:description="Increase kit capacity by 20 from %d."%product.capacity
	dialog.dialog_text=description+"\nTotal: $%d game dollars"%product.price
	dialog.ok_button_text="Buy for $%d"%product.price
	dialog.confirmed.connect(func():
		var message := ""
		match kind:
			"guaranteed": message=profile.purchase_bundle(product.items,product.price)
			"random": message=profile.buy_box(product.name)
			"analyzer": message=profile.buy_analyzer()
			"capacity": message=profile.upgrade_capacity()
		status.text=message
		refresh.call()
	)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
