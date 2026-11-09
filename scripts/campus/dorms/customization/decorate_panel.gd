class_name DormDecoratePanel
extends Control

## Mounted only while the authenticated owner decorates their streamed room.
## `submit_edit(intent)` returns {ok,state/error}, or an empty dictionary while
## an RPC is pending; the coordinator then calls accept_result on reply.
signal closed
signal preview_changed(item: Dictionary, valid: bool)

const Rules = preload("res://scripts/campus/dorms/customization/placement_rules.gd")
const Edits = preload("res://scripts/campus/dorms/customization/room_edits.gd")
var submit_edit: Callable
var owned_options: Array[Dictionary] = [] # host-derived item ID, kind, display name
var room_side := "west"
var state: Dictionary = {"items":[], "styles":{}}
var draft: Dictionary = {}
var original: Dictionary = {}
var fine := false
var pending := false
var undo_intent: Dictionary = {}
var pending_undo: Dictionary = {}
var status: Label
var catalog_grid: GridContainer
var pick_button: Button
var place_button: Button
var _thumbnail_cache := {}

func open_room(authoritative_state: Dictionary, options: Array[Dictionary], side: String, sender: Callable) -> void:
	state = authoritative_state.duplicate(true)
	owned_options = options.duplicate(true)
	room_side = side
	submit_edit = sender
	visible = true
	_build()
	_refresh_catalog()

func close_room() -> void:
	cancel()
	visible = false
	closed.emit()

func cancel() -> void:
	draft = {}; original = {}
	preview_changed.emit({}, false)
	if is_instance_valid(status): status.text = "Selection cancelled"

func select_owned(option: Dictionary) -> void:
	if pending: return
	var id := str(option.get("id", ""))
	var kind := str(option.get("kind", ""))
	if id.is_empty() or not Rules.FOOTPRINTS.has(kind): return
	var placed: Dictionary = {}
	for item in state.get("items", []):
		if str(item.get("id", "")) == id: placed = item; break
	original = placed.duplicate(true)
	draft = placed.duplicate(true) if not placed.is_empty() else {"id":id, "kind":kind, "x":0.0, "z":0.0, "rotation":0}
	_preview()

func move_by(dx: float, dz: float) -> void:
	if draft.is_empty() or pending: return
	var step := 0.05 if fine else 0.25
	draft.x = snappedf(float(draft.x) + dx * step, step)
	draft.z = snappedf(float(draft.z) + dz * step, step)
	_preview()

func rotate_selected() -> void:
	if draft.is_empty() or pending: return
	draft.rotation = (int(draft.rotation) + 1) % 4
	_preview()

func place_selected() -> void:
	if draft.is_empty() or pending: return
	var op := "move" if not original.is_empty() else "place"
	_send({"op":op, "item":draft.duplicate(true)})

func pickup_selected() -> void:
	if original.is_empty() or pending: return
	_send({"op":"pickup", "id":str(original.id)})

func undo_last() -> void:
	if pending or undo_intent.is_empty(): return
	_send(undo_intent.duplicate(true))

func set_style(category: String, variant: String) -> void:
	if pending: return
	_send({"op":"style", "category":category, "variant":variant})

func reconcile(authoritative_state: Dictionary) -> void:
	state = authoritative_state.duplicate(true)
	cancel()
	_refresh_catalog()

func _send(intent: Dictionary) -> void:
	if not submit_edit.is_valid(): status.text = "Room edits are unavailable"; return
	pending_undo = _inverse(intent)
	pending = true
	var result: Dictionary = submit_edit.call(intent)
	if result.is_empty():
		status.text = "Saving…"
		return
	accept_result(result)

func accept_result(result: Dictionary) -> void:
	if not pending: return
	pending = false
	if result.get("ok", false) and result.get("state") is Dictionary:
		undo_intent = pending_undo.duplicate(true)
		reconcile(result.state)
		status.text = "Saved"
	else:
		# Host rejection restores its snapshot. Never leave a speculative ghost.
		if result.get("state") is Dictionary: state = result.state.duplicate(true)
		cancel()
		status.text = "Could not save: " + str(result.get("error", "rejected"))
	pending_undo = {}

