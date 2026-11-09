class_name AvatarCosmeticCustomizerPanel
extends Control

const EditIntent = preload("res://scripts/avatar_cosmetics/ui/edit_intent_builder.gd")
const CosmeticCatalogAdapter = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const ItemGrid = preload("res://scripts/avatar_cosmetics/ui/item_grid.gd")
const ParameterPanel = preload("res://scripts/avatar_cosmetics/ui/parameter_panel.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const LivePreview = preload("res://scripts/avatar_cosmetics/ui/live_preview.gd")
const ThumbnailCache = preload("res://scripts/avatar_cosmetics/ui/thumbnail_cache.gd")
const StudioTheme = preload("res://scripts/ui/design_system/theme.gd")
const CATEGORY_MARKS := {"body":"◉", "faces":"☺", "hair":"≋", "facial_hair":"⌁", "tops":"♜", "bottoms":"Ⅱ", "shoes":"▰", "accessories":"✦"}

signal draft_changed(state: Dictionary)
signal equipment_intent_requested(intent: Dictionary)
signal validation_failed(errors: Array)
signal close_requested
signal apply_requested(intent: Dictionary)

@onready var category_bar: HFlowContainer = %CategoryBar
@onready var item_grid: ItemGrid = %ItemGrid
@onready var parameter_panel: ParameterPanel = %ParameterPanel
@onready var preview: LivePreview = %LivePreview
@onready var empty_label: Label = %EmptyLabel

var catalog: Dictionary = {}
var owned: Array = []
var draft: Dictionary = {"version": 1, "body": {}, "equipped": {}}
var initial_draft: Dictionary = {"version": 1, "body": {}, "equipped": {}}
var category := "body"
var selected_definition: Dictionary = {}
var avatar_renderer: Callable
var state_resolver: Callable
var creating := false
var _preview_dirty := false
var remove_accessory: Button

func _process(_delta: float) -> void:
	if _preview_dirty and is_visible_in_tree():
		_preview_dirty = false
		_rebuild_preview()

func _ready() -> void:
	theme = StudioTheme.create()
	preview.use_native_resolution()
	var poses := %PreviewPose as OptionButton
	for pose in ["Relaxed", "Fit check", "T-pose", "Walk"]:
		poses.add_item(pose)
	poses.select(0)
	poses.item_selected.connect(func(index: int): preview.set_pose(poses.get_item_text(index)))
	preview.set_pose(poses.get_item_text(0))
	for category_id in CosmeticCatalogAdapter.DISPLAY_CATEGORIES:
		var button := Button.new()
		button.text = CATEGORY_MARKS[category_id] + "  " + category_id.replace("_", " ").capitalize()
		button.custom_minimum_size.y = 36
		button.add_theme_font_size_override("font_size", 14)
		button.toggle_mode = true
		button.set_meta("category", category_id)
		button.pressed.connect(func(): select_category(category_id))
		category_bar.add_child(button)
	item_grid.item_requested.connect(_select_item)
	remove_accessory = Button.new()
	remove_accessory.text = "Remove accessory"
	remove_accessory.hide()
	var browser := %SelectionTitle.get_parent()
	browser.add_child(remove_accessory)
	browser.move_child(remove_accessory, %SelectionTitle.get_index()+1)
	remove_accessory.pressed.connect(func():_select_item(selected_definition))
	parameter_panel.parameter_changed.connect(_change_parameter)
	%CloseButton.pressed.connect(_cancel)
	%RevertButton.pressed.connect(revert_draft)
	%ApplyButton.pressed.connect(func():
		if creating or is_dirty():
			%StatusLabel.text = "Applying your look…"
			%ApplyButton.disabled = true
			apply_requested.emit(atomic_edit_intent()))
	validation_failed.connect(func(errors: Array): %StatusLabel.text = str(errors[0]) if not errors.is_empty() else "Could not update this look.")
	select_category("body")

func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		preview.reset_camera()
		get_viewport().set_input_as_handled()

func configure(catalog_value: Dictionary, owned_value: Array, state_value: Dictionary, thumbnail_cache: ThumbnailCache, renderer: Callable, resolver := Callable()) -> void:
	catalog = catalog_value
	owned = owned_value.duplicate()
	draft = state_value.duplicate(true)
	initial_draft = draft.duplicate(true)
	avatar_renderer = renderer
	state_resolver = resolver
	item_grid.configure(thumbnail_cache, load("res://assets/cosmetics/ui/thumbnail_placeholder.svg"))
	_preview_dirty = true
	_refresh()

func is_dirty() -> bool:
	return draft != initial_draft

func enable_creation() -> void:
	creating = true
	%ApplyButton.text = "Create Character"
	%ApplyButton.disabled = false

func atomic_edit_intent() -> Dictionary:
	return EditIntent.build(initial_draft, draft)

func revert_draft() -> void:
	draft = initial_draft.duplicate(true)
	selected_definition = {}
	draft_changed.emit(draft.duplicate(true))
	_preview_dirty = true
	_refresh()

func acknowledge_apply(success: bool, message := "", saved_draft: Dictionary = {}) -> void:
	if success:
		initial_draft = (draft if saved_draft.is_empty() else saved_draft).duplicate(true)
	%ApplyButton.disabled = not creating and not is_dirty()
	%StatusLabel.text = message if not message.is_empty() else ("Look saved." if success else "Could not save. Your changes are still here.")

func _cancel() -> void:
	if not is_dirty():
		close_requested.emit()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Leave the studio?"
	dialog.dialog_text = "Your saved look stays unchanged. Discard these preview changes?"
	dialog.ok_button_text = "Discard changes"
	dialog.confirmed.connect(func(): close_requested.emit(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func select_category(next_category: String) -> void:
	if next_category not in CosmeticCatalogAdapter.DISPLAY_CATEGORIES:
		return
	category = next_category
	selected_definition = {}
	for entry in draft.get("equipped", {}).values():
		var item: Dictionary = catalog.get(entry.get("id", ""), {})
		if item.get("category") == category:
			selected_definition = item
			break
	for button in category_bar.get_children():
		button.button_pressed = button.get_meta("category") == category
		button.theme_type_variation = "PrimaryButton" if button.button_pressed else "Button"
	_refresh()

func _refresh(rebuild_items := true) -> void:
	remove_accessory.visible = category=="accessories" and bool(selected_definition.get("allow_unequip",true)) and not CosmeticCatalogAdapter.equipped_slot_for(draft,str(selected_definition.get("id",""))).is_empty()
	if not is_node_ready():
		return
	%ApplyButton.disabled = not creating and not is_dirty()
	%RevertButton.disabled = not is_dirty()
	%StatusLabel.text = "Unsaved changes" if is_dirty() else ""
	%SelectionTitle.text = "Body customization" if category == "body" else str(selected_definition.get("name", category.replace("_", " ").capitalize()))
	if category == "body":
		item_grid.visible = false
		empty_label.visible = false
		parameter_panel.show_schema({"parameters": CosmeticCatalogAdapter.body_schema()}, draft.get("body", {}))
	else:
		var items := CosmeticCatalogAdapter.category_items(catalog, owned, category)
		item_grid.visible = true
		empty_label.visible = items.is_empty()
		empty_label.text = "No owned %s yet." % category.replace("_", " ")
		var selected_id := str(selected_definition.get("id", ""))
		if rebuild_items:
			item_grid.show_items(items, draft, selected_id)
		else:
			item_grid.update_selection(draft, selected_id)
		if selected_definition.is_empty():
			parameter_panel.show_schema({}, {})
		else:
			var slot := str(selected_definition.get("slot", ""))
			var values: Dictionary = draft.get("equipped", {}).get(slot, {}).get("parameters", {})
			parameter_panel.show_schema(selected_definition, values)

func _select_item(definition: Dictionary) -> void:
	var previous := draft.duplicate(true)
	selected_definition = definition
	var can_remove: bool = definition.category == "accessories" and bool(definition.get("allow_unequip", true))
	draft = CosmeticCatalogAdapter.toggle_selection(draft, definition, can_remove)
	if CosmeticCatalogAdapter.equipped_slot_for(draft, str(definition.get("id", ""))).is_empty():
		selected_definition = {}
	if _resolve_and_publish(previous):
		var slot := str(definition.get("slot", ""))
		if draft.get("equipped", {}).has(slot) and str(draft.equipped[slot].get("id", "")) == str(definition.get("id", "")):
			equipment_intent_requested.emit({"op": "equip", "id": str(definition.id), "parameters": draft.equipped[slot].parameters.duplicate(true)})

func _change_parameter(key: String, value: Variant) -> void:
	var previous := draft.duplicate(true)
	if category == "body":
		if not draft.get("body", {}) is Dictionary:
			draft.body = {}
		draft.body[key] = value
	else:
		var slot := str(selected_definition.get("slot", ""))
		if slot.is_empty() or not draft.get("equipped", {}).has(slot):
			return
		draft.equipped[slot].parameters[key] = value
	if _resolve_and_publish(previous, false, key) and category != "body":
		var slot := str(selected_definition.get("slot", ""))
		if draft.get("equipped", {}).has(slot):
			equipment_intent_requested.emit({"op": "equip", "id": str(selected_definition.id), "parameters": draft.equipped[slot].parameters.duplicate(true)})

func _resolve_and_publish(previous: Dictionary, refresh_controls := true, parameter := "") -> bool:
	if state_resolver.is_valid():
		var result: Variant = state_resolver.call(catalog, draft, owned)
		if not result is Dictionary or not result.get("state", {}) is Dictionary or not result.get("errors", []) is Array:
			draft = previous
			if CosmeticCatalogAdapter.equipped_slot_for(draft, str(selected_definition.get("id", ""))).is_empty(): selected_definition = {}
			validation_failed.emit(["Cosmetic resolver returned an invalid result"])
			_refresh()
			return false
		if not result.errors.is_empty():
			draft = previous
			if CosmeticCatalogAdapter.equipped_slot_for(draft, str(selected_definition.get("id", ""))).is_empty(): selected_definition = {}
			validation_failed.emit(result.errors.duplicate())
			_refresh()
			return false
		draft = result.state
	draft_changed.emit(draft.duplicate(true))
	if refresh_controls:
		_preview_dirty = true
		_refresh(false)
	else:
		# Keep the active slider/color picker alive throughout its gesture.
		%ApplyButton.disabled = not creating and not is_dirty()
		%RevertButton.disabled = not is_dirty()
		%StatusLabel.text = "Unsaved changes · Apply when you’re ready"
		if not _update_preview_parameter(parameter):
			_preview_dirty = true
	return true

func _update_preview_parameter(key: String) -> bool:
	if not is_instance_valid(preview.avatar) or not preview.avatar.has_meta("preview_colors"):
		return false
	if category == "body":
		match key:
			"skin":
				return Renderer.update_preview_color(preview.avatar, key, draft.body[key])
			"height":
				preview.avatar.scale = Vector3.ONE * float(draft.body.height)
				return true
			"head", "head_width", "head_height":
				var head := preview.avatar.get_node_or_null("Body/Head") as Node3D
				if head == null:
					return false
				var body: Dictionary = draft.body
				var has_fit := preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd").has_deformation(body)
				head.scale = float(body.head) * Vector3(float(body.head_width), float(body.head_height), 1.0)
				head.position.y = 1.56
				if has_fit:
					head.position.y += .44 * (float(body.torso_length) - 1.0) + .135 * (float(body.neck_length) - 1.0) + .205 * (head.scale.y - 1.0)
				return true
		return false
	if selected_definition.get("parameters", {}).get(key, {}).get("type") != "color":
		return false
	var entry: Dictionary = draft.equipped[str(selected_definition.slot)]
	return Renderer.update_preview_color(preview.avatar, "%s/%s" % [entry.id, key], entry.parameters[key])

func _rebuild_preview() -> void:
	if not avatar_renderer.is_valid():
		return
	var rendered: Variant = avatar_renderer.call(draft, catalog)
	if rendered is Node3D:
		preview.set_avatar(rendered)

