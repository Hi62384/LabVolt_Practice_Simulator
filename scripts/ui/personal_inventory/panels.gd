extends RefCounted
## Presentation only. All ownership changes remain with the authenticated trade service.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const InventoryTheme = preload("res://scripts/ui/design_system/theme.gd")

static func item_icon(item: Dictionary) -> String:
	match str(item.get("kind", "")):
		"paper", "notebook": return "course"
		"calculator": return "math"
		"pencil_case": return "inventory"
		"kit": return "inventory"
		"board", "wire", "dc_wire": return "circuit"
	return "plus"

static func component_icon(type: String) -> String:
	for key in ["resistor", "capacitor", "inductor", "diode", "led", "switch"]:
		if type.to_lower().contains(key): return key
	return "chip" if type.begins_with("ic:") else "component"

static func offer_panel(parent: Node, title: String, offer: Dictionary, catalog: Dictionary) -> void:
	parent.add_child(UI.badge(title,"inventory"))
	var count := 0
	for type in offer:
		if int(offer[type])<=0: continue
		var definition: Dictionary=catalog.get(type,{})
		parent.add_child(UI.card(str(definition.get("name",type)),"Quantity · %d"%int(offer[type]),component_icon(str(type)),str(definition.get("rarity","Common"))))
		count+=1
	if count==0: parent.add_child(UI.badge("No items offered","info"))

static func trade_menu(service: Node, parent: Node) -> void:
	parent.theme=InventoryTheme.create()
	parent.add_child(UI.card("Player trade","Review both offers before confirming. Changes reset both confirmations.","network"))
	var game=service.game
	if not game.session.online:
		parent.add_child(UI.badge("Join or host a multiplayer laboratory to trade.","lock"));return
	if game.school.mode=="Creative Freeplay":
		parent.add_child(UI.badge("Creative components cannot be traded.","lock"));return
	if service.current.is_empty():
		parent.add_child(UI.badge("Choose a player to invite","network"))
		for peer in game.session.roster:
			if peer!=service.multiplayer.get_unique_id():
				parent.add_child(UI.action("Trade with "+str(game.session.roster[peer].name),"network",func():service.request({"op":"invite","target":peer})))
		return
	var snapshot: Dictionary=service.current.duplicate(true)
	var id: String=str(snapshot.id)
	var revision: int=int(snapshot.get("revision",0))
	var mine: int=service.multiplayer.get_unique_id()
	var other: int=snapshot.peers[1] if snapshot.peers[0]==mine else snapshot.peers[0]
	var catalog: Dictionary=service.profile().catalog()
	# Display received definitions without importing or granting ownership.
	catalog=catalog.duplicate(true)
	catalog.merge(preload("res://scripts/custom_circuit.gd").catalog(snapshot.get("definitions",{})))
	parent.add_child(UI.badge("Confirmed · %d / 2 · Revision %d"%[snapshot.confirmed.size(),revision],"check"))
	var grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	grid.maximum_columns=2;parent.add_child(grid)
	var own := VBoxContainer.new();var theirs := VBoxContainer.new();grid.add_child(own);grid.add_child(theirs)
	offer_panel(own,"Your submitted offer",snapshot.offers[mine],catalog)
	offer_panel(theirs,"Their submitted offer",snapshot.offers[other],catalog)
	for participant in snapshot.get("instances",{}):
		for instance in snapshot.instances[participant]:
			var label := UI.text(("Your" if participant==mine else "Their")+" physical item · "+str(instance),"MutedLabel")
			label.tooltip_text="Saved state · "+str(snapshot.instances[participant][instance]);parent.add_child(label)
	if snapshot.phase!="review":
		parent.add_child(UI.badge("Accepted · Saving authenticated receipt. Keep this profile open.","save"));return
	var draft_key := id+":"+str(revision)
	if str(service.get_meta("ui_draft_key",""))!=draft_key:
		service.set_meta("ui_draft_key",draft_key)
		service.set_meta("ui_draft",snapshot.offers[mine].duplicate(true))
	var proposal: Dictionary=service.get_meta("ui_draft")
	parent.add_child(UI.badge("Edit your offer · quantities remain owned until receipt","component"))
	var feedback := UI.text("Review the submitted offers above.","MutedLabel")
	var confirm_callback := func():
		if _current(service,id,revision):service.request({"op":"confirm","id":id,"revision":revision})
	var confirm := UI.action("Confirm displayed offers","check",confirm_callback,true)
	confirm.disabled=mine in snapshot.confirmed or proposal!=snapshot.offers[mine]
	if confirm.disabled:confirm.text="Confirmed · Waiting for other player"
	for type in service.profile().data.inventory:
		if not catalog.has(type):continue
		var definition: Dictionary=catalog[type]
		var card := UI.card(str(definition.name),"Owned · %d"%int(service.profile().data.inventory[type]),component_icon(str(type)),str(definition.get("rarity","Common")))
		parent.add_child(card)
		var amount := SpinBox.new();amount.min_value=0;amount.max_value=service.profile().data.inventory[type];amount.step=1;amount.value=proposal.get(type,0);amount.custom_minimum_size=Vector2(140,44)
		amount.tooltip_text="Offer quantity · "+str(definition.name)
		card.get_node("Content/Copy").add_child(amount)
		amount.value_changed.connect(func(value):
			proposal[type]=int(value);confirm.disabled=true;feedback.text="Offer changed. Submit your changes before confirming."
		)
	parent.add_child(feedback)
	parent.add_child(UI.action("Submit offer · Reset confirmations","save",func():
		if _current(service,id,revision):
			service.request({"op":"offer","id":id,"items":proposal,"definitions":service.offer_definitions(proposal)})
			feedback.text="Offer submitted · Waiting for host review";confirm.disabled=true
	))
	parent.add_child(confirm)
	parent.add_child(UI.action("Cancel trade","close",func():
		if str(service.current.get("id",""))==id:service.request({"op":"cancel","id":id})
	))

static func _current(service: Node, id: String, revision: int) -> bool:
	return str(service.current.get("id",""))==id and int(service.current.get("revision",-1))==revision and service.current.get("phase","")=="review"

static func notebook_intro(parent: Node, open_callback: Callable) -> void:
	parent.add_child(UI.card("Your notebook","Carry your notes, drawings and saved page with your character.","course"))
	parent.add_child(UI.action("Open my notebook","course",open_callback,true))
