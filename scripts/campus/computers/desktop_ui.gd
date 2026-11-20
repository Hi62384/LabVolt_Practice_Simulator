extends Control
## One local player's virtual computer. All persistent operations go through ComputerSessions.
signal closed

var session: Node
var game: Node
var snapshot: Dictionary = {}
var current_path := ""
var drafts: Dictionary = {}
var pending_new := false
var pending_rename := ""
var pending_folder_source := ""
var pending_folder_target := ""
var pending_paper_id := 0
var active_app := "Files"
var file_list: Tree
var project_tree: Tree
var editor: TextEdit
var path_field: LineEdit
var status_label: Label
var title_label: Label
var content: VBoxContainer
var autosave_timer: Timer
var saving_path := ""
var exit_requested := false
var share_monitor := false
var monitor_share: CheckButton
var parked_device := ""
var parked_cycle := -1
var parked_profile := ""
var parked_workspaces := {}
var folder_path := ""
var breadcrumbs: Label
var resize_key := ""
var resize_edges := Vector2.ZERO
var resize_start := Rect2()
var resize_pointer := Vector2.ZERO
var task_buttons := {}
var power_button: Button
var retry_documents_button: Button
var last_activity_signal := 0
var folder_button: Button
var delete_button: Button
var _rendering := false
var _portable_pending := false
var laptop_display_filter: ColorRect
var browser_surface: VBoxContainer
var pending_browser_download := false
var app_window_title: Label
var start_panel: PanelContainer
var start_button: Button
var app_window: PanelContainer
var workspace: Control
var windows := {}
var clock_label: Label
var desktop_status: Label
var app_names := ["Files","Text editor","Calculator","Browser","Code editor","Terminal","Settings","Recycle Bin"]
var pinned_apps := ["Files","Browser"]
var selected_shortcut := ""
var shortcuts_by_name := {}
var start_search: LineEdit
var start_account: Label
var start_results: VBoxContainer
var recent_files: Array[String]=[]
var wallpaper_panel: TextureRect
var style_choice := 0
var pending_open_path := ""
var _covered_viewport: Viewport
var _covered_viewport_disabled_3d := false
const Icon = preload("res://scripts/ui/design_system/widgets.gd")
const APP_ICONS := {"Files":"folder","Text editor":"save","Code editor":"code","Calculator":"meter","Browser":"network","Terminal":"code","Settings":"settings","Recycle Bin":"trash"}

func build(source: Node, owner_game: Node = null) -> void:
	session = source
	game = owner_game
	theme = preload("res://scripts/ui/design_system/theme.gd").create()
	for type in ["Button","OptionButton","LineEdit","TextEdit","Label","PopupMenu","ItemList"]:
		theme.set_font_size("font_size",type,14)
		for state in theme.get_stylebox_list(type):
			var style := theme.get_stylebox(state,type)
			style.content_margin_top=4.0
			style.content_margin_bottom=4.0
			style.content_margin_left=8.0
			style.content_margin_right=8.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if not session.desktop_changed.is_connected(_on_desktop_changed):
		session.desktop_changed.connect(_on_desktop_changed)
	if not session.operation_failed.is_connected(_on_operation_failed):
		session.operation_failed.connect(_on_operation_failed)
	autosave_timer=Timer.new()
	autosave_timer.one_shot=true
	autosave_timer.wait_time=.55
	autosave_timer.timeout.connect(_autosave)
	add_child(autosave_timer)
	if session.has_signal("power_changed"):session.power_changed.connect(_clear_powered_off)
	_build_shell()
	visibility_changed.connect(_update_world_rendering)
	tree_exiting.connect(_restore_world_rendering)

func _update_world_rendering() -> void:
	if not is_visible_in_tree():
		_restore_world_rendering()
		return
	if not is_instance_valid(game) or _covered_viewport != null:
		return
	# The opaque, full-screen desktop covers the world. Keep gameplay processing behind it.
	_covered_viewport = game.get_viewport()
	_covered_viewport_disabled_3d = _covered_viewport.disable_3d
	_covered_viewport.disable_3d = true

func _restore_world_rendering() -> void:
	if is_instance_valid(_covered_viewport):
		_covered_viewport.disable_3d = _covered_viewport_disabled_3d
	_covered_viewport = null

func build_monitor_preview() -> void:
	theme=preload("res://scripts/ui/design_system/theme.gd").create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell(true)

func _build_shell(preview := false) -> void:
	var backdrop := TextureRect.new()
	wallpaper_panel=backdrop
	var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	backdrop.texture = ImageTexture.create_from_image(pixel)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var waves := Shader.new()
	waves.code = """
shader_type canvas_item;

vec3 ribbon(vec2 uv, float center, float width, float shine) {
	float distance_to_edge = uv.y - center;
	float band = 1.0 - smoothstep(0.0, width, abs(distance_to_edge));
	float halo = exp(-abs(distance_to_edge) * 33.0);
	float seam = exp(-abs(distance_to_edge) * 850.0);
	return vec3(0.0, .23, .34) * band * .56
		+ vec3(0.0, .48, .51) * halo * shine
		+ vec3(.17, .92, .88) * seam * shine;
}

void fragment() {
	vec2 uv = UV;
	vec3 base = mix(vec3(.016, .059, .125), vec3(.013, .145, .212), 1.0 - uv.y);
	base *= .70 + .42 * exp(-length(uv - vec2(.62,.24)) * 1.8);
	float crest = .79 + .115 * sin(uv.x * 6.0 - 1.0) - .14 * uv.x;
	float sweep = .52 + .11 * sin(uv.x * 5.5 + .4) - .37 * uv.x;
	float glow = .14 + .74 * exp(-pow((uv.x - .49) * 5.9, 2.0));
	vec3 light = ribbon(uv, crest, .071, glow);
	light += ribbon(uv, sweep, .093, .12 + .64 * smoothstep(.38, .89, uv.x));
	light += ribbon(uv, crest + .13 - .035 * uv.x, .045, .09);
	COLOR = vec4((base + light) * COLOR.rgb, 1.0);
}
"""
	var wallpaper_shader:=ShaderMaterial.new()
	wallpaper_shader.shader=waves
	backdrop.material=wallpaper_shader
	add_child(backdrop)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	desktop_status=Label.new()
	desktop_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	workspace=Control.new()
	workspace.clip_contents=true
	workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	workspace.resized.connect(_fit_windows)
	workspace.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:_select_shortcut(""))
	var brand:=Label.new()
	brand.text="Campus OS"
	brand.add_theme_color_override("font_color",Color("e4f4ff"))
	brand.add_theme_font_size_override("font_size",22)
	brand.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	brand.mouse_filter=Control.MOUSE_FILTER_IGNORE
	workspace.add_child(brand)
	brand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	brand.offset_left=-188;brand.offset_top=-49;brand.offset_right=-22
	var shortcuts := GridContainer.new()
	shortcuts.columns=2
	shortcuts.position=Vector2(18,8)
	shortcuts.add_theme_constant_override("h_separation", 12)
	shortcuts.add_theme_constant_override("v_separation", 6)
	workspace.add_child(shortcuts)
	for name in app_names:
		var shortcut := Button.new()
		shortcut.text=name
		shortcut.flat=true
		shortcut.toggle_mode=true
		shortcut.pressed.connect(func():_select_shortcut(name))
		shortcut.gui_input.connect(func(event):_desktop_shortcut_input(name,shortcut,event))
		shortcuts_by_name[name]=shortcut
		shortcut.icon=_desktop_app_icon(name)
		shortcut.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		shortcut.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		shortcut.add_theme_constant_override("icon_max_width",48)
		shortcut.flat=true
		shortcut.custom_minimum_size=Vector2(104,70)
		shortcut.add_theme_color_override("font_shadow_color", Color("000000b8"))
		shortcut.add_theme_constant_override("shadow_offset_y", 1)
		shortcuts.add_child(shortcut)
	var taskbar := HBoxContainer.new()
	taskbar.add_theme_constant_override("separation", 8)
	taskbar.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("102936"), Color("385a68"), 10))
	var tray_shell := PanelContainer.new()
	tray_shell.custom_minimum_size.y=53
	var tray_style := StyleBoxFlat.new()
	tray_style.bg_color=Color("061b2eee")
	tray_style.set_corner_radius_all(16)
	tray_style.border_color=Color("38596c")
	tray_style.set_border_width_all(1)
	tray_style.content_margin_left=6
	tray_style.content_margin_right=10
	tray_style.content_margin_top=3
	tray_style.content_margin_bottom=3
	tray_shell.add_theme_stylebox_override("panel",tray_style)
	var tray_margin:=MarginContainer.new()
	tray_margin.add_theme_constant_override("margin_left",12)
	tray_margin.add_theme_constant_override("margin_right",12)
	tray_margin.add_theme_constant_override("margin_bottom",8)
	root.add_child(tray_margin)
	tray_margin.add_child(tray_shell)
	tray_shell.add_child(taskbar)
	start_button = _button("Start", _toggle_start)
	start_button.icon=Icon.icon("course")
	start_button.custom_minimum_size.x = 85
	taskbar.add_child(start_button)
	for name in app_names:
		var app_name: String = str(name)
		var app_button := _button("",func():_switch_app(app_name))
		app_button.icon=shortcuts_by_name[name].icon
		app_button.add_theme_constant_override("icon_max_width",25)
		app_button.custom_minimum_size.x=34
		app_button.tooltip_text=name
		app_button.accessibility_name=name
		app_button.visible=name in pinned_apps
		task_buttons[name]=app_button
		taskbar.add_child(app_button)
	taskbar.add_child(desktop_status)
	clock_label = Label.new()
	clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	taskbar.add_child(clock_label)
	_update_clock()
	if preview:return
	var clock_tick := Timer.new()
	clock_tick.wait_time=1.0
	clock_tick.autostart=true
	clock_tick.timeout.connect(_update_clock)
	add_child(clock_tick)
	start_panel = PanelContainer.new()
	start_panel.hide()
	start_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	start_panel.offset_left=13
	start_panel.offset_right=525
	start_panel.offset_bottom=-72
	start_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	start_panel.offset_top=-482
	start_panel.custom_minimum_size=Vector2(390,345)
	start_panel.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("092b40f5"), Color("2eb9ce"), 18))
	add_child(start_panel)
	var start_list := VBoxContainer.new()
	start_panel.add_child(start_list)
	start_list.add_theme_constant_override("separation", 10)
	var heading_row := HBoxContainer.new()
	start_list.add_child(heading_row)
	var emblem := TextureRect.new()
	emblem.texture = Icon.icon("course")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(29, 29)
	emblem.modulate = Color("62edf6")
	heading_row.add_child(emblem)
	var start_heading := Label.new()
	start_heading.text = "Campus OS"
	start_heading.add_theme_font_size_override("font_size", 23)
	heading_row.add_child(start_heading)
	start_search=LineEdit.new()
	start_search.placeholder_text="Search apps and files"
	start_search.right_icon=Icon.icon("search")
	start_search.custom_minimum_size.y=36
	start_search.text_changed.connect(_update_start_results)
	start_list.add_child(start_search)
	start_account=Label.new()
	start_account.add_theme_color_override("font_color",Color("aac1ce"))
	var start_scroll:=ScrollContainer.new()
	start_scroll.custom_minimum_size.y=153
	start_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	start_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	start_list.add_child(start_scroll)
	start_results=VBoxContainer.new()
	start_results.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	start_scroll.add_child(start_results)
	_update_start_results("")
	retry_documents_button=_button("Retry local save",func():session.retry_local_documents())
	retry_documents_button.hide()
	start_list.add_child(retry_documents_button)
	start_list.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	start_list.add_child(footer)
	start_account.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(start_account)
	power_button=_button("Power off",_power_off)
	power_button.icon=Icon.icon("power")
	power_button.hide()
	footer.add_child(power_button)
	footer.add_child(_button("Leave computer",_request_exit))
	monitor_share = CheckButton.new()
	monitor_share.text = "Share screen nearby"
	monitor_share.tooltip_text = "Nearby players can see the desktop, including open documents."
	monitor_share.hide()
	monitor_share.toggled.connect(func(value: bool): share_monitor = value)
	start_list.add_child(monitor_share)

	# The filter is confined to this desktop canvas and never changes the
	# player's global rendering settings. It does not intercept UI input.
	laptop_display_filter = ColorRect.new()
	laptop_display_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	laptop_display_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen_texture : hint_screen_texture, filter_nearest;\nuniform float display_scale = 1.0;\nvoid fragment() { vec2 pixels = max(vec2(1.0), 1.0 / SCREEN_PIXEL_SIZE * display_scale); vec2 uv = (floor(SCREEN_UV * pixels) + vec2(0.5)) / pixels; COLOR = texture(screen_texture, uv); }"
	var filter_material := ShaderMaterial.new()
	filter_material.shader = shader
	laptop_display_filter.material = filter_material
	laptop_display_filter.visible = false
	add_child(laptop_display_filter)
	status_label=desktop_status