func _inverse(intent: Dictionary) -> Dictionary:
	match str(intent.get("op", "")):
		"place": return {"op":"pickup", "id":str(intent.get("item", {}).get("id", ""))}
		"move", "pickup":
			var id := str(intent.get("id", intent.get("item", {}).get("id", "")))
			for item in state.get("items", []):
				if str(item.get("id", "")) == id: return {"op":"move" if intent.op == "move" else "place", "item":item.duplicate(true)}
		"style": return {"op":"style", "category":intent.category, "variant":state.get("styles", {}).get(intent.category, Edits.STYLE_CHOICES[intent.category][0])}
	return {}

func _preview() -> void:
	var candidate: Array = state.get("items", []).duplicate(true)
	var existing := Edits._index(candidate, str(draft.get("id", "")))
	if existing >= 0: candidate[existing] = draft.duplicate(true)
	else: candidate.append(draft.duplicate(true))
	var valid := Rules.validate(candidate, room_side).is_empty()
	preview_changed.emit(draft.duplicate(true), valid)
	status.text = "Ready to place" if valid else "Placement blocks the room"

func _build() -> void:
	for child in get_children(): child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 164)
	var box := PanelContainer.new(); add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new(); box.add_child(row)
	catalog_grid = GridContainer.new(); catalog_grid.columns = 8; row.add_child(catalog_grid)
	var controls := VBoxContainer.new(); row.add_child(controls)
	status = Label.new(); status.text = "Choose an owned item"; controls.add_child(status)
	var arrows := HBoxContainer.new(); controls.add_child(arrows)
	for direction in [["←",-1.0,0.0],["→",1.0,0.0],["↑",0.0,-1.0],["↓",0.0,1.0]]:
		var button := Button.new(); button.text = direction[0]; arrows.add_child(button)
		button.pressed.connect(func(): move_by(direction[1], direction[2]))
	var rotate := Button.new(); rotate.text = "Rotate"; controls.add_child(rotate); rotate.pressed.connect(rotate_selected)
	var fine_button := CheckButton.new(); fine_button.text = "Fine placement"; controls.add_child(fine_button)
	fine_button.toggled.connect(func(value: bool): fine = value)
	place_button = Button.new(); place_button.text = "Place / move"; controls.add_child(place_button); place_button.pressed.connect(place_selected)
	pick_button = Button.new(); pick_button.text = "Pick up"; controls.add_child(pick_button); pick_button.pressed.connect(pickup_selected)
	var cancel_button := Button.new(); cancel_button.text = "Cancel"; controls.add_child(cancel_button); cancel_button.pressed.connect(cancel)
	var undo_button := Button.new(); undo_button.text = "Undo"; controls.add_child(undo_button); undo_button.pressed.connect(undo_last)
	var close_button := Button.new(); close_button.text = "Done"; controls.add_child(close_button); close_button.pressed.connect(close_room)
	var styles := HBoxContainer.new(); row.add_child(styles)
	for category in Edits.STYLE_CHOICES:
		var choice := OptionButton.new(); choice.tooltip_text = str(category).capitalize(); styles.add_child(choice)
		for variant in Edits.STYLE_CHOICES[category]: choice.add_item(str(variant).replace("_", " "))
		choice.item_selected.connect(func(index: int): set_style(category, str(Edits.STYLE_CHOICES[category][index])))

func _refresh_catalog() -> void:
	if not is_instance_valid(catalog_grid): return
	for child in catalog_grid.get_children(): child.queue_free()
	for option in owned_options:
		var kind := str(option.get("kind", ""))
		if not Rules.FOOTPRINTS.has(kind): continue
		var button := Button.new(); button.custom_minimum_size = Vector2(72, 72)
		button.icon = _thumbnail(kind); button.expand_icon = true
		button.tooltip_text = str(option.get("name", kind))
		catalog_grid.add_child(button)
		button.pressed.connect(func(): select_owned(option))

func _thumbnail(kind: String) -> Texture2D:
	if _thumbnail_cache.has(kind): return _thumbnail_cache[kind]
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("e5e0d4"))
	var size: Vector2 = Rules.FOOTPRINTS[kind]
	var width := clampi(roundi(size.x * 25.0), 12, 48)
	var height := clampi(roundi(size.y * 20.0), 12, 48)
	var color := Color("668084") if kind in ["bed", "rug", "poster"] else Color("806b52")
	image.fill_rect(Rect2i(32-(width >> 1), 32-(height >> 1), width, height), color)
	var texture := ImageTexture.create_from_image(image)
	_thumbnail_cache[kind] = texture
	return texture
