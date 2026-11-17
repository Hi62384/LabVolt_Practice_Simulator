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
	for bundle in preload("res://scripts/ui/store_bundles_equipment/bundle_catalog.gd").guaranteed():
		var price := 0
		var count := 0
		for id in bundle.items:
			price+=int(Catalog.all()[id].price)*int(bundle.items[id])
			count+=int(bundle.items[id])
		var tier := str(bundle.get("kit_tier",""))
		if not tier.is_empty():price+=int(Profile.KIT_TIERS[tier].price)
		result.append({"kind":"guaranteed","name":bundle.name,"items":bundle.items,"price":ceili(price*.8),"count":count,"kit_tier":tier})
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
	for capacity in preload("res://scripts/campus/computers/usb_inventory.gd").PRICES:
		result.append({"kind":"usb","capacity_mb":capacity,"name":"%d MB USB drive"%capacity,"price":preload("res://scripts/campus/computers/usb_inventory.gd").PRICES[capacity],"rarity":"Common","summary":"Portable file storage","description":"Save computer files on a removable USB drive."})
	var laptops: Dictionary=preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	for tier in ["basic","standard","premium"]:
		var laptop: Dictionary=laptops[tier]
		var summary: String={"basic":"Entry-level performance","standard":"Faster performance","premium":"Full-speed performance"}[tier]
		result.append({"kind":"portable_laptop","tier":tier,"name":laptop.name,"price":laptop.price,"rarity":{"basic":"Uncommon","standard":"Rare","premium":"Epic"}[tier],"summary":summary,"description":"Portable computer with %s. Select it and press F to place it; right-click to open and use it. Connect a USB drive to keep files after power-off."%summary.to_lower()})
	var phones: Dictionary=preload("res://scripts/campus/phones/phone_tiers.gd").TIERS
	for tier in ["basic","standard","premium"]:
		var phone: Dictionary=phones[tier]
		result.append({"kind":"smartphone","tier":tier,"name":phone.name,"price":phone.price,"rarity":{"basic":"Uncommon","standard":"Rare","premium":"Epic"}[tier],"summary":"%d MB photo storage"%int(phone.storage_bytes/1048576),"description":"Right-click to open your phone. Press P while holding it to take an in-game photo. Web browsing is not available yet."})
	return result

static func populate(parent: Node, profile: Variant, refresh: Callable, status: Label, section: String, reveal := Callable(), product_kinds: Array = []) -> void:
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
	if not product_kinds.is_empty():entries=entries.filter(func(product):return str(product.get("kind","")) in product_kinds)
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
		"Digital assortment":["led_green","hc00","hc04","timer555"],"Builder assortment":["pot10k","buzzer","spi_display","lv_mcu"],"ETY155 lab kit":["r1000","r220","pot10k","led"],"DGS266 digital lab kit":["hc00","hc08","flip74","seven_segment"]}
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
		if not str(product.get("kit_tier", "")).is_empty():parent.add_child(UI.text("Includes a large kit case with these components packed inside.","MutedLabel"))
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
		parent.add_child(UI.text("Goes to your hotbar or dorm cabinet." if kind in ["usb","portable_laptop","smartphone"] else "Goes to your hotbar, equipped backpack, or dorm cabinet, in that order.","MutedLabel"))
	var buy := UI.action("Buy for $%d"%product.price,"cart",Callable())
	buy.pressed.connect(func():
		if buy.disabled:return
		buy.disabled=true
		var message := ""
		match kind:
			"guaranteed": message=profile.purchase_bundle(product.items,product.price)
			"random": message=profile.buy_box(product.name)
			"lab_goggles": message=profile.buy_study_tool("lab_goggles")
			"kit": message=profile.create_kit(product.tier)
			"usb": message=profile.buy_usb(int(product.capacity_mb))
			"portable_laptop": message=profile.buy_portable_laptop(str(product.tier))
			"smartphone": message=profile.buy_smartphone(str(product.tier))
		var items: Dictionary = profile.last_bundle_receipt if kind in ["guaranteed", "random"] else {}
		refresh.call(message)
		if reveal.is_valid() and not items.is_empty():
			reveal.call({"name":product.name,"items":items})
	)
	parent.add_child(buy)