func _desktop_app_icon(name: String) -> Texture2D:
	var tile_colors := {"Files":"1c6197", "Text editor":"1379b9",
		"Calculator":"247794", "Browser":"0986cf", "Code editor":"3c459e",
		"Terminal":"365367", "Settings":"5279a0", "Recycle Bin":"079482"}
	var tile := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56"><defs><linearGradient id="g" x2="0" y2="1"><stop stop-color="#%s"/><stop offset="1" stop-color="#10223b"/></linearGradient></defs><rect x="1" y="1" width="54" height="54" rx="13" fill="url(#g)" stroke="#95ddff" stroke-opacity=".55"/><path d="M13 7H43" stroke="white" stroke-opacity=".2" stroke-linecap="round"/></svg>'
	tile.load_svg_from_string(svg % tile_colors[name])
	var glyph := Icon.icon(APP_ICONS[name]).get_image()
	glyph.convert(Image.FORMAT_RGBA8)
	glyph.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	if name == "Files":
		for y in glyph.get_height():
			for x in glyph.get_width():
				var pixel := glyph.get_pixel(x, y)
				glyph.set_pixel(x, y, Color(1.0, .76, .30, pixel.a))
	tile.blend_rect(glyph, Rect2i(0, 0, 32, 32), Vector2i(12, 12))
	return ImageTexture.create_from_image(tile)

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(54, 28)
	button.pressed.connect(action)
	return button

func _update_clock() -> void:
	if is_instance_valid(clock_label):clock_label.text=Time.get_time_string_from_system().left(5)

func _window_key(name: String) -> String:
	return name

