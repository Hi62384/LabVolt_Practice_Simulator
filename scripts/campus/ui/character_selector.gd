extends Control
signal closed

const ThemeFactory = preload("res://scripts/ui/design_system/theme.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const Preview = preload("res://scripts/avatar_cosmetics/ui/live_preview.gd")
const Avatar = preload("res://scripts/avatar_model.gd")
const Names = preload("res://scripts/campus/social/public_profiles.gd")
const Coordinator = preload("res://scripts/avatar_cosmetics/core/coordinator.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const DEFAULT_MODEL := "res://assets/default_avatar.glb"
const CARD_WIDTH := 146
static var thumbnails := {}

var game: Node
var gallery: GridContainer
var gallery_scroll: ScrollContainer
var split: BoxContainer
var details: ScrollContainer
var preview: SubViewportContainer
var edit_button: Button
var name_field: LineEdit
var name_heading: Label
var message: Label
var actions: BoxContainer
var _thumbnail_stage: SubViewportContainer
var _queued: Array[Dictionary] = []
var _capturing := false
var _cosmetics := Coordinator.new()
var _preview_key := ""

func build(owner_game: Node) -> void:
	game = owner_game
	_cosmetics.load_catalog()
	theme = ThemeFactory.create()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("0b212e")
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 9)
	margin.add_child(page)
	_label(page, "Your Characters", 29)
	_label(page, "Choose a character or create one in the studio.", 14, T.MUTED)

	split = BoxContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	page.add_child(split)
	gallery_scroll = _scroll(split)
	gallery = GridContainer.new()
	gallery.add_theme_constant_override("h_separation", 8)
	gallery.add_theme_constant_override("v_separation", 8)
	gallery_scroll.add_child(gallery)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", T.surface(Color("112b3a"), Color("315266"), 8))
	split.add_child(card)
	details = _scroll(card)
	details.custom_minimum_size.x = 320
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 7)
	details.add_child(info)
	preview = Preview.new()
	preview.custom_minimum_size = Vector2(0, 292)
	info.add_child(preview)
	preview.use_native_resolution()
	var title_row := HBoxContainer.new()
	info.add_child(title_row)
	name_heading = _label(title_row, "", 21)
	title_row.add_child(_button("Reset camera", "refresh", preview.reset_camera))
	var rename := HBoxContainer.new()
	info.add_child(rename)
	name_field = LineEdit.new()
	name_field.placeholder_text = "Display name"
	name_field.max_length = 24
	name_field.size_flags_horizontal = SIZE_EXPAND_FILL
	name_field.custom_minimum_size.y = 36
	rename.add_child(name_field)
	name_field.text_submitted.connect(func(_value): _rename())
	rename.add_child(_button("Save name", "save", _rename))
	message = _label(info, "", 13, T.ACCENT)

	page.add_child(HSeparator.new())
	actions = BoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	var back := _button("Back", "back", func(): closed.emit())
	actions.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(spacer)
	edit_button = _button("Edit Character", "palette", _editor.bind(false))
	actions.add_child(edit_button)
	var create := _button("Create New Character", "plus", _editor.bind(true))
	create.theme_type_variation = "PrimaryButton"
	actions.add_child(create)

	if DisplayServer.get_name() != "headless":
		_thumbnail_stage = Preview.new()
		_thumbnail_stage.size = Vector2(272, 300)
		_thumbnail_stage.hide()
		add_child(_thumbnail_stage)
		_thumbnail_stage.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	resized.connect(_reflow)
	gallery_scroll.resized.connect(_columns)
	game.characters.changed.connect(_refresh)
	_refresh()
	_reflow()

func _reflow() -> void:
	var narrow := size.x < 670
	split.vertical = narrow
	details.custom_minimum_size.x = 0 if narrow else clampf(size.x * 0.36, 320, 520)
	actions.vertical = size.x < 460
	_columns()

func _columns() -> void:
	gallery.columns = maxi(1, int((gallery_scroll.size.x - 15) / (CARD_WIDTH + 8)))

func _refresh() -> void:
	_queued.clear()
	for child in gallery.get_children():
		gallery.remove_child(child)
		child.queue_free()
	var id: String = game.characters.selected
	var profiles: Array = game.characters.profiles.duplicate()
	if id.is_empty():
		profiles.push_front({"id": "", "name": "Starter appearance", "path": ""})
	var chosen := "Starter appearance"
	for profile in profiles:
		var active: bool = profile.id == id
		var display: String = profile.name if profile.id == "" else game.characters.display_name_for(profile.id, profile.name)
		var look := _saved_look(profile)
		if active:
			chosen = display
			if _preview_key != look.key:
				_preview_key = look.key
				preview.set_avatar(_avatar(look))
				preview.reset_camera()
				if is_instance_valid(preview.avatar):
					Avatar.animate(preview.avatar, false)
		_card(profile, display, active, look)
	name_heading.text = chosen
	name_field.text = game.characters.display_name()
	edit_button.disabled = id.is_empty()
	message.text = "Starter appearance" if id.is_empty() else "✓ Selected"

