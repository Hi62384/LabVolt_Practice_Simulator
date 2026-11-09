class_name ClothingStorePanel
extends PanelContainer
## Store-specific shell around the shared card/grid/cache and live-preview components.

signal close_requested

const ItemGrid = preload("res://scripts/avatar_cosmetics/ui/item_grid.gd")
const ThumbnailCache = preload("res://scripts/avatar_cosmetics/ui/thumbnail_cache.gd")
const LivePreview = preload("res://scripts/avatar_cosmetics/ui/live_preview.gd")
const Session = preload("res://scripts/campus/facilities/clothing_store/store_session.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const StudioScene = preload("res://scenes/avatar_cosmetics/customizer_panel.tscn")
const Studio = preload("res://scripts/avatar_cosmetics/ui/customizer_panel.gd")
const Categories = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const StoreTheme = preload("res://scripts/ui/design_system/theme.gd")
const Parameters = preload("res://scripts/avatar_cosmetics/ui/parameter_panel.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
var catalog: Control
var category_buttons := {}
var ownership_filter: OptionButton
var empty_label: Label
var parameter_panel: ScrollContainer
var purchase_review := ""

var session := Session.new()
var grid: ScrollContainer
var cache: Node
var preview: SubViewportContainer
var search: LineEdit
var category := ""
var name_label: Label
var price_label: Label
var message_label: Label
var balance_label: Label
var buy_button: Button
var request_id_factory := Callable()

func _ready() -> void:
	theme = StoreTheme.create()
	catalog = StudioScene.instantiate()
	# The scene supplies the same layout and widgets. StoreSession owns commerce.
	catalog.set_script(null)
	add_child(catalog)
	var column := catalog.get_node("Margin/Root/Content/StageColumn")
	column.get_node("Header/Title").text = "Harbor Outfitters"
	column.get_node("Subtitle").text = "CAMPUS CLOTHING STORE"
	var poses := catalog.get_node("%PreviewPose") as OptionButton
	preview = catalog.get_node("%LivePreview")
	preview.use_native_resolution()
	for pose in ["Relaxed", "Fit check", "T-pose", "Walk"]:
		poses.add_item(pose)
	poses.select(0)
	poses.item_selected.connect(func(index: int):preview.set_pose(poses.get_item_text(index)))
	preview.set_pose("Relaxed")
	var category_bar := catalog.get_node("%CategoryBar") as HFlowContainer
	for id in [""] + Categories.DISPLAY_CATEGORIES:
		if id=="body":continue
		var button := Button.new()
		button.text = "All" if id=="" else str(Studio.CATEGORY_MARKS.get(id,""))+"  "+str(id).replace("_"," ").capitalize()
		button.custom_minimum_size.y=36
		button.toggle_mode=true
		button.add_theme_font_size_override("font_size",14)
		button.pressed.connect(func():
			category=id
			_refresh())
		category_buttons[id]=button
		category_bar.add_child(button)
	var filters := HBoxContainer.new()
	var browser := catalog.get_node("Margin/Root/Content/Properties/Browser")
	browser.add_child(filters)
	browser.move_child(filters,0)
	ownership_filter = OptionButton.new()
	ownership_filter.accessibility_name = "Filter by ownership"
	for label in ["All items","Owned","For sale"]:
		ownership_filter.add_item(label)
	ownership_filter.item_selected.connect(func(_index):_refresh())
	filters.add_child(ownership_filter)
	search = LineEdit.new()
	search.placeholder_text = "Search items"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value):_refresh())
	filters.add_child(search)
	name_label = catalog.get_node("%SelectionTitle")
	empty_label = catalog.get_node("%EmptyLabel")
	price_label = UI.text("","MutedLabel")
	browser.add_child(price_label)
	browser.move_child(price_label,2)
	cache = ThumbnailCache.new()
	cache.max_entries=96
	add_child(cache)
	grid = catalog.get_node("%ItemGrid")
	grid.configure(cache,load("res://assets/cosmetics/ui/thumbnail_placeholder.svg"))
	grid.item_requested.connect(_select)
	parameter_panel = catalog.get_node("%ParameterPanel")
	parameter_panel.hide()
	parameter_panel.parameter_changed.connect(func(key: String, value: Variant):
		var values := session.selected_parameters.duplicate(true)
		values[key] = value
		session.select(session.selected_id, values))
	message_label = catalog.get_node("%StatusLabel")
	buy_button = catalog.get_node("%ApplyButton")
	buy_button.pressed.connect(_buy)
	var close := catalog.get_node("%CloseButton") as Button
	close.text = "Close"
	close.pressed.connect(func():close_requested.emit())
	var revert := catalog.get_node("%RevertButton") as Button
	revert.text = "Reset preview"
	revert.pressed.connect(func():
		session.cancel_preview()
		parameter_panel.hide()
		_refresh())
	balance_label = UI.text("","MutedLabel")
	balance_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	balance_label.size_flags_horizontal=Control.SIZE_SHRINK_END
	browser.add_child(balance_label)
	browser.move_child(balance_label,1)
	message_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	message_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	session.preview_changed.connect(_render_selection)
	session.preview_cancelled.connect(_restore_preview)
	session.state_changed.connect(_state_changed)
	_refresh()