func _create_window(key: String,name: String) -> Dictionary:
	var window := PanelContainer.new()
	window.set_meta("desktop_app",key)
	window.clip_contents=true
	var frame := StyleBoxFlat.new()
	frame.bg_color=Color("052536fa")
	frame.border_color=Color("34d9e3")
	frame.anti_aliasing = true
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(16)
	frame.set_content_margin_all(10)
	frame.shadow_color=Color("0ab4c64a")
	frame.shadow_size=12
	window.add_theme_stylebox_override("panel",frame)
	window.theme = _application_theme()
	window.add_theme_constant_override("separation",5)
	workspace.add_child(window)
	if window_sheen==null:
		var gradient:=Gradient.new()
		gradient.offsets=PackedFloat32Array([0.0,.16,.7,1.0])
		gradient.colors=PackedColorArray([Color("20a6be42"),Color("0a344608"),Color("0a344600"),Color("16bdd329")])
		window_sheen=GradientTexture2D.new()
		window_sheen.gradient=gradient
		window_sheen.fill_to=Vector2(0,1)
	var sheen:=TextureRect.new()
	sheen.texture=window_sheen
	sheen.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	sheen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	window.add_child(sheen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	window.add_child(column)
	var bar := HBoxContainer.new()
	bar.gui_input.connect(func(event: InputEvent): _window_drag(key, event))
	column.add_child(bar)
	var badge := TextureRect.new()
	badge.texture=shortcuts_by_name[name].icon
	badge.custom_minimum_size=Vector2(23,23)
	badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bar.add_child(badge)
	var title := Label.new()
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter=Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape=Control.CURSOR_MOVE
	title.gui_input.connect(func(event: InputEvent):_window_drag(key,event))
	bar.add_child(title)
	for spec in [["—","Minimize",func():_minimize_window(key)],["□","Maximize or restore",func():_toggle_maximize(key)],["×","Close",func():_close_window(key)]]:
		var control := Button.new()
		control.text=spec[0]
		control.tooltip_text=spec[1]
		control.accessibility_name=spec[1]
		control.custom_minimum_size=Vector2(31,23)
		control.pressed.connect(spec[2])
		bar.add_child(control)
	var area := VBoxContainer.new()
	area.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(area)
	var message := Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size",12)
	column.add_child(message)
	var base := Vector2(830,575) if name in ["Files","Text editor","Code editor","Browser","Terminal","Recycle Bin","Settings"] else Vector2(338,460)
	var offset := float(windows.size()%5)*24.0
	window.position=Vector2(maxf(155.0,workspace.size.x-base.x-12) if name=="Calculator" else 210+offset,12+offset)
	var state := {"shell":window,"title":title,"content":area,"status":message,"app":name,"built":false,"maximized":false,"rect":Rect2(window.position,base),"restore":Rect2(window.position,base)}
	windows[key]=state
	_fit_windows()
	return state

var application_theme: Theme
var window_sheen: GradientTexture2D

func _application_theme() -> Theme:
	if application_theme != null: return application_theme
	application_theme = theme.duplicate()
	var tokens = preload("res://scripts/ui/design_system/tokens.gd")
	for style in [["normal","104054","28677b"],["hover","1a5365","46bdd0"],["pressed","116578","55d8df"],["disabled","102d40","244251"]]:
		var button_skin: StyleBoxFlat=tokens.surface(Color(style[1]),Color(style[2]),9)
		button_skin.content_margin_top=4
		button_skin.content_margin_bottom=4
		button_skin.content_margin_left=8
		button_skin.content_margin_right=8
		application_theme.set_stylebox(style[0],"Button",button_skin)
		var active_skin: StyleBoxFlat=button_skin.duplicate()
		if style[0]!="disabled":
			active_skin.bg_color=Color("075563") if style[0]=="normal" else Color("087583")
			active_skin.border_color=Color("29c9d2")
		application_theme.set_stylebox(style[0],"PrimaryButton",active_skin)
	for style in ["tab_selected","tab_hovered","tab_unselected"]:
		var selected: bool=style!="tab_unselected"
		application_theme.set_stylebox(style,"TabBar",tokens.surface(Color("125469" if selected else "082b3d"),Color("35b8c7" if selected else "1b485a"),8))
	for style in ["title_button_normal","title_button_hover","title_button_pressed"]:
		application_theme.set_stylebox(style,"Tree",tokens.surface(Color("082b3d"),Color("163d50"),0))
	application_theme.set_color("title_button_color","Tree",Color("b0d4e2"))
	application_theme.set_color("current_line_color","CodeEdit",Color("16485d63"))
	application_theme.set_color("line_number_color","CodeEdit",Color("779baa"))
	for control in ["ItemList", "Tree"]:
		application_theme.set_stylebox("panel", control, tokens.surface(Color("041e2f"), Color("255e73"), 10))
		application_theme.set_stylebox("selected", control, tokens.surface(Color("135366"), Color("36a6be"), 6))
	for control in ["TextEdit", "CodeEdit", "LineEdit"]:
		application_theme.set_stylebox("normal", control, tokens.surface(Color("031e2e"), Color("2e7f91"), 8))
		application_theme.set_color("caret_color", control, Color("71f8ff"))
		application_theme.set_stylebox("focus",control,tokens.surface(Color.TRANSPARENT,Color("30c9d5"),8))
	return application_theme

func _recoverable_window_position(point: Vector2, extent: Vector2) -> Vector2:
	var reachable := minf(140.0, minf(extent.x, workspace.size.x))
	return point.clamp(Vector2(reachable - extent.x, -12.0), Vector2(workspace.size.x - reachable, maxf(0.0, workspace.size.y - 29.0)))

func _fit_windows() -> void:
	if workspace.size.x<32 or workspace.size.y<32:return
	for state in windows.values():
		var window: PanelContainer=state.shell
		if state.maximized:
			var frame:=window.get_theme_stylebox("panel") as StyleBoxFlat
			frame.set_corner_radius_all(0)
			frame.shadow_size=0
			window.position=Vector2.ZERO
			window.size=workspace.size
		else:
			var frame:=window.get_theme_stylebox("panel") as StyleBoxFlat
			frame.set_corner_radius_all(16)
			frame.shadow_size=12
			var rect: Rect2=state.rect
			window.size=rect.size.max(window.get_combined_minimum_size()).min(workspace.size)
			window.position=_recoverable_window_position(rect.position,window.size)

func _window_drag(key: String,event: InputEvent) -> void:
	var state: Dictionary=windows.get(key,{})
	if state.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_focus_window(key)
		if event.double_click:_toggle_maximize(key)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not state.maximized:
		var window: PanelContainer=state.shell
		window.position=_recoverable_window_position(window.position+event.relative,window.size)
		state.rect=Rect2(window.position,window.size)

func _toggle_maximize(key: String) -> void:
	var state: Dictionary=windows[key]
	var window: PanelContainer=state.shell
	if state.maximized:
		state.rect=state.restore
	else:
		state.restore=Rect2(window.position,window.size)
	state.maximized=not state.maximized
	_fit_windows()

func _minimize_window(key: String) -> void:
	windows[key].shell.hide()
	if app_window==windows[key].shell:_focus_last_window()

func _close_window(key: String) -> void:
	if not windows.has(key):return
	var state: Dictionary=windows[key]
	if key in ["Text editor","Code editor"] and app_window==state.shell:_capture_draft()
	if key=="Browser" and is_instance_valid(browser_surface):
		browser_surface.close_session()
		browser_surface=null
	var focused: bool=app_window==state.shell
	state.shell.hide()
	state.shell.queue_free()
	windows.erase(key)
	task_buttons[state.app].visible=state.app in pinned_apps
	if focused:_focus_last_window()

func _focus_last_window() -> void:
	for i in range(workspace.get_child_count()-1,-1,-1):
		var candidate: Control=workspace.get_child(i)
		if candidate.has_meta("desktop_app") and candidate.visible:
			_focus_window(candidate.get_meta("desktop_app"))
			return
	app_window=null
	status_label=desktop_status
	_bind_editor({})

func _bind_editor(state: Dictionary) -> void:
	file_list=state.get("file_list")
	project_tree=state.get("project_tree")
	breadcrumbs=state.get("breadcrumbs")
	editor=state.get("editor")
	path_field=state.get("path_field")
	folder_button=state.get("folder_button")
	delete_button=state.get("delete_button")

func _focus_window(key: String) -> void:
	if not windows.has(key):return
	var state: Dictionary=windows[key]
	if is_instance_valid(app_window) and app_window!=state.shell:
		var previous:=str(app_window.get_meta("desktop_app",""))
		if windows.has(previous):
			windows[previous].path=current_path
			windows[previous].folder=folder_path
	elif not is_instance_valid(app_window):
		current_path=""
		folder_path=""
	if app_window!=state.shell:
		current_path=str(state.get("path",""))
		folder_path=str(state.get("folder",""))
	app_window=state.shell
	app_window.show()
	app_window.move_to_front()
	active_app=state.app
	app_window_title=state.title
	content=state.content
	status_label=state.status
	_bind_editor(state)

func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_bind_editor({})

func _switch_app(name: String) -> void:
	if name not in app_names: return
	_capture_draft()
	var key := _window_key(name)
	var new_window:=not windows.has(key)
	var state: Dictionary=_create_window(key,name) if new_window else windows[key]
	var rebuild: bool=not state.built or state.app!=name or name in ["Recycle Bin"]
	if state.app!=name:task_buttons[state.app].visible=state.app in pinned_apps
	state.app=name
	task_buttons[name].show()
	_focus_window(key)
	app_window_title.text=name
	if is_instance_valid(start_panel):start_panel.hide()
	if not rebuild:
		if key in ["Text editor","Code editor","Files"]:
			_refresh_file_list()
			_load_editor()
		return
	_clear_content()
	state.built=true
	if name == "Files" or name == "Text editor" or name == "Code editor":
		_build_files(name)
		state.merge({"file_list":file_list,"project_tree":project_tree,"breadcrumbs":breadcrumbs,"editor":editor,"path_field":path_field,"folder_button":folder_button,"delete_button":delete_button},true)
	elif name == "Calculator":
		var calculator := preload("res://scripts/scientific_calculator.gd").new()
		calculator.campus_style = true
		calculator.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		content.add_child(calculator)
		for node in calculator.find_children("*","Button",true,false):
			node.custom_minimum_size.y=28
		_fit_windows.call_deferred()
	elif name == "Browser":
		browser_surface=preload("res://scripts/campus/computers/browser_surface.gd").new()
		browser_surface.game=game
		browser_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(browser_surface)
		var files: Array=[]
		for row in _file_rows():
			if row is Dictionary:
				var text_value:=str(row.get("text",""))
				files.append({"kind":"virtual_file","name":str(row.get("path","")),"bytes":text_value.to_utf8_buffer().size()})
		browser_surface.configure("computer",str(snapshot.get("station","")),str(snapshot.get("lease","")),files)
		browser_surface.attachment_loader=_browser_attachment
		browser_surface.assistant_virtual_save=_browser_save_answer
		if snapshot.get("public_device",false):browser_surface.virtual_download_save=_browser_save_download
		status_label.visible=not browser_surface.call("renderer_available")
		status_label.text="Embedded browser unavailable on this device." if status_label.visible else ""
	elif name=="Terminal":
		var terminal:=preload("res://scripts/campus/computers/virtual_terminal.gd").new()
		terminal.size_flags_vertical=Control.SIZE_EXPAND_FILL
		content.add_child(terminal)
		terminal.build(self)
	elif name=="Settings":_build_os_settings()
	elif name=="Recycle Bin":_build_recycle_bin()
	if new_window:
		var initial: Rect2=state.rect
		initial.size=initial.size.max(state.shell.get_combined_minimum_size()).min(workspace.size)
		initial.position=initial.position.clamp(Vector2.ZERO,(workspace.size-initial.size).max(Vector2.ZERO))
		state.rect=initial
		state.restore=initial
		_fit_windows()

func _select_shortcut(name: String) -> void:
	selected_shortcut=name
	for app in shortcuts_by_name:
		shortcuts_by_name[app].set_pressed_no_signal(app==name)

func _desktop_shortcut_input(name: String, button: Button, event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index==MOUSE_BUTTON_LEFT and event.double_click:
		_switch_app(name);button.accept_event()
	elif event.button_index==MOUSE_BUTTON_RIGHT:
		_select_shortcut(name)
		var menu:=PopupMenu.new()
		add_child(menu)
		menu.add_item("Open",0)
		menu.add_item("Unpin from taskbar" if name in pinned_apps else "Pin to taskbar",1)
		menu.add_item("Properties",2)
		menu.id_pressed.connect(func(id):
			if id==0:_switch_app(name)
			elif id==1:_toggle_pin(name)
			elif id==2:_message(name,_app_description(name)))
		menu.popup_hide.connect(menu.queue_free)
		menu.position=Vector2i(DisplayServer.mouse_get_position())
		menu.popup()
		button.accept_event()

func _app_description(name: String) -> String:
	return {"Files":"Browse and organize virtual workspace files.","Text editor":"Write and autosave plain text notes.","Code editor":"Edit source files and run numeric CampusScript programs.","Calculator":"Scientific calculator for campus work.","Browser":"Open websites in the isolated Chromium session.","Terminal":"Work with virtual files using commands.","Settings":"Customize this Campus OS desktop."}.get(name,"Campus OS application")

func _toggle_pin(name: String) -> void:
	if name in pinned_apps:pinned_apps.erase(name)
	else:pinned_apps.append(name)
	task_buttons[name].visible=name in pinned_apps or windows.has(name)
	_save_os_preferences()

func _toggle_start(force_open := false) -> void:
	if not is_instance_valid(start_panel):return
	start_panel.visible=force_open or not start_panel.visible
	if start_panel.visible:
		start_panel.move_to_front()
		var profiles: Dictionary=game.session.roster if is_instance_valid(game) else {}
		start_account.text=str(profiles.get(multiplayer.get_unique_id(),{}).get("name","Local workspace"))
		_update_start_results(start_search.text)
		start_search.grab_focus()

func _update_start_results(query: String) -> void:
	for child in start_results.get_children():
		start_results.remove_child(child)
		child.queue_free()
	var needle:=query.strip_edges().to_lower()
	var launchers:=GridContainer.new()
	launchers.columns=5
	launchers.add_theme_constant_override("h_separation", 5)
	launchers.add_theme_constant_override("v_separation", 7)
	start_results.add_child(launchers)
	for name in app_names:
		if not needle.is_empty() and not name.to_lower().contains(needle):continue
		var launch:=_button(name,func():_switch_app(name);start_panel.hide())
		launch.icon=shortcuts_by_name[name].icon
		launch.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		launch.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		launch.add_theme_constant_override("icon_max_width", 38)
		launch.add_theme_font_size_override("font_size", 12)
		launch.custom_minimum_size=Vector2(87,66)
		launch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		launch.flat=true
		launchers.add_child(launch)
	var paths: Array=recent_files if needle.is_empty() else _file_rows().map(func(row):return str(row.path))
	var matches:=0
	for path in paths:
		if matches>=5:break
		if not str(path).to_lower().contains(needle) or _file(path).is_empty():continue
		start_results.add_child(_button(str(path),func():_open_path(path);start_panel.hide()))
		matches+=1

func _build_recycle_bin() -> void:
	if not snapshot.get("recycle_available",false):
		var notice:=Label.new()
		notice.text="Connect to a workstation using its internal drive to access Recycle Bin."
		notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		content.add_child(notice)
		return
	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	var search := LineEdit.new()
	search.placeholder_text = "Search deleted items"
	search.right_icon=Icon.icon("search")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(search)
	var sort := OptionButton.new()
	sort.add_item("Date deleted")
	sort.add_item("Name")
	toolbar.add_child(sort)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	var entries := Tree.new()
	entries.columns = 4
	entries.hide_root = true
	entries.column_titles_visible = true
	entries.set_column_title(0, "Name")
	entries.set_column_title(1, "Original location")
	entries.set_column_title(2, "Date deleted")
	entries.set_column_title(3,"Size")
	entries.set_column_custom_minimum_width(3,62)
	entries.set_column_expand(3,false)
	entries.custom_minimum_size = Vector2(310, 140)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(entries)
	var details_panel:=PanelContainer.new()
	details_panel.custom_minimum_size.x=180
	details_panel.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("082b3d"),Color("27596b"),10))
	split.add_child(details_panel)
	var details := Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_panel.add_child(details)
	var tools := HBoxContainer.new()
	content.add_child(tools)
	var restore := _button("Restore",func():
		var selected := entries.get_selected()
		if selected != null: _send({"op":"untrash","item":selected.get_metadata(0).id}))
	restore.icon=Icon.icon("refresh")
	restore.theme_type_variation="PrimaryButton"
	tools.add_child(restore)
	var purge := _button("Delete permanently",func():
		var selected := entries.get_selected()
		if selected != null:
			var item: String = selected.get_metadata(0).id
			_confirm_action("Delete this recycled item permanently?",func():_send({"op":"purge","item":item})))
	purge.icon=Icon.icon("trash")
	tools.add_child(purge)
	var empty := _button("Empty Recycle Bin",func():
		_confirm_action("Delete all recycled items permanently?",func():_send({"op":"purge"})))
	empty.icon=Icon.icon("trash")
	tools.add_child(empty)
	var items: Array = snapshot.get("recycle", []).duplicate()
	var update := func(_query: String = ""):
		entries.clear()
		var root_item := entries.create_item()
		if sort.selected == 1:
			items.sort_custom(func(left, right): return str(left.path).get_file().nocasecmp_to(str(right.path).get_file()) < 0)
		else:
			items.sort_custom(func(left, right): return int(left.deleted) > int(right.deleted))
		for item in items:
			var path := str(item.path)
			if not path.to_lower().contains(search.text.strip_edges().to_lower()): continue
			var row := entries.create_item(root_item)
			row.set_text(0, path.get_file())
			row.set_icon(0, Icon.icon("folder" if item.get("folder",false) else "course"))
			row.set_text(1, "/" + _parent_folder(path))
			row.set_text(2, Time.get_datetime_string_from_unix_time(int(item.deleted), true).left(16))
			row.set_text(3,String.humanize_size(int(item.bytes)) if item.has("bytes") else "—")
			row.set_metadata(0, item)
		details.text = "Recycle Bin is empty" if items.is_empty() else "Select an item"
		restore.disabled = true
		purge.disabled = true
		empty.disabled = items.is_empty()
	search.text_changed.connect(update)
	sort.item_selected.connect(func(_index: int): update.call())
	entries.item_selected.connect(func():
		var selected := entries.get_selected()
		if selected == null: return
		details.text = "%s\n\nOriginal location   %s\nDate deleted   %s\nSize   %s" % [selected.get_text(0),selected.get_text(1),selected.get_text(2),selected.get_text(3)]
		restore.disabled = false
		purge.disabled = false)
	update.call()

