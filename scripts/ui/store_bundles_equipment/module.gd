extends RefCounted
## Bundle/equipment presentation. Prices and receipt actions use existing profile methods.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Art = preload("res://scripts/electronics/component_shop_ui/component_art.gd")
const Catalog = preload("res://scripts/electronics_catalog.gd")
const Dorm = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Portraits = preload("res://scripts/ui/personal_inventory/item_portraits.gd")

static func products(profile: Variant) -> Array:
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
	return result

static func equipment_products() -> Array:
	var result := [{
		"kind": "lab_goggles", "name": Dorm.TOOLS["lab_goggles"], "price": Dorm.TOOL_PRICES["lab_goggles"],
		"rarity": "Uncommon", "summary": "Protective eyewear",
		"description": "Protective eyewear for your head accessory slot."
	}]
	for tier in Profile.KIT_TIERS:
		var kit: Dictionary = Profile.KIT_TIERS[tier]
		var summary := "%d component spaces" % int(kit.capacity)
		result.append({
			"kind": "kit", "tier": tier, "name": kit.name, "price": kit.price, "rarity": kit.rarity,
			"summary": summary, "description": "%s." % summary
		})
	return result

static func populate(parent: Node, profile: Variant, refresh: Callable, status: Label, section: String, reveal := Callable()) -> void:
	# The shell mounts Bundles and Equipment in separate section containers.
	assert(section in ["bundles", "equipment"])
	var layout := HBoxContainer.new()
	layout.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation",14)
	parent.add_child(layout)
	var grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	grid.maximum_columns=3
	layout.add_child(grid)
	var inspector := PanelContainer.new()
	inspector.custom_minimum_size=Vector2(310,240)
	layout.add_child(inspector)
	var details_body := VBoxContainer.new()
	inspector.add_child(details_body)
	var is_bundle := section == "bundles"
	var portraits := Portraits.new()
	var entries := products(profile) if is_bundle else equipment_products()
	for product in entries:
		var summary: String = product.get("summary", "")
		if is_bundle:
			summary = "%d guaranteed items" % product.count if product.kind == "guaranteed" else "%d random draws" % product.count
		var card := UI.card(product.name,"$%d · %s" % [product.price, summary],"inventory",product.get("rarity","Common"))
		grid.add_child(card)
		var tile: PanelContainer = card.get_node("Content/Icon")
		tile.custom_minimum_size = Vector2(92,92)
		var picture: TextureRect = tile.get_child(0)
		picture.texture = bundle_art(product.name) if is_bundle else portraits.texture(product,profile)
		var button := UI.action("Details","info",func():details(details_body,profile,product,refresh,status,reveal))
		card.get_node("Content/Copy").add_child(button)

static func bundle_art(name: String, opened := false) -> Texture2D:
	var catalog := Catalog.all()
	var samples := {"Resistor box":["r1000","r220","r10000"],"Capacitor box":["c0.1","c1.0","c10.0"],
		"Semiconductor starter":["diode","led","diode","led"],"Basic assortment":["r220","c1.0","button","led"],
		"Digital assortment":["led_green","hc00","hc04","timer555"],"Builder assortment":["pot10k","buzzer","spi_display","lv_mcu"]}
	var colors := {"Resistor box":"73614a","Capacitor box":"43647d","Semiconductor starter":"704b61",
		"Basic assortment":"4c6754","Digital assortment":"564b78","Builder assortment":"7a5544"}
	var entries: Array = []
	for id in samples.get(name,[]): entries.append(catalog[id])
	return Art.bundle(entries, colors.get(name,"527071"), opened)

static func details(parent: Node, profile: Variant, product: Dictionary, refresh: Callable, status: Label, reveal: Callable) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	parent.add_child(UI.text(product.name,"Title"))
	var kind: String=product.kind
	if kind in ["guaranteed", "random"]:
		var random := kind == "random"
		if random:
			parent.add_child(UI.text("%d independent draws · Per-draw odds" % product.count))
		var catalog := Catalog.all()
		var items: Dictionary = product.pool if random else product.items
		for id in items:
			var entry: Dictionary = catalog[id]
			var row := HBoxContainer.new()
			parent.add_child(row)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(36, 36)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = Art.texture(entry)
			row.add_child(icon)
			var label := UI.text("%s · %d%%" % [entry.name, items[id]] if random else "%d × %s" % [items[id], entry.name])
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(label)
	else:
		var description := UI.text(product.description)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(description)
		parent.add_child(UI.text("Goes to your hotbar, equipped backpack, or dorm cabinet, in that order.","MutedLabel"))
	var buy := UI.action("Buy for $%d"%product.price,"cart",func():
		var message := ""
		match kind:
			"guaranteed": message=profile.purchase_bundle(product.items,product.price)
			"random": message=profile.buy_box(product.name)
			"lab_goggles": message=profile.buy_study_tool("lab_goggles")
			"kit": message=profile.create_kit(product.tier)
		var items: Dictionary = profile.last_bundle_receipt if kind in ["guaranteed", "random"] else {}
		refresh.call(message)
		if reveal.is_valid() and not items.is_empty():
			reveal.call({"name":product.name,"items":items})
	)
	parent.add_child(buy)