func _card(profile: Dictionary, display: String, active: bool, look: Dictionary) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 174)
	card.tooltip_text = display
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := Color("19463f") if active else Color("123141")
		if state == "hover":
			fill = fill.lightened(0.12)
		card.add_theme_stylebox_override(state, T.surface(fill, T.ACCENT if active else Color("315266"), 6))
	card.pressed.connect(_choose.bind(str(profile.id)))
	gallery.add_child(card)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.offset_left = 6
	column.offset_right = -6
	column.offset_top = 6
	column.offset_bottom = -6
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(column)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.size_flags_vertical = SIZE_EXPAND_FILL
	image.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(image)
	var caption := _label(column, ("✓ " if active else "") + display, 14)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_instance_valid(_thumbnail_stage):
		if thumbnails.has(look.key):
			image.texture = thumbnails[look.key]
		else:
			_queued.append({"image": image, "look": look})
			set_process(true)

func _process(_delta: float) -> void:
	if _capturing:
		return
	if _queued.is_empty():
		set_process(false)
		return
	var job: Dictionary = _queued.pop_front()
	if not is_instance_valid(job.image):
		return
	_capturing = true
	_thumbnail_stage.set_avatar(_avatar(job.look))
	_thumbnail_stage.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var snapshot: Image = _thumbnail_stage.viewport.get_texture().get_image()
	if snapshot != null and not snapshot.is_empty():
		if thumbnails.size() >= 96:
			thumbnails.erase(thumbnails.keys().front())
		var texture := ImageTexture.create_from_image(snapshot)
		thumbnails[job.look.key] = texture
		if is_instance_valid(job.image):
			job.image.texture = texture
	_thumbnail_stage.set_avatar(null)
	_capturing = false

func _saved_look(profile: Dictionary) -> Dictionary:
	var path: String = DEFAULT_MODEL if profile.id == "" else str(profile.path).path_join("avatar.glb")
	var appearance := {}
	if not profile.id.is_empty() and not _cosmetics.catalog.is_empty():
		var file := "user://electronics_%s.json" % str(profile.id).sha256_text().left(24)
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else {}
		if profile.id == game.characters.selected and game.front.in_game:
			saved = game.electronics.profile.data
		var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(profile.path).path_join("character.json")))
		if legacy is Dictionary:
			var resolved := _cosmetics.begin_preview(saved if saved is Dictionary else {}, legacy)
			appearance = resolved.state
	var key := "%s:%s" % [path, FileAccess.get_md5(path) if appearance.is_empty() else JSON.stringify(appearance).sha256_text()]
	return {"path": path, "appearance": appearance, "key": key}

func _avatar(look: Dictionary) -> Node3D:
	if not look.appearance.is_empty():
		return Renderer.render_avatar(look.appearance, _cosmetics.catalog)
	var avatar := Avatar.build(FileAccess.get_file_as_bytes(look.path))
	if avatar != null:
		avatar.rotation.y = PI if look.path == DEFAULT_MODEL else 0.0
	return avatar

func _choose(id: String) -> void:
	if id == game.characters.selected:
		return
	if game.front.in_game:
		message.text = "Return to the main menu to switch characters."
		return
	game.characters.select_profile(id)
	if game.characters.selected != id:
		message.text = str(game.characters.last_selection_result.get("error", "Could not select character."))

func _rename() -> void:
	var value := name_field.text.strip_edges()
	if value.is_empty() or Names.clean_name(value) != value:
		message.text = "Enter 1–24 characters without brackets or control characters."
		return
	if game.characters.rename_selected(value) == OK:
		game.ui.name_input.text = game.characters.display_name()
		message.text = "Display name saved"
	else:
		message.text = "Could not save display name"

func _editor(create_new: bool) -> void:
	var result: String = game.characters.edit(create_new)
	if not result.is_empty():
		message.text = result

func _scroll(parent: Node) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll

func _button(value: String, icon: String, callback: Callable) -> Button:
	var button := Widgets.action(value, icon, callback)
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_constant_override("icon_max_width", 17)
	return button

func _label(parent: Node, value: String, font_size: int, ink := T.INK) -> Label:
	var item := Widgets.text(value)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", ink)
	parent.add_child(item)
	return item