func _confirm_action(message: String, action: Callable) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.dialog_text=message
	add_child(dialog)
	dialog.confirmed.connect(func():dialog.hide();action.call();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _name_dialog(heading: String, initial: String, submitted: Callable) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title=heading
	dialog.ok_button_text="Save"
	var field:=LineEdit.new()
	field.text=initial
	field.max_length=96
	field.custom_minimum_size=Vector2(310,34)
	dialog.add_child(field)
	add_child(dialog)
	var confirm:=func():
		dialog.hide()
		submitted.call(field.text.strip_edges())
		dialog.queue_free()
	dialog.confirmed.connect(confirm)
	dialog.canceled.connect(dialog.queue_free)
	field.text_submitted.connect(func(_text):confirm.call())
	dialog.popup_centered()
	field.select_all()
	field.grab_focus()

func _message(heading: String, message: String) -> void:
	var dialog:=AcceptDialog.new()
	dialog.title=heading
	dialog.dialog_text=message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360,120))

func _os_prefs_path() -> String:
	return "user://campus_os_%s.cfg" % str(session.get("local_profile")).sha256_text().left(24)

func _save_os_preferences() -> void:
	var cfg:=ConfigFile.new()
	cfg.set_value("desktop","pinned",pinned_apps)
	cfg.set_value("desktop","style",style_choice)
	var error:=cfg.save(_os_prefs_path())
	if error!=OK:desktop_status.text="Desktop preferences could not be saved."

func _load_os_preferences() -> void:
	var cfg:=ConfigFile.new()
	if cfg.load(_os_prefs_path())==OK:
		var saved: Variant=cfg.get_value("desktop","pinned",["Files","Browser"])
		pinned_apps=saved.filter(func(name):return name in app_names) if saved is Array else ["Files","Browser"]
		style_choice=clampi(int(cfg.get_value("desktop","style",0)),0,2)
	for name in app_names:task_buttons[name].visible=name in pinned_apps or windows.has(name)
	_apply_wallpaper()

func _apply_wallpaper() -> void:
	wallpaper_panel.modulate=[Color.WHITE,Color("9dbad9"),Color("83c8bb")][style_choice]

func _build_os_settings() -> void:
	var split:=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(split)
	var navigation:=VBoxContainer.new()
	navigation.custom_minimum_size.x=132
	split.add_child(navigation)
	var sections:=TabContainer.new()
	sections.tabs_visible=false
	sections.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	split.add_child(sections)
	var system:=VBoxContainer.new()
	system.name="System"
	sections.add_child(system)
	var banner:=PanelContainer.new()
	banner.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("104c61"),Color("27aabf"),12))
	system.add_child(banner)
	var identity:=Label.new()
	identity.text="Campus OS\nLabVolt Practice Simulator"
	identity.add_theme_font_size_override("font_size",21)
	banner.add_child(identity)
	var system_heading:=Label.new()
	system_heading.text="System"
	system_heading.add_theme_font_size_override("font_size",18)
	system.add_child(system_heading)
	var theme_row:=HBoxContainer.new()
	system.add_child(theme_row)
	var theme_name:=Label.new()
	theme_name.text="System theme"
	theme_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_name)
	var system_style:=_os_theme_select()
	theme_row.add_child(system_style)
	var pins_row:=HBoxContainer.new()
	system.add_child(pins_row)
	var pins_label:=Label.new()
	pins_label.text="Taskbar pins"
	pins_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	pins_row.add_child(pins_label)
	pins_row.add_child(_button("Manage pins",func():sections.current_tab=2))
	system.add_child(HSeparator.new())
	var appearance := VBoxContainer.new()
	appearance.name = "Appearance"
	sections.add_child(appearance)
	var heading := Label.new()
	heading.text = "System theme"
	heading.add_theme_font_size_override("font_size", 20)
	appearance.add_child(heading)
	var style:=_os_theme_select()
	appearance.add_child(style)
	style.item_selected.connect(system_style.select)
	system_style.item_selected.connect(style.select)
	var apps := VBoxContainer.new()
	apps.name = "Taskbar pins"
	sections.add_child(apps)
	var pins := ScrollContainer.new()
	pins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	apps.add_child(pins)
	var pin_list := VBoxContainer.new()
	pin_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pins.add_child(pin_list)
	for name in app_names:
		var pin := CheckButton.new()
		pin.text = name
		pin.icon = shortcuts_by_name[name].icon
		pin.button_pressed = name in pinned_apps
		pin.toggled.connect(func(value: bool):
			if value != (name in pinned_apps): _toggle_pin(name))
		pin_list.add_child(pin)
	var about := Label.new()
	about.name = "About"
	about.text = "Campus OS\nLabVolt Practice Simulator"
	about.add_theme_font_size_override("font_size", 22)
	sections.add_child(about)
	var group:=ButtonGroup.new()
	var section_icons:=["settings","palette","inventory","info"]
	for index in sections.get_child_count():
		var destination:=index
		var button:=_button(str(sections.get_child(index).name),func():sections.current_tab=destination)
		button.icon=Icon.icon(section_icons[index])
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode=true
		button.button_group=group
		button.button_pressed=index==0
		navigation.add_child(button)
		sections.tab_changed.connect(func(active:int):button.set_pressed_no_signal(active==destination))

func _os_theme_select() -> OptionButton:
	var selector:=OptionButton.new()
	for name in ["Campus navy","Evening blue","Muted teal"]:selector.add_item(name)
	selector.select(style_choice)
	selector.item_selected.connect(func(index:int):
		style_choice=index
		_apply_wallpaper()
		_save_os_preferences())
	return selector