func open_profile(snapshot: Dictionary, preview_avatar: Node3D = null, authoritative_economy_display: Dictionary = {}, initial_category := "") -> void:
	category=initial_category
	purchase_review=""
	ownership_filter.select(0)
	parameter_panel.hide()
	search.clear()
	catalog.show()
	session.open(snapshot)
	session.set_economy_display(authoritative_economy_display)
	if preview_avatar != null: preview.set_avatar(preview_avatar)
	else: _restore_preview()
	_refresh()
	search.grab_focus()

func accept_purchase(request_id: String, result: Dictionary, snapshot: Dictionary) -> void:
	session.accept_authoritative_result(request_id, result, snapshot)
	_refresh()

func _refresh() -> void:
	if grid == null: return
	var categories: Array = [category]
	if category in ["head","eyewear","neck"]:categories=["accessories"]
	if category in ["hoodies","jackets"]:categories=["tops"]
	var rows: Array = []
	for current in categories: rows.append_array(session.catalog.browse(current, search.text if search != null else ""))
	if category in ["head","eyewear","neck"]:
		rows=rows.filter(func(item):return item.get("slot","")==category)
	elif category=="hoodies":
		rows=rows.filter(func(item):return "hood" in str(item.name).to_lower() or "sweater" in str(item.name).to_lower())
	elif category=="jackets":
		rows=rows.filter(func(item):return "jacket" in str(item.name).to_lower() or "coat" in str(item.name).to_lower())
	var owned: Array = session.profile.get("owned_cosmetics", [])
	var filter := ownership_filter.selected
	rows=rows.filter(func(item):
		if filter==1:return item.id in owned
		if filter==2:return item.id not in owned and not bool(item.get("locked",false))
		return true)
	for item in rows:
		item.shop_tag = "Owned" if item.id in owned else "Locked" if item.get("locked",false) else "$%d" % int(item.get("price",0))
	for id in category_buttons:
		var button: Button=category_buttons[id]
		button.set_pressed_no_signal(id==category)
		button.theme_type_variation="PrimaryButton" if id==category else "Button"
	empty_label.text="No items match these filters."
	empty_label.visible=rows.is_empty()
	grid.show_items(rows, session.profile.get("avatar_cosmetics", {}), session.selected_id)

func _select(definition: Dictionary) -> void:
	purchase_review=""
	session.select(str(definition.get("id", "")))
	parameter_panel.show_schema(definition, session.selected_parameters)
	parameter_panel.visible=not definition.get("parameters",{}).is_empty()
	preview.focus_category(str(definition.get("category", "")), true)
	_refresh()

func _buy() -> void:
	if not request_id_factory.is_valid():
		message_label.text = "Purchase service unavailable"
		return
	if session.selected_state().status == "owned":
		session.request_equip(str(request_id_factory.call()))
	elif session.selected_state().status=="available":
		if purchase_review==session.selected_id:
			purchase_review=""
			session.request_purchase(str(request_id_factory.call()))
		else:
			purchase_review=session.selected_id
			_state_changed(session.view())

func _state_changed(state: Dictionary) -> void:
	var definition := session.catalog.item(state.selected_id)
	name_label.text = str(definition.get("name", "Select an item"))
	var purchase: Dictionary = state.purchase
	price_label.text = "Owned" if purchase.status=="owned" else str(purchase.get("message","")) if purchase.status=="locked" else "$%d" % int(purchase.get("price",0))
	price_label.visible = not definition.is_empty()
	balance_label.text = "Funds: unlimited (playtest)" if state.unlimited else "Balance: $%d" % int(state.balance)
	message_label.text = str(state.message) if not str(state.message).is_empty() else str(purchase.get("message", ""))
	buy_button.disabled = purchase.get("status") not in ["available", "owned"] or state.pending
	buy_button.text = "Processing…" if state.pending else ("Equip" if purchase.status == "owned" else ("Buy · $%d" % int(purchase.get("price",0)) if purchase.status=="available" else str(purchase.get("message","Select an item"))))
	if not purchase_review.is_empty() and purchase_review==state.selected_id and purchase.status=="available":
		buy_button.text="Confirm · $%d" % int(purchase.price)
		message_label.text="Buy %s?" % definition.name

func _restore_preview() -> void:
	preview.set_avatar(Renderer.render_avatar(session.profile.get("avatar_cosmetics", {}), session.catalog.items))

func _render_selection(intent: Dictionary) -> void:
	var state: Dictionary = session.profile.get("avatar_cosmetics", {}).duplicate(true)
	if not state.get("equipped") is Dictionary: state.equipped = {}
	var definition := session.catalog.item(intent.id)
	state.equipped[definition.slot] = {"id": intent.id, "parameters": intent.parameters}
	var hypothetical_owned: Array = session.profile.get("owned_cosmetics", []).duplicate()
	hypothetical_owned.append(intent.id)
	var resolved := Core.resolve(session.catalog.items, state, hypothetical_owned)
	if resolved.errors.is_empty(): preview.set_avatar(Renderer.render_avatar(resolved.state, session.catalog.items))
	else: message_label.text = "Preview conflicts with the current outfit"

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		session.cancel_preview()
		close_requested.emit()
		get_viewport().set_input_as_handled()