func _build_files(name: String) -> void:
	var toolbar := HFlowContainer.new()
	content.add_child(toolbar)
	var create:=_button("New file",func():
		var extension := ".campus" if name=="Code editor" else ".txt"
		_name_dialog("New virtual file","untitled"+extension,func(filename):
			if filename.is_empty() or filename.contains("/"):return
			var destination: String=filename if folder_path.is_empty() else folder_path+"/"+filename
			if not _valid_path(destination) or not _file(destination).is_empty():
				desktop_status.text="Choose an unused virtual filename."
				return
			pending_open_path=destination
			_send({"op":"save","path":destination,"text":"","version":0})))
	create.icon=Icon.icon("plus")
	create.theme_type_variation="PrimaryButton"
	toolbar.add_child(create)
	folder_button=_button("New folder",func():
		_name_dialog("New virtual folder","",func(name_value):
			if name_value.is_empty() or name_value.contains("/"):return
			var destination: String=name_value if folder_path.is_empty() else folder_path+"/"+name_value
			if _valid_path(destination):_send({"op":"mkdir","path":destination})))
	folder_button.icon=Icon.icon("folder")
	folder_button.visible=bool(snapshot.get("public_device",false)) and name!="Text editor";toolbar.add_child(folder_button)
	var open_button:=_button("Open",func():
		if name=="Files":_open_selected(true)
		else:_pick_editor_file())
	open_button.icon=Icon.icon("folder")
	toolbar.add_child(open_button)
	if name!="Files":
		var save_button:=_button("Save  Ctrl+S",_save_file)
		save_button.icon=Icon.icon("save")
		toolbar.add_child(save_button)
	var rename := _button("Rename",func():
		var selected:=_selected_entry()
		var source:=str(selected.get("path",current_path))
		if source.is_empty():return
		_name_dialog("Rename "+source.get_file(),source.get_file(),func(filename):
			if filename.is_empty() or filename.contains("/"):return
			var directory:=_parent_folder(source)
			var destination: String=filename if directory.is_empty() else directory+"/"+filename
			if not _valid_path(destination) or source==destination:return
			pending_folder_source=source
			pending_folder_target=destination
			_send({"op":"rename","path":source,"new_path":destination})))
	rename.disabled = not _supports_rename()
	rename.tooltip_text = "Rename is unavailable in this computer session." if rename.disabled else "Rename the selected virtual file."
	toolbar.add_child(rename)
	delete_button=_button("Delete", _delete_selected)
	delete_button.icon=Icon.icon("trash")
	delete_button.visible=bool(snapshot.get("public_device",false))
	var actions: HFlowContainer
	if name=="Files":
		toolbar.add_child(delete_button)
	else:
		actions=HFlowContainer.new()
		actions.hide()
		var more:=_button("⋯",func():actions.visible=not actions.visible)
		more.tooltip_text="Document actions"
		toolbar.add_child(more)
		content.add_child(actions)
		toolbar.remove_child(rename)
		actions.add_child(rename)
		actions.add_child(delete_button)
	var path_row := HBoxContainer.new()
	content.add_child(path_row)
	var path_label := Label.new()
	path_label.text = "Virtual file:"
	path_row.add_child(path_label)
	path_field = LineEdit.new()
	path_field.placeholder_text = "notes.txt or program.py"
	path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_field.text = current_path
	path_field.text_changed.connect(func(_value: String):
		if pending_new:autosave_timer.start())
	path_field.text_submitted.connect(func(_value: String):_save_file())
	path_row.add_child(path_field)
	path_row.visible=false
	if name!="Files":
		var open_tabs:=TabBar.new()
		open_tabs.clip_tabs=true
		open_tabs.tab_close_display_policy=TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
		var tab_row:=HBoxContainer.new()
		tab_row.name="DocumentTabs"
		open_tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab_row.add_child(open_tabs)
		var new_tab:=_button("+",func():create.pressed.emit())
		new_tab.custom_minimum_size.x=32
		new_tab.tooltip_text="New document"
		tab_row.add_child(new_tab)
		content.add_child(tab_row)
		var editor_state: Dictionary=windows[name]
		editor_state.tabs=open_tabs
		editor_state.documents=[]
		open_tabs.tab_changed.connect(func(index):
			if _rendering or index<0 or index>=editor_state.documents.size():return
			_capture_draft()
			current_path=editor_state.documents[index]
			_load_editor())
		open_tabs.tab_close_pressed.connect(func(index):
			if index<0 or index>=editor_state.documents.size():return
			_capture_draft()
			editor_state.documents.remove_at(index)
			if index==open_tabs.current_tab:
				current_path=editor_state.documents[mini(index,editor_state.documents.size()-1)] if not editor_state.documents.is_empty() else ""
			_load_editor())
	var trail := HBoxContainer.new()
	content.add_child(trail)
	var back_button:=_button("‹",func():_browse_history(-1))
	back_button.custom_minimum_size.x=34
	back_button.tooltip_text="Back"
	trail.add_child(back_button)
	var forward_button:=_button("›",func():_browse_history(1))
	forward_button.custom_minimum_size.x=34
	forward_button.tooltip_text="Forward"
	trail.add_child(forward_button)
	var trail_panel:=PanelContainer.new()
	trail_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	trail_panel.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("062638"),Color("286478"),16))
	trail.add_child(trail_panel)
	breadcrumbs=Label.new()
	trail_panel.add_child(breadcrumbs)
	var up:=_button("↑",_folder_up)
	up.custom_minimum_size.x=34
	up.tooltip_text="Parent folder"
	trail.add_child(up)
	trail.visible=name=="Files"
	var split := HSplitContainer.new()
	split.split_offset=-165 if name=="Code editor" else -220 if name=="Files" else 0
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	if name=="Files":
		var shortcuts := VBoxContainer.new()
		shortcuts.custom_minimum_size.x=144
		split.add_child(shortcuts)
		var heading:=Label.new()
		heading.text="Locations"
		shortcuts.add_child(heading)
		for location in [["Workspace","","folder"],["Documents","Documents","course"],["Downloads","Downloads","download"],["Pictures","Pictures","palette"]]:
			var destination: String=location[1]
			var place:=_button(location[0],func():_go_to_location(destination))
			place.icon=Icon.icon(location[2])
			place.alignment=HORIZONTAL_ALIGNMENT_LEFT
			place.set_drag_forwarding(func(_point):return null,func(_point,data):return not _move_destination(data,destination).is_empty(),func(_point,data):_move_entry(data,destination))
			shortcuts.add_child(place)
		shortcuts.add_child(HSeparator.new())
		var bin:=_button("Recycle Bin",func():_switch_app("Recycle Bin"))
		bin.icon=Icon.icon("trash")
		bin.alignment=HORIZONTAL_ALIGNMENT_LEFT
		shortcuts.add_child(bin)
		var copy:=_button("Copy download to USB",_choose_download_to_copy)
		copy.icon=Icon.icon("save")
		shortcuts.add_child(copy)
	file_list = Tree.new()
	file_list.set_meta("nav_history",[""])
	file_list.set_meta("nav_index",0)
	file_list.set_meta("nav_back",back_button)
	file_list.set_meta("nav_forward",forward_button)
	file_list.set_drag_forwarding(_file_drag_data,_file_can_drop_data,_file_drop_data)
	file_list.hide_root = true
	file_list.columns = 4
	file_list.column_titles_visible = true
	file_list.set_column_title(0, "Name")
	file_list.set_column_title(1, "Type")
	file_list.set_column_title(2, "Size")
	file_list.set_column_custom_minimum_width(2,65)
	file_list.set_column_expand(2,false)
	file_list.set_column_expand_ratio(0,3)
	file_list.set_column_title(3,"Modified")
	file_list.set_column_custom_minimum_width(3,115)
	file_list.set_column_expand(3,false)
	file_list.custom_minimum_size.x = 260
	file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_list.add_theme_constant_override("v_separation", 7)
	file_list.item_activated.connect(func(): _open_selected(true))
	split.add_child(file_list)
	file_list.visible = name == "Files"
	project_tree = null
	if name == "Code editor":
		project_tree = Tree.new()
		project_tree.custom_minimum_size.x = 188
		project_tree.item_activated.connect(func():
			var item := project_tree.get_selected()
			if item != null and not item.get_metadata(0).get("folder", false):
				_open_path(str(item.get_metadata(0).path)))
		split.add_child(project_tree)
	if name in ["Code editor", "Text editor"]:
		var code := CodeEdit.new()
		code.gutters_draw_line_numbers=true
		code.highlight_current_line=true
		code.caret_blink=true
		code.indent_use_spaces=true
		code.indent_size=4
		var highlighter := CodeHighlighter.new()
		highlighter.number_color=Color("e2b181")
		highlighter.symbol_color=Color("8ac1d4")
		highlighter.add_color_region('"','"',Color("a6d6ae"))
		highlighter.add_color_region("#","",Color("91a4b1"),true)
		for keyword in ["let","print","repeat","end","def","func","var","const","if","elif","else","for","while","return","import","class","true","false"]:
			highlighter.add_keyword_color(keyword,Color("9eafff"))
		if name=="Code editor": code.syntax_highlighter=highlighter
		var mono := SystemFont.new()
		mono.font_names=PackedStringArray(["Consolas","Cascadia Mono","DejaVu Sans Mono"])
		code.add_theme_font_override("font",mono)
		editor=code
	else:editor=TextEdit.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE if name == "Code editor" else TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text_changed.connect(_on_text_changed)
	if name!="Files":
		var find:=LineEdit.new()
		find.placeholder_text="Find in document"
		find.right_icon=Icon.icon("search")
		find.custom_minimum_size.x=138
		if name=="Code editor":actions.add_child(find)
		else:toolbar.add_child(find)
		find.text_submitted.connect(func(term):
			if term.is_empty():return
			var hit:=editor.search(term,0,editor.get_caret_line(),editor.get_caret_column()+1)
			if hit.x>=0:editor.select(hit.y,hit.x,hit.y,hit.x+term.length());editor.grab_focus())
		editor.add_theme_font_size_override("font_size",14)
	var document := VBoxContainer.new()
	document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(document)
	if name=="Code editor":
		var tab_row: Control=windows[name].tabs.get_parent()
		tab_row.reparent(document)
	document.visible = name != "Files"
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	document.add_child(editor)
	editor.visible=name!="Files"
	if name != "Files":
		var footer:=PanelContainer.new()
		footer.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("0b3448"),Color("22586f"),8))
		var caret := Label.new()
		caret.add_theme_color_override("font_color", Color("a0c2d4"))
		document.add_child(footer)
		footer.add_child(caret)
		var local_editor: TextEdit = editor
		var update_caret := func():
			caret.text = "%s     Ln %d, Col %d     UTF-8     Spaces: 4" % ["Source" if name == "Code editor" else "Plain text", local_editor.get_caret_line() + 1, local_editor.get_caret_column() + 1]
		local_editor.caret_changed.connect(update_caret)
		update_caret.call()
	_refresh_file_list()
	_load_editor()
	if name == "Code editor":
		var editor_footer: Node=document.get_child(document.get_child_count()-1)
		var output:=TextEdit.new()
		var output_tools:=HBoxContainer.new()
		document.add_child(output_tools)
		var output_header:=Label.new()
		output_header.text="›_   Program output"
		output_header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		output_tools.add_child(output_header)
		output_tools.add_child(_button("Clear",func():output.clear()))
		output_tools.add_child(_button("Copy",func():DisplayServer.clipboard_set(output.text)))
		output.editable=false
		output.custom_minimum_size.y=72
		output.placeholder_text="Program output"
		document.add_child(output)
		document.move_child(editor_footer,-1)
		var run_button:=_button("Run",func():
			if current_path.get_extension().to_lower()!="campus":
				output.text="Run supports .campus files. Other source files can be edited and saved."
				return
			output.text=preload("res://scripts/campus/computers/campus_script.gd").new().run(editor.text))
		run_button.icon=Icon.icon("play")
		run_button.theme_type_variation="PrimaryButton"
		toolbar.add_child(run_button)
		toolbar.add_child(_button("Syntax",func():_message("CampusScript","let r = 3\nrepeat 3\n  print r * 2\n  let r = r + 1\nend\nif r > 4\n  print sqrt(r)\nend")))

func _file_rows() -> Array:
	var files: Variant = snapshot.get("files", [])
	if files is Array:
		return files
	if files is Dictionary:
		var rows: Array = []
		for key in files.keys():
			var row: Variant = files[key]
			if row is Dictionary:
				var copy: Dictionary = row.duplicate()
				copy["path"] = str(key)
				rows.append(copy)
		return rows
	return []

func _file(path: String) -> Dictionary:
	for value in _file_rows():
		if value is Dictionary and str(value.get("path", "")) == path:
			return value
	return {}

func _parent_folder(path: String) -> String:
	return path.get_base_dir() if path.contains("/") else ""

func _folder_up() -> void:
	_navigate_folder(_parent_folder(folder_path))

func _go_to_location(destination: String) -> void:
	if destination.is_empty() or destination in snapshot.get("folders",[]):
		_navigate_folder(destination)
	elif snapshot.get("public_device",false):
		file_list.set_meta("pending_location",destination)
		_send({"op":"mkdir","path":destination})

func _navigate_folder(destination: String) -> void:
	var history: Array=file_list.get_meta("nav_history")
	var index: int=file_list.get_meta("nav_index")
	if history[index]!=destination:
		history=history.slice(0,index+1)
		history.append(destination)
		file_list.set_meta("nav_history",history)
		file_list.set_meta("nav_index",history.size()-1)
	folder_path=destination
	_refresh_file_list()

func _browse_history(direction: int) -> void:
	var history: Array=file_list.get_meta("nav_history")
	var index: int=file_list.get_meta("nav_index")+direction
	while index>=0 and index<history.size():
		var destination: String=history[index]
		if destination.is_empty() or destination in snapshot.get("folders",[]):
			file_list.set_meta("nav_index",index)
			folder_path=destination
			_refresh_file_list()
			return
		index+=direction

func _pick_editor_file() -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title="Open virtual file"
	dialog.ok_button_text="Open"
	var choices:=ItemList.new()
	choices.custom_minimum_size=Vector2(370,230)
	for row in _file_rows():choices.add_item(str(row.path),Icon.icon("course"))
	dialog.add_child(choices)
	add_child(dialog)
	dialog.get_ok_button().disabled=true
	choices.item_selected.connect(func(_index):dialog.get_ok_button().disabled=false)
	dialog.confirmed.connect(func():
		var selected:=choices.get_selected_items()
		if not selected.is_empty():_open_path(choices.get_item_text(selected[0]))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _file_drag_data(point: Vector2) -> Variant:
	if not _supports_rename():return null
	var row:=file_list.get_item_at_position(point)
	var entry: Variant=row.get_metadata(0) if row!=null else null
	if not entry is Dictionary:return null
	var preview:=Label.new()
	preview.text=str(entry.path).get_file()
	file_list.set_drag_preview(preview)
	return {"campus_virtual_path":entry.path}

func _drop_folder(point: Vector2) -> Variant:
	var row:=file_list.get_item_at_position(point)
	if row==null:return folder_path
	var entry: Variant=row.get_metadata(0)
	return entry.path if entry is Dictionary and entry.get("folder",false) else null

func _file_can_drop_data(point: Vector2,data: Variant) -> bool:
	var destination: Variant=_drop_folder(point)
	var allowed:=destination is String and not _move_destination(data,destination).is_empty()
	file_list.drop_mode_flags=Tree.DROP_MODE_ON_ITEM if allowed else Tree.DROP_MODE_DISABLED
	return allowed

func _file_drop_data(point: Vector2,data: Variant) -> void:
	var destination: Variant=_drop_folder(point)
	if destination is String:_move_entry(data,destination)

func _virtual_path_exists(path: String) -> bool:
	return path in snapshot.get("folders",[]) or snapshot.get("binary_files",{}).has(path) or not _file(path).is_empty()

func _move_destination(data: Variant,directory: String) -> String:
	if not _supports_rename() or not data is Dictionary:return ""
	var source:=str(data.get("campus_virtual_path",""))
	if not _valid_path(source) or not _virtual_path_exists(source):return ""
	if not directory.is_empty() and directory not in snapshot.get("folders",[]):return ""
	var target:=source.get_file() if directory.is_empty() else directory+"/"+source.get_file()
	if target.begins_with(source+"/") or not _valid_path(target) or _virtual_path_exists(target):return ""
	return target

func _move_entry(data: Variant,directory: String) -> void:
	var target:=_move_destination(data,directory)
	if target.is_empty():return
	var source:=str(data.campus_virtual_path)
	pending_folder_source=source
	pending_folder_target=target
	status_label.text="Moving "+source.get_file()+"…"
	_send({"op":"rename","path":source,"new_path":target})

func _rebase_open_documents(source: String,target: String) -> void:
	var remap:=func(path: String) -> String:
		return target+path.substr(source.length()) if path==source or path.begins_with(source+"/") else path
	current_path=remap.call(current_path)
	folder_path=remap.call(folder_path)
	for path in drafts.keys():
		var moved: String=remap.call(path)
		if moved!=path:
			drafts[moved]=drafts[path]
			drafts.erase(path)
	for window in windows.values():
		window.path=remap.call(str(window.get("path","")))
		window.folder=remap.call(str(window.get("folder","")))
		if window.has("documents"):window.documents=window.documents.map(remap)

func _refresh_file_list() -> void:
	if file_list==null:return
	var pending_location: String=file_list.get_meta("pending_location","")
	if not pending_location.is_empty() and pending_location in snapshot.get("folders",[]):
		file_list.remove_meta("pending_location")
		_navigate_folder(pending_location)
		return
	var index: int=file_list.get_meta("nav_index")
	file_list.get_meta("nav_back").disabled=index==0
	file_list.get_meta("nav_forward").disabled=index>=file_list.get_meta("nav_history").size()-1
	if not folder_path.is_empty() and not folder_path in snapshot.get("folders",[]):folder_path=""
	breadcrumbs.text="Workspace" if folder_path.is_empty() else "Workspace  ›  "+folder_path.replace("/","  ›  ")
	file_list.clear()
	var root_item := file_list.create_item()
	for folder in snapshot.get("folders", []):
		var path := str(folder)
		if _parent_folder(path) != folder_path: continue
		var row := file_list.create_item(root_item)
		row.set_text(0, path.get_file())
		row.set_icon(0, Icon.icon("folder"))
		row.set_icon_modulate(0,Color("ffd17b"))
		row.set_text(1, "Folder")
		row.set_text(2, "—")
		row.set_text(3,_modified_label(path))
		row.set_metadata(0, {"path":path,"folder":true})
	for value in _file_rows():
		var path := str(value.get("path", ""))
		if _parent_folder(path) != folder_path: continue
		var row := file_list.create_item(root_item)
		row.set_text(0, path.get_file())
		row.set_icon(0, Icon.icon("course"))
		row.set_text(1, path.get_extension().to_upper() if not path.get_extension().is_empty() else "File")
		row.set_text(2, String.humanize_size(str(value.get("text", "")).to_utf8_buffer().size()))
		row.set_text(3,_modified_label(path))
		row.set_metadata(0, {"path":path,"folder":false})
	for path: String in snapshot.get("binary_files",{}):
		if _parent_folder(path)!=folder_path:continue
		var row:=file_list.create_item(root_item)
		row.set_text(0,path.get_file())
		row.set_icon(0,Icon.icon("course"))
		row.set_text(1,path.get_extension().to_upper())
		row.set_text(2,String.humanize_size(int(snapshot.binary_files[path])))
		row.set_text(3,_modified_label(path))
		row.set_metadata(0,{"path":path,"folder":false,"binary":true})
	if root_item.get_child_count() == 0:
		var empty := file_list.create_item(root_item)
		empty.set_text(0, "This folder is empty")
		empty.set_selectable(0, false)
		empty.set_selectable(1, false)
		empty.set_selectable(2, false)
		empty.set_selectable(3, false)
	if is_instance_valid(project_tree): _refresh_project_tree()

func _modified_label(path: String) -> String:
	var stamp:=int(snapshot.get("modified",{}).get(path,0))
	return Time.get_datetime_string_from_unix_time(stamp,true).substr(5,11) if stamp>0 else "—"

func _refresh_project_tree() -> void:
	var expanded := {}
	var item := project_tree.get_root()
	while item != null:
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and metadata.folder: expanded[metadata.path] = not item.collapsed
		item = item.get_next_in_tree()
	project_tree.clear()
	var root_item := project_tree.create_item()
	root_item.set_text(0, "Workspace")
	root_item.set_metadata(0, {"path":"","folder":true})
	var folders := {"":root_item}
	var paths: Array = snapshot.get("folders", []).duplicate()
	paths.sort_custom(func(left, right): return str(left).length() < str(right).length())
	for path in paths:
		var parent: TreeItem = folders.get(_parent_folder(path), root_item)
		var row := project_tree.create_item(parent)
		row.set_text(0, str(path).get_file())
		row.set_icon(0, Icon.icon("folder"))
		row.set_metadata(0, {"path":path,"folder":true})
		row.collapsed = not bool(expanded.get(path, current_path.begins_with(str(path)+"/")))
		folders[path] = row
	for file in _file_rows():
		var path := str(file.path)
		var parent: TreeItem = folders.get(_parent_folder(path), root_item)
		var row := project_tree.create_item(parent)
		row.set_text(0, path.get_file())
		row.set_icon(0, Icon.icon("course"))
		row.set_metadata(0, {"path":path,"folder":false})
		if path == current_path: row.select(0)


func _selected_entry() -> Dictionary:
	if is_instance_valid(project_tree):
		var row := project_tree.get_selected()
		return row.get_metadata(0) if row != null else {}
	if file_list == null or file_list.get_selected() == null: return {}
	var metadata: Variant = file_list.get_selected().get_metadata(0)
	return metadata if metadata is Dictionary else {}

func _new_folder() -> void:
	if path_field==null:return
	var path:=path_field.text.strip_edges()
	if not _valid_path(path):status_label.text="Enter a valid folder path.";return
	_send({"op":"mkdir","path":path})

func _delete_selected() -> void:
	var selected:=_selected_entry()
	if selected.is_empty():status_label.text="Select a file or folder to delete.";return
	var path:=str(selected.path)
	_capture_draft()
	for draft in drafts:
		if str(draft)==path or str(draft).begins_with(path+"/"):
			status_label.text="Save or discard changes before deleting.";return
	var recoverable: bool=snapshot.get("recycle_available",false)
	_confirm_action(("Move %s to Recycle Bin?" if recoverable else "Delete %s permanently from this drive?") % path.get_file(),func():
		_send({"op":"trash" if recoverable else "delete","path":path})
		if current_path==path or current_path.begins_with(path+"/"):
			current_path="";_load_editor())

func _load_editor() -> void:
	if editor == null or active_app=="Files":
		return
	var file := _file(current_path)
	var next_text:=str(drafts.get(current_path,file.get("text","")))
	if editor.text!=next_text:
		_rendering=true
		editor.text=next_text
		_rendering=false
	if active_app in ["Text editor","Code editor"]:
		var window: Dictionary=windows[active_app]
		if window.has("tabs"):
			if not current_path.is_empty() and not current_path in window.documents:
				window.documents.append(current_path)
				if window.documents.size()>8:window.documents.pop_front()
			var tabs: TabBar=window.tabs
			_rendering=true
			tabs.clear_tabs()
			for path in window.documents:tabs.add_tab(str(path).get_file())
			if current_path.is_empty():tabs.add_tab("Untitled")
			var selected: int=window.documents.find(current_path)
			tabs.current_tab=selected if selected>=0 else tabs.tab_count-1
			_rendering=false
		app_window_title.text=(current_path.get_file() if not current_path.is_empty() else "Untitled")+"  ·  "+active_app
	if path_field != null:
		path_field.text = current_path
	if visible:
		editor.grab_focus()

func _capture_draft() -> void:
	if editor != null and active_app!="Files":
		if editor.text != str(_file(current_path).get("text", "")):
			drafts[current_path] = editor.text
		else:
			drafts.erase(current_path)

func _on_text_changed() -> void:
	if not _rendering:
		_capture_draft()
		status_label.text = "Editing…" if drafts.has(current_path) else "Saved"
		autosave_timer.start()

func _new_file() -> void:
	_capture_draft()
	if active_app=="Files":_switch_app("Text editor")
	current_path = ""
	pending_new = true
	if editor != null:
		_rendering = true
		editor.text = ""
		_rendering = false
	if path_field != null:
		path_field.text = "" if folder_path.is_empty() else folder_path+"/"
		path_field.grab_focus()
	status_label.text = "Enter a virtual filename, then Save."

func _open_selected(open_in_editor := false) -> void:
	var selected:=_selected_entry()
	if selected.is_empty():
		return
	if selected.get("folder",false):
		_navigate_folder(str(selected.path))
		return
	if selected.get("binary",false):
		status_label.text="This file is stored on the virtual drive."
		return
	_open_path(str(selected.path))

func _open_path(path: String, remember := true) -> void:
	if _file(path).is_empty():return
	var code_file:=path.get_extension().to_lower() in ["campus","gd","lua","py","js","ts","cs","c","cpp","json"]
	_switch_app("Code editor" if code_file else "Text editor")
	current_path=path
	folder_path=_parent_folder(path)
	pending_new=false
	recent_files.erase(path)
	recent_files.push_front(path)
	if recent_files.size()>16:recent_files.pop_back()
	_load_editor()
	if is_instance_valid(project_tree): _refresh_project_tree()
	if remember:_send({"op":"editor","path":path,"cursor":0})

func _valid_path(value: String) -> bool:
	return not value.to_lower().begins_with(".recycle") and preload("res://scripts/campus/computers/virtual_files.gd").path(value)==value and not value.is_empty()

func _save_file() -> void:
	_capture_draft()
	if editor==null or path_field==null:return
	var path:=path_field.text.strip_edges()
	if not _valid_path(path):
		status_label.text="Choose a valid file name."
		return
	if path!=current_path and not pending_new:
		status_label.text="Use Rename to change an existing file name."
		return
	if pending_new and current_path.is_empty() and not _file(path).is_empty():
		status_label.text="That virtual file already exists."
		return
	if pending_new and current_path.is_empty():
		drafts.erase("")
		current_path=path
	drafts[path]=editor.text
	_autosave()

func _autosave() -> void:
	if snapshot.is_empty() or not saving_path.is_empty():return
	if drafts.has("") and editor!=null and path_field!=null and pending_new:
		var path:=path_field.text.strip_edges()
		if _valid_path(path) and _file(path).is_empty():
			drafts[path]=drafts[""]
			drafts.erase("")
			current_path=path
	for raw in drafts.keys():
		var path:=str(raw)
		if path.is_empty():continue
		saving_path=path
		status_label.text="Saving…"
		_send({"op":"save","path":path,"text":str(drafts[path]),"version":int(_file(path).get("version",0))})
		return

func _rename_file() -> void:
	if not _supports_rename():
		status_label.text = "Rename is unavailable in this computer session."
		return
	if path_field == null:
		return
	var selected:=_selected_entry()
	var folder_selected:=bool(selected.get("folder",false))
	var old_path:=str(selected.get("path","")) if folder_selected else current_path
	if old_path.is_empty():return
	var new_path := path_field.text.strip_edges()
	if not _valid_path(new_path) or new_path == old_path or not _file(new_path).is_empty():
		status_label.text = "Choose a distinct valid virtual filename."
		return
	_capture_draft()
	if folder_selected:
		pending_folder_source=old_path;pending_folder_target=new_path
	else:pending_rename = new_path
	_send({"op": "rename", "path": old_path, "new_path": new_path})
	status_label.text = "Renaming " + old_path + "…"

func _supports_rename() -> bool:
	return session != null and session.has_method("supports_operation") and bool(session.call("supports_operation", "rename"))

func _send(payload: Dictionary) -> void:
	if session == null or snapshot.is_empty():
		return
	payload["lease"] = snapshot.get("lease", "")
	payload["revision"] = snapshot.get("revision", 0)
	var tiers: Dictionary = preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	var tier: String = str(snapshot.get("tier", ""))
	var delay: int = int(tiers.get(tier, {}).get("delay_ms", 0))
	if delay > 0 and payload.get("op", "") in ["save", "mkdir", "delete", "rename", "answer", "submit", "refresh"]:
		if _portable_pending:
			status_label.text = "The laptop is still processing the previous action."
			return
		_portable_pending = true
		status_label.text = "Processing…"
		await get_tree().create_timer(float(delay) / 1000.0).timeout
		_portable_pending = false
		if not is_inside_tree() or snapshot.is_empty() or snapshot.get("lease") != payload.lease or snapshot.get("revision") != payload.revision:
			return
	session.request(payload)

func _on_operation_failed(message: String) -> void:
	if pending_browser_download and is_instance_valid(browser_surface):browser_surface.status.text=message
	pending_browser_download=false
	pending_rename = ""
	pending_folder_source="";pending_folder_target=""
	saving_path=""
	pending_paper_id=0
	pending_open_path=""
	if is_instance_valid(file_list) and file_list.has_meta("pending_location"):file_list.remove_meta("pending_location")
	if is_instance_valid(status_label):
		status_label.text=message
	elif is_instance_valid(game) and is_instance_valid(game.get("ui")):
		game.ui.log_message(message)

func _request_exit() -> void:
	_capture_draft()
	exit_requested=true
	autosave_timer.stop()
	_exit_now()

func request_close() -> void:
	_request_exit()

func _exit_now() -> void:
	if snapshot.has("power_cycle"):
		parked_device=str(snapshot.get("station",""))
		parked_cycle=int(snapshot.get("power_cycle",-1))
		parked_profile=str(session.get("local_profile"))
		var layout: Array=[]
		for child in workspace.get_children():
			var key := str(child.get_meta("desktop_app",""))
			if not windows.has(key) or windows[key].shell!=child:continue
			var window: Dictionary=windows[key]
			layout.append({"app":window.app,"rect":window.rect,"restore":window.restore,"maximized":window.maximized,"minimized":not child.visible,"path":current_path if child==app_window else window.get("path",""),"folder":folder_path if child==app_window else window.get("folder",""),"documents":window.get("documents",[]).duplicate()})
		var browser: Dictionary=browser_surface.parked_tabs() if is_instance_valid(browser_surface) else {}
		parked_workspaces[parked_device]={"cycle":parked_cycle,"profile":parked_profile,"layout":layout,"path":current_path,"folder":folder_path,"browser":browser,"drafts":drafts.duplicate(true),"pending_new":pending_new}
	_send({"op":"exit"})

func _clear_powered_off(power: Dictionary) -> void:
	for id in parked_workspaces.keys():
		if not power.get(id,false):parked_workspaces.erase(id)
	if not parked_device.is_empty() and not power.get(parked_device,false):_reset_windows()

func _restore_parked(record: Dictionary) -> void:
	drafts=record.get("drafts",{}).duplicate(true)
	current_path=str(record.path)
	folder_path=str(record.folder)
	for entry in record.layout:
		if entry.app not in app_names: continue
		_switch_app(entry.app)
		var window: Dictionary=windows[_window_key(entry.app)]
		window.rect=entry.rect
		window.restore=entry.restore
		window.maximized=entry.maximized
		window.path=entry.get("path","")
		window.folder=entry.get("folder","")
		if window.has("documents"):window.documents=entry.get("documents",[]).duplicate()
		current_path=window.path;folder_path=window.folder
		_load_editor()
		window.shell.visible=not entry.minimized
	_fit_windows()
	_focus_last_window()
	pending_new=bool(record.get("pending_new",false))
	if is_instance_valid(browser_surface):browser_surface.restore_parked_tabs(record.browser)

func _reset_windows() -> void:
	for key in windows.keys():_close_window(key)
	parked_device=""
	parked_cycle=-1
	current_path=""
	folder_path=""
	pending_new=false

func _power_off() -> void:
	if is_instance_valid(browser_surface):browser_surface.close_session()
	_send({"op":"power", "station":str(snapshot.get("station",""))})

func _browser_attachment(kind: String,id: String,lease: String,item: Dictionary) -> PackedByteArray:
	if not is_instance_valid(browser_surface) or kind!="computer" or id!=str(snapshot.get("station","")) or lease!=str(snapshot.get("lease","")) or not visible:return PackedByteArray()
	if item.get("kind","")!="virtual_file":return PackedByteArray()
	var file: Dictionary=_file(str(item.get("name","")))
	if file.is_empty():return PackedByteArray()
	var data:=str(file.get("text","")).to_utf8_buffer()
	return data if data.size()<=browser_surface.MAX_ATTACHMENT_BYTES and data.size()==int(item.get("bytes",-1)) else PackedByteArray()

func _browser_save_answer(answer: String) -> void:
	if not visible or snapshot.is_empty() or answer.is_empty():return
	var stem:="assistant_"+Time.get_datetime_string_from_system().replace(":","").replace("-","").replace("T","_")
	var path:=stem+".txt"
	var suffix:=1
	while not _file(path).is_empty() and suffix<100:
		path=stem+"_"+str(suffix)+".txt";suffix+=1
	if not _file(path).is_empty():status_label.text="No free name for the assistant answer.";return
	_send({"op":"save","path":path,"text":answer.left(1600),"version":0})
	status_label.text="Saving assistant answer as "+path+"…"

func _browser_save_download(filename: String,bytes: PackedByteArray) -> void:
	if not visible or snapshot.is_empty():return
	pending_browser_download=true
	_send({"op":"download","name":filename,"bytes":bytes})

func _choose_download_to_copy() -> void:
	var paths: Array=snapshot.get("copyable_downloads",[])
	if paths.is_empty():
		status_label.text="Attach a USB drive and save a file in this workstation's Downloads first."
		return
	var dialog:=ConfirmationDialog.new()
	dialog.title="Copy download to USB"
	dialog.ok_button_text="Copy"
	var list:=ItemList.new()
	list.custom_minimum_size=Vector2(330,170)
	for path: String in paths:list.add_item(path.get_file())
	list.select(0)
	dialog.add_child(list)
	dialog.confirmed.connect(func():
		var selected:=list.get_selected_items()
		if not selected.is_empty():
			status_label.text="Copying to USB Downloads…"
			_send({"op":"copy_download","path":paths[selected[0]]})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _on_desktop_changed(value: Dictionary) -> void:
	if pending_browser_download and value.has("download_path"):
		if is_instance_valid(browser_surface):browser_surface.status.text="Saved to "+str(value.download_path)
		pending_browser_download=false
	if value.is_empty():
		pending_browser_download=false
		share_monitor = false
		monitor_share.set_pressed_no_signal(false)
		if not exit_requested or parked_device.is_empty():_reset_windows()
		var was_visible := visible
		visible = false
		snapshot.clear()
		drafts.clear()
		saving_path=""
		exit_requested=false
		start_panel.hide()
		pending_rename = ""
		pending_folder_source="";pending_folder_target=""
		if game != null and was_visible:
			game.capture()
		elif game == null and was_visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		closed.emit()
		if pending_paper_id > 0 and game != null:
			var id := pending_paper_id
			pending_paper_id = 0
			game.paper_ui.open_sheet(id)
		return
	var prior_lease: Variant = snapshot.get("lease")
	var station := str(value.get("station",""))
	var stored: Dictionary=parked_workspaces.get(station,{})
	var can_restore: bool = value.has("power_cycle") and not stored.is_empty() and stored.cycle==int(value.get("power_cycle",-1)) and stored.profile==str(session.get("local_profile"))
	if not can_restore:parked_workspaces.erase(station)
	var resumed := not parked_device.is_empty() and parked_device==str(value.get("station","")) and parked_cycle==int(value.get("power_cycle",-1)) and parked_profile==str(session.get("local_profile"))
	if prior_lease!=value.get("lease") and not resumed:_reset_windows()
	var save_acked := not saving_path.is_empty() and int(value.get("revision",-1))>int(snapshot.get("revision",-1))
	snapshot = value.duplicate(true)
	if resumed and is_instance_valid(browser_surface):browser_surface.lease=str(snapshot.get("lease",""))
	parked_device=""
	parked_cycle=-1
	var tiers: Dictionary = preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	var scale: float = float(tiers.get(str(snapshot.get("tier", "")), {}).get("display_scale", 1.0))
	laptop_display_filter.visible = scale < 1.0
	(laptop_display_filter.material as ShaderMaterial).set_shader_parameter("display_scale", scale)
	if power_button != null:power_button.visible=snapshot.has("power_cycle")
	monitor_share.visible = is_instance_valid(game) and game.session.online and snapshot.has("power_cycle") and str(snapshot.get("tier", "")).is_empty()
	if retry_documents_button != null:retry_documents_button.visible=not str(snapshot.get("local_error","")).is_empty()
	if folder_button != null:folder_button.visible=bool(snapshot.get("public_device",false)) and active_app!="Text editor"
	if delete_button != null:delete_button.visible=bool(snapshot.get("public_device",false))
	for path in drafts.keys():
		if not _file(str(path)).is_empty() and str(drafts[path]) == str(_file(str(path)).get("text", "")):
			drafts.erase(path)
	if prior_lease != snapshot.get("lease") and not resumed:
		drafts.clear()
		current_path = str(snapshot.get("editor", {}).get("path", ""))
	elif not pending_folder_target.is_empty() and _virtual_path_exists(pending_folder_target):
		_rebase_open_documents(pending_folder_source,pending_folder_target)
		pending_folder_source="";pending_folder_target=""
	elif not pending_rename.is_empty() and not _file(pending_rename).is_empty():
		var old_path := current_path
		current_path = pending_rename
		if drafts.has(old_path):
			drafts[current_path] = drafts[old_path]
			drafts.erase(old_path)
		status_label.text = "Renamed to " + current_path
		pending_rename = ""
	elif pending_new and not current_path.is_empty() and not _file(current_path).is_empty():
		pending_new = false
		status_label.text = "Saved"
	var was_visible := visible
	if not was_visible:_load_os_preferences()
	desktop_status.text=""
	visible = true
	if game != null and not was_visible:
		game.release_mouse()
	elif game == null and not was_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if prior_lease!=snapshot.get("lease") and can_restore:
		if resumed:
			drafts=stored.get("drafts",{}).duplicate(true)
			pending_new=bool(stored.get("pending_new",false))
		else:_restore_parked(stored)
	_refresh_file_list()
	_load_editor()
	if active_app=="Recycle Bin" and windows.has(active_app):_switch_app(active_app)
	if save_acked:
		saving_path=""
		if drafts.is_empty():status_label.text="Saved"
		if not drafts.is_empty():_autosave.call_deferred()
	if not pending_open_path.is_empty() and not _file(pending_open_path).is_empty():
		var new_path:=pending_open_path
		pending_open_path=""
		_open_path.call_deferred(new_path,false)
	if snapshot.has("local_error"):status_label.text=str(snapshot.local_error)

func _resize_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		resize_key=""
		return false
	if not resize_key.is_empty() and event is InputEventMouseMotion and windows.has(resize_key):
		var state: Dictionary=windows[resize_key]
		var delta := workspace.get_local_mouse_position()-resize_pointer
		var low := resize_start.position
		var high := resize_start.end
		var minimum: Vector2=state.shell.get_combined_minimum_size().max(Vector2(270,190))
		for axis in 2:
			if resize_edges[axis]<0:low[axis]=minf(low[axis]+delta[axis],high[axis]-minimum[axis])
			if resize_edges[axis]>0:high[axis]=maxf(high[axis]+delta[axis],low[axis]+minimum[axis])
		state.rect=Rect2(low,high-low)
		_fit_windows()
		return true
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) and not event is InputEventMouseMotion:return false
	var point := workspace.get_local_mouse_position()
	for index in range(workspace.get_child_count()-1,-1,-1):
		var item: Control=workspace.get_child(index)
		if not item.visible or not item.has_meta("desktop_app"):continue
		var rect := Rect2(item.position,item.size)
		if not rect.has_point(point):continue
		var key := str(item.get_meta("desktop_app"))
		if not windows.has(key) or windows[key].maximized:return false
		var edge := Vector2.ZERO
		for axis in 2:
			if point[axis]-rect.position[axis]<6:edge[axis]=-1
			elif rect.end[axis]-point[axis]<6:edge[axis]=1
		if edge==Vector2.ZERO:
			item.mouse_default_cursor_shape=Control.CURSOR_ARROW
			return false
		if edge.x==0:item.mouse_default_cursor_shape=Control.CURSOR_VSIZE
		elif edge.y==0:item.mouse_default_cursor_shape=Control.CURSOR_HSIZE
		else:item.mouse_default_cursor_shape=Control.CURSOR_FDIAGSIZE if edge.x==edge.y else Control.CURSOR_BDIAGSIZE
		if event is InputEventMouseMotion:return false
		_focus_window(key)
		resize_key=key
		resize_edges=edge
		resize_start=rect
		resize_pointer=point
		return true
	return false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _resize_input(event):
		get_viewport().set_input_as_handled()
		return
	if snapshot.get("public_device",false) and (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion):
		var now:=Time.get_ticks_msec()
		if now-last_activity_signal>=4000:
			last_activity_signal=now
			_send({"op":"activity"})
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var hovered:=get_viewport().gui_get_hovered_control()
		while is_instance_valid(hovered) and hovered!=workspace:
			if hovered.has_meta("desktop_app"):
				if app_window!=hovered:
					_capture_draft()
					_focus_window(hovered.get_meta("desktop_app"))
				break
			hovered=hovered.get_parent_control()
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ENTER and is_instance_valid(get_viewport().gui_get_focus_owner()) and get_viewport().gui_get_focus_owner() in shortcuts_by_name.values() and not selected_shortcut.is_empty():
		_switch_app(selected_shortcut)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if start_panel.visible:start_panel.hide()
		else:_request_exit()
		get_viewport().set_input_as_handled()
	elif event.alt_pressed and event.keycode == KEY_F4 and is_instance_valid(app_window):
		_close_window(str(app_window.get_meta("desktop_app")))
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_file()
		get_viewport().set_input_as_handled()
