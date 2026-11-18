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
var file_list: ItemList
var editor: TextEdit
var path_field: LineEdit
var status_label: Label
var title_label: Label
var content: VBoxContainer
var autosave_timer: Timer
var saving_path := ""
var exit_requested := false
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
var app_window_title: Label
var start_panel: PanelContainer
var start_button: Button
var app_window: PanelContainer
var workspace: Control
var windows := {}
var clock_label: Label
var desktop_status: Label
var app_names := ["Files","Text editor","Course work","Calculator","Browser","Code editor","Terminal","Settings","Recycle Bin","Circuit Lab"]
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
const Icon = preload("res://scripts/ui/design_system/widgets.gd")
const APP_ICONS := {"Files":"folder","Text editor":"save","Code editor":"code","Course work":"course","Calculator":"meter","Browser":"network","Terminal":"code","Settings":"settings","Circuit Lab":"circuit","Recycle Bin":"trash"}

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

func _build_shell() -> void:
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
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8 if side=="bottom" else (12 if side in ["left","right"] else 20))
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
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
	root.add_child(tray_shell)
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
	var clock_tick := Timer.new()
	clock_tick.wait_time=1.0
	clock_tick.autostart=true
	clock_tick.timeout.connect(_update_clock)
	add_child(clock_tick)
	_update_clock()
	start_panel = PanelContainer.new()
	start_panel.hide()
	start_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	start_panel.offset_left=22
	start_panel.offset_bottom=-72
	start_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	start_panel.offset_top=-444
	start_panel.custom_minimum_size=Vector2(388,350)
	start_panel.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("152b3d"), Color("38596c"), 14))
	add_child(start_panel)
	var start_list := VBoxContainer.new()
	start_panel.add_child(start_list)
	var start_heading := Label.new()
	start_heading.text = "Campus OS"
	start_heading.add_theme_font_size_override("font_size", 18)
	start_list.add_child(start_heading)
	start_search=LineEdit.new()
	start_search.placeholder_text="Search apps and files"
	start_search.text_changed.connect(_update_start_results)
	start_list.add_child(start_search)
	start_account=Label.new()
	start_account.add_theme_color_override("font_color",Color("aac1ce"))
	start_list.add_child(start_account)
	var start_scroll:=ScrollContainer.new()
	start_scroll.custom_minimum_size.y=235
	start_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	start_list.add_child(start_scroll)
	start_results=VBoxContainer.new()
	start_results.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	start_scroll.add_child(start_results)
	_update_start_results("")
	retry_documents_button=_button("Retry local save",func():session.retry_local_documents())
	retry_documents_button.hide()
	start_list.add_child(retry_documents_button)
	power_button=_button("Power off",_power_off)
	power_button.hide()
	start_list.add_child(power_button)
	start_list.add_child(_button("Leave computer",_request_exit))
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
	_switch_app("Files")

func _desktop_app_icon(name: String) -> Texture2D:
	var tile_colors := {"Files":"1c6197", "Text editor":"1379b9", "Course work":"6550bf",
		"Calculator":"247794", "Browser":"0986cf", "Code editor":"3c459e",
		"Terminal":"365367", "Settings":"5279a0", "Recycle Bin":"079482", "Circuit Lab":"6741b4"}
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
	frame.bg_color=Color("152b3d")
	frame.border_color=Color("38596c")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(10)
	frame.set_content_margin_all(8)
	frame.shadow_color=Color("00000066")
	frame.shadow_size=5
	window.add_theme_stylebox_override("panel",frame)
	workspace.add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	window.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var badge := TextureRect.new()
	badge.texture=Icon.icon(APP_ICONS[name])
	badge.custom_minimum_size=Vector2(16,16)
	badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bar.add_child(badge)
	var title := Label.new()
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.mouse_filter=Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape=Control.CURSOR_MOVE
	title.gui_input.connect(func(event: InputEvent):_window_drag(key,event))
	bar.add_child(title)
	for spec in [["—","Minimize",func():_minimize_window(key)],["□","Maximize or restore",func():_toggle_maximize(key)],["×","Close",func():_close_window(key)]]:
		var control := Button.new()
		control.text=spec[0]
		control.tooltip_text=spec[1]
		control.accessibility_name=spec[1]
		control.custom_minimum_size=Vector2(34,26)
		control.pressed.connect(spec[2])
		bar.add_child(control)
	var area := VBoxContainer.new()
	area.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(area)
	var message := Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size",12)
	column.add_child(message)
	var base := Vector2(830,575) if name in ["Files","Text editor","Code editor","Browser","Course work","Terminal","Circuit Lab","Recycle Bin"] else Vector2(338,460)
	var offset := float(windows.size()%5)*24.0
	window.position=Vector2(maxf(155.0,workspace.size.x-base.x-12) if name=="Calculator" else 210+offset,12+offset)
	var state := {"shell":window,"title":title,"content":area,"status":message,"app":name,"built":false,"maximized":false,"rect":Rect2(window.position,base),"restore":Rect2(window.position,base)}
	windows[key]=state
	_fit_windows()
	return state

func _fit_windows() -> void:
	if workspace.size.x<32 or workspace.size.y<32:return
	for state in windows.values():
		var window: PanelContainer=state.shell
		if state.maximized:
			window.position=Vector2.ZERO
			window.size=workspace.size
		else:
			var rect: Rect2=state.rect
			window.size=rect.size.max(window.get_combined_minimum_size()).min(workspace.size)
			window.position=rect.position.clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))

func _window_drag(key: String,event: InputEvent) -> void:
	var state: Dictionary=windows.get(key,{})
	if state.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_focus_window(key)
		if event.double_click:_toggle_maximize(key)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not state.maximized:
		var window: PanelContainer=state.shell
		window.position=(window.position+event.relative).clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))
		state.rect=Rect2(window.position,window.size)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not state.maximized:
		var pointer:=workspace.get_local_mouse_position()
		if pointer.y<10:
			_toggle_maximize(key)
		elif pointer.x<12 or pointer.x>workspace.size.x-12:
			var width:=workspace.size.x*.5
			state.rect=Rect2(Vector2(0 if pointer.x<12 else width,0),Vector2(width,workspace.size.y))
			_fit_windows()

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
	_capture_draft()
	var key := _window_key(name)
	var state: Dictionary=windows[key] if windows.has(key) else _create_window(key,name)
	var rebuild: bool=not state.built or state.app!=name or name in ["Course work","Recycle Bin"]
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
		state.merge({"file_list":file_list,"breadcrumbs":breadcrumbs,"editor":editor,"path_field":path_field,"folder_button":folder_button,"delete_button":delete_button},true)
	elif name == "Course work":
		_build_course_work()
	elif name == "Calculator":
		var calculator := preload("res://scripts/scientific_calculator.gd").new()
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
		status_label.text="Campus browser · embedded Chromium." if browser_surface.call("renderer_available") else "Embedded browser unavailable on this device."
	elif name=="Terminal":
		var terminal:=preload("res://scripts/campus/computers/virtual_terminal.gd").new()
		terminal.size_flags_vertical=Control.SIZE_EXPAND_FILL
		content.add_child(terminal)
		terminal.build(self)
	elif name=="Settings":_build_os_settings()
	elif name=="Recycle Bin":_build_recycle_bin()
	elif name=="Circuit Lab":
		var lab:=preload("res://scripts/campus/computers/circuit_lab_app.gd").new()
		lab.size_flags_vertical=Control.SIZE_EXPAND_FILL
		content.add_child(lab)
		lab.build(self)
		state.circuit=lab

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
	return {"Files":"Browse and organize virtual workspace files.","Text editor":"Write and autosave plain text notes.","Code editor":"Edit source files and run numeric CampusScript programs.","Course work":"Open assigned documents and see instructor feedback.","Calculator":"Scientific calculator for campus work.","Browser":"Open websites in the isolated Chromium session.","Terminal":"Work with virtual files using commands.","Settings":"Customize this Campus OS desktop."}.get(name,"Campus OS application")

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
	launchers.columns=2
	start_results.add_child(launchers)
	for name in app_names:
		if not needle.is_empty() and not name.to_lower().contains(needle):continue
		var launch:=_button(name,func():_switch_app(name);start_panel.hide())
		launch.icon=Icon.icon(APP_ICONS[name])
		launch.alignment=HORIZONTAL_ALIGNMENT_LEFT
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
	var entries:=ItemList.new()
	entries.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(entries)
	for item in snapshot.get("recycle",[]):
		var index:=entries.add_item(str(item.path),Icon.icon("trash"))
		entries.set_item_metadata(index,item.id)
	var tools:=HBoxContainer.new()
	content.add_child(tools)
	tools.add_child(_button("Restore",func():
		if not entries.get_selected_items().is_empty():
			_send({"op":"untrash","item":entries.get_item_metadata(entries.get_selected_items()[0])})))
	tools.add_child(_button("Delete permanently",func():
		if not entries.get_selected_items().is_empty():
			var item: String=entries.get_item_metadata(entries.get_selected_items()[0])
			_confirm_action("Delete this recycled item permanently?",func():_send({"op":"purge","item":item}))))
	tools.add_child(_button("Empty Recycle Bin",func():
		_confirm_action("Delete all recycled items permanently?",func():_send({"op":"purge"}))))

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
	var style:=OptionButton.new()
	for name in ["Campus navy","Evening blue","Muted teal"]:style.add_item(name)
	style.select(style_choice)
	style.item_selected.connect(func(index):
		style_choice=index
		_apply_wallpaper()
		_save_os_preferences())
	content.add_child(style)
	var pinned:=Label.new()
	pinned.text="Right-click a desktop shortcut to change its taskbar pin."
	pinned.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(pinned)
	var about:=Label.new()
	about.text="Campus OS • LabVolt Practice Simulator"
	content.add_child(about)

func _build_files(name: String) -> void:
	var toolbar := HFlowContainer.new()
	content.add_child(toolbar)
	toolbar.add_child(_button("New file",func():
		var extension := ".campus" if name=="Code editor" else ".txt"
		_name_dialog("New virtual file","untitled"+extension,func(filename):
			if filename.is_empty() or filename.contains("/"):return
			var destination: String=filename if folder_path.is_empty() else folder_path+"/"+filename
			if not _valid_path(destination) or not _file(destination).is_empty():
				desktop_status.text="Choose an unused virtual filename."
				return
			pending_open_path=destination
			_send({"op":"save","path":destination,"text":"","version":0}))))
	folder_button=_button("New folder",func():
		_name_dialog("New virtual folder","",func(name_value):
			if name_value.is_empty() or name_value.contains("/"):return
			var destination: String=name_value if folder_path.is_empty() else folder_path+"/"+name_value
			if _valid_path(destination):_send({"op":"mkdir","path":destination})))
	folder_button.visible=bool(snapshot.get("public_device",false));toolbar.add_child(folder_button)
	toolbar.add_child(_button("Open", func():_open_selected(true)))
	if name!="Files":toolbar.add_child(_button("Save  Ctrl+S",_save_file))
	var rename := _button("Rename",func():
		var selected:=_selected_entry()
		var source:=str(selected.get("path",current_path))
		if source.is_empty():return
		_name_dialog("Rename "+source.get_file(),source.get_file(),func(filename):
			if filename.is_empty() or filename.contains("/"):return
			var directory:=_parent_folder(source)
			var destination: String=filename if directory.is_empty() else directory+"/"+filename
			if not _valid_path(destination) or source==destination:return
			if selected.get("folder",false):
				pending_folder_source=source
				pending_folder_target=destination
			elif source==current_path:pending_rename=destination
			_send({"op":"rename","path":source,"new_path":destination})))
	rename.disabled = not _supports_rename()
	rename.tooltip_text = "Rename is unavailable in this computer session." if rename.disabled else "Rename the selected virtual file."
	toolbar.add_child(rename)
	delete_button=_button("Delete", _delete_selected)
	delete_button.visible=bool(snapshot.get("public_device",false));toolbar.add_child(delete_button)
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
		content.add_child(open_tabs)
		var editor_state: Dictionary=windows[name]
		editor_state.tabs=open_tabs
		editor_state.documents=[]
		open_tabs.tab_changed.connect(func(index):
			if _rendering or index<0 or index>=editor_state.documents.size():return
			_capture_draft()
			current_path=editor_state.documents[index]
			_load_editor())
		open_tabs.tab_close_pressed.connect(func(index):
			_capture_draft()
			editor_state.documents.remove_at(index)
			if index==open_tabs.current_tab:
				current_path=editor_state.documents[mini(index,editor_state.documents.size()-1)] if not editor_state.documents.is_empty() else ""
			_load_editor())
	var trail := HBoxContainer.new()
	content.add_child(trail)
	var up := _button("↑",_folder_up)
	up.tooltip_text="Parent folder"
	trail.add_child(up)
	breadcrumbs=Label.new()
	trail.add_child(breadcrumbs)
	trail.visible=name!="Text editor"
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
		var home:=_button("Workspace",func():folder_path="";_refresh_file_list())
		home.icon=Icon.icon("folder")
		shortcuts.add_child(home)
		var bin:=_button("Recycle Bin",func():_switch_app("Recycle Bin"))
		bin.icon=Icon.icon("trash")
		shortcuts.add_child(bin)
	file_list = ItemList.new()
	file_list.custom_minimum_size.x = 210 if name=="Files" else 132
	file_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	file_list.add_theme_constant_override("v_separation",7)
	file_list.item_activated.connect(func(_index: int): _open_selected(true))
	split.add_child(file_list)
	file_list.visible=name in ["Files","Code editor"]
	if name=="Code editor":
		var code := CodeEdit.new()
		code.gutters_draw_line_numbers=true
		var highlighter := CodeHighlighter.new()
		highlighter.number_color=Color("e2b181")
		highlighter.symbol_color=Color("8ac1d4")
		highlighter.add_color_region('"','"',Color("a6d6ae"))
		highlighter.add_color_region("#","",Color("91a4b1"),true)
		for keyword in ["let","print","repeat","end","def","func","var","const","if","elif","else","for","while","return","import","class","true","false"]:
			highlighter.add_keyword_color(keyword,Color("9eafff"))
		code.syntax_highlighter=highlighter
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
		find.custom_minimum_size.x=138
		toolbar.add_child(find)
		find.text_submitted.connect(func(term):
			if term.is_empty():return
			var hit:=editor.search(term,0,editor.get_caret_line(),editor.get_caret_column()+1)
			if hit.x>=0:editor.select(hit.y,hit.x,hit.y,hit.x+term.length());editor.grab_focus())
		editor.add_theme_font_size_override("font_size",14)
	split.add_child(editor)
	editor.visible=name!="Files"
	_refresh_file_list()
	_load_editor()
	if name == "Code editor":
		var output:=TextEdit.new()
		output.editable=false
		output.custom_minimum_size.y=88
		output.placeholder_text="Program output"
		content.add_child(output)
		toolbar.add_child(_button("Run",func():
			if current_path.get_extension().to_lower()!="campus":
				output.text="Run supports .campus files. Other source files can be edited and saved."
				return
			output.text=preload("res://scripts/campus/computers/campus_script.gd").new().run(editor.text)))
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
	folder_path=_parent_folder(folder_path)
	_refresh_file_list()

func _refresh_file_list() -> void:
	if file_list==null:return
	if not folder_path.is_empty() and not folder_path in snapshot.get("folders",[]):folder_path=""
	breadcrumbs.text="Workspace" if folder_path.is_empty() else "Workspace  ›  "+folder_path.replace("/","  ›  ")
	file_list.clear()
	for folder in snapshot.get("folders",[]):
		var path:=str(folder)
		if _parent_folder(path)!=folder_path:continue
		file_list.add_item(path.get_file(),Icon.icon("folder"))
		file_list.set_item_metadata(file_list.item_count-1,{"path":path,"folder":true})
	for value in _file_rows():
		var path:=str(value.get("path",""))
		if _parent_folder(path)!=folder_path:continue
		file_list.add_item(path.get_file(),Icon.icon("course"))
		file_list.set_item_metadata(file_list.item_count-1,{"path":path,"folder":false})

func _selected_entry() -> Dictionary:
	if file_list==null or file_list.get_selected_items().is_empty():return {}
	var metadata: Variant=file_list.get_item_metadata(file_list.get_selected_items()[0])
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
	if pending_new and current_path.is_empty():return
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
			var selected: int=window.documents.find(current_path)
			if selected>=0:tabs.current_tab=selected
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
		folder_path=str(selected.path)
		if is_instance_valid(path_field):path_field.text=folder_path+"/"
		_refresh_file_list()
		return
	_open_path(str(selected.path))

func _open_path(path: String, remember := true) -> void:
	if _file(path).is_empty():return
	if path.ends_with(".circuit"):
		_switch_app("Circuit Lab")
		var lab: Control=windows["Circuit Lab"].circuit
		for index in lab.project_picker.item_count:
			if lab.project_picker.get_item_text(index)==path:lab.project_picker.select(index)
		lab._open()
		return
	var code_file:=path.get_extension().to_lower() in ["campus","gd","lua","py","js","ts","cs","c","cpp","json"]
	_switch_app("Code editor" if code_file else "Text editor")
	current_path=path
	folder_path=_parent_folder(path)
	pending_new=false
	recent_files.erase(path)
	recent_files.push_front(path)
	if recent_files.size()>16:recent_files.pop_back()
	_load_editor()
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
	if exit_requested:
		if drafts.is_empty():_exit_now()
		else:
			exit_requested=false
			status_label.text="Name this file to save and leave."

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

func _build_course_work() -> void:
	var assignments: Array=snapshot.get("assignments",[])
	var tabs:=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(tabs)
	var overview:=_course_page(tabs,"Overview")
	_course_text(overview,"%d assignments in this session" % assignments.size())
	overview.add_child(_button("Refresh course work",func():_send({"op":"refresh"})))
	var work:=_course_page(tabs,"Assignments")
	if assignments.is_empty():_course_text(work,"No assignments are available in this session.")
	var grades:=_course_page(tabs,"Grades")
	var marked:=0
	for assignment in assignments:
		var id:=int(assignment.get("id",0))
		var title:=str(assignment.get("title","Assignment"))
		var mark: Dictionary=assignment.get("mark",{})
		_course_text(work,title+"  ·  "+("In progress" if mark.is_empty() else "Marked"))
		work.add_child(_button("Open in Paper Workspace",func():_open_paper(id)))
		if not mark.is_empty():
			marked+=1
			_course_text(grades,"%s  ·  %.1f%%" % [title,float(mark.get("score",0))])
			if mark.has("reason"):_course_text(grades,str(mark.reason))
			continue
		var questions: Array=assignment.get("questions",[])
		for index in questions.size():
			var question: Variant=questions[index]
			var key:=str(index)
			var prompt:=str(question.get("prompt",question.get("text","Question %d"%(index+1)))) if question is Dictionary else str(question)
			_course_text(work,prompt)
			var row:=HBoxContainer.new()
			work.add_child(row)
			var answer:=LineEdit.new()
			answer.max_length=512
			answer.text=str(assignment.get("answers",{}).get(key,""))
			answer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(answer)
			row.add_child(_button("Save answer",func():_send({"op":"answer","paper":id,"question":key,"value":answer.text})))
		if assignment.get("can_submit",false):
			work.add_child(_button("Submit assignment",func():
				_confirm_action("Submit "+title+" for grading?",func():_send({"op":"submit","paper":id}))))
	if marked==0:_course_text(grades,"Marked results will appear here.")
	var materials:=_course_page(tabs,"Materials")
	for item in snapshot.get("materials",[]):
		if item is Dictionary:_course_text(materials,str(item.get("title","Material"))+"\n"+str(item.get("text","")))
	if materials.get_child_count()==0:_course_text(materials,"No lesson materials are available in this session.")
	tabs.current_tab=clampi(int(windows["Course work"].get("tab",0)),0,tabs.get_tab_count()-1)
	tabs.tab_changed.connect(func(index):windows["Course work"].tab=index)

func _course_page(tabs: TabContainer, name: String) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=name
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _course_text(column: VBoxContainer, text: String) -> void:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)

func _open_paper(id: int) -> void:
	pending_paper_id=id
	_request_exit()

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
	pending_rename = ""
	pending_folder_source="";pending_folder_target=""
	saving_path=""
	exit_requested=false
	pending_paper_id=0
	pending_open_path=""
	status_label.text=message

func _request_exit() -> void:
	_capture_draft()
	exit_requested=true
	_autosave()

func request_close() -> void:
	_request_exit()

func _exit_now() -> void:
	if snapshot.has("power_cycle") and str(snapshot.get("tier","")).is_empty():
		parked_device=str(snapshot.get("station",""))
		parked_cycle=int(snapshot.get("power_cycle",-1))
		parked_profile=str(session.get("local_profile"))
		var layout: Array=[]
		for child in workspace.get_children():
			var key := str(child.get_meta("desktop_app",""))
			if not windows.has(key) or windows[key].shell!=child:continue
			var window: Dictionary=windows[key]
			layout.append({"app":window.app,"rect":window.rect,"restore":window.restore,"maximized":window.maximized,"minimized":not child.visible,"path":current_path if child==app_window else window.get("path",""),"folder":folder_path if child==app_window else window.get("folder","")})
		var browser: Dictionary=browser_surface.parked_tabs() if is_instance_valid(browser_surface) else {}
		parked_workspaces[parked_device]={"cycle":parked_cycle,"profile":parked_profile,"layout":layout,"path":current_path,"folder":folder_path,"browser":browser}
	_send({"op":"exit"})

func _clear_powered_off(power: Dictionary) -> void:
	for id in parked_workspaces.keys():
		if not power.get(id,false):parked_workspaces.erase(id)
	if not parked_device.is_empty() and not power.get(parked_device,false):_reset_windows()

func _restore_parked(record: Dictionary) -> void:
	current_path=str(record.path)
	folder_path=str(record.folder)
	for entry in record.layout:
		_switch_app(entry.app)
		var window: Dictionary=windows[_window_key(entry.app)]
		window.rect=entry.rect
		window.restore=entry.restore
		window.maximized=entry.maximized
		window.path=entry.get("path","")
		window.folder=entry.get("folder","")
		current_path=window.path;folder_path=window.folder
		_load_editor()
		window.shell.visible=not entry.minimized
	_fit_windows()
	_focus_last_window()
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

func _on_desktop_changed(value: Dictionary) -> void:
	if value.is_empty():
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
	if retry_documents_button != null:retry_documents_button.visible=not str(snapshot.get("local_error","")).is_empty()
	if folder_button != null:folder_button.visible=bool(snapshot.get("public_device",false))
	if delete_button != null:delete_button.visible=bool(snapshot.get("public_device",false))
	for path in drafts.keys():
		if not _file(str(path)).is_empty() and str(drafts[path]) == str(_file(str(path)).get("text", "")):
			drafts.erase(path)
	if prior_lease != snapshot.get("lease") and not resumed:
		drafts.clear()
		current_path = str(snapshot.get("editor", {}).get("path", ""))
	elif not pending_folder_target.is_empty() and pending_folder_target in snapshot.get("folders",[]):
		if current_path.begins_with(pending_folder_source+"/"):current_path=pending_folder_target+current_path.substr(pending_folder_source.length())
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
	if prior_lease!=snapshot.get("lease") and not resumed and can_restore:_restore_parked(stored)
	if windows.is_empty() and not can_restore:_switch_app("Files")
	_refresh_file_list()
	_load_editor()
	if windows.has("Circuit Lab"):windows["Circuit Lab"].circuit.refresh_projects()
	if active_app in ["Recycle Bin","Course work"] and windows.has(active_app):_switch_app(active_app)
	if save_acked:
		saving_path=""
		if drafts.is_empty():status_label.text="Saved"
		if exit_requested or not drafts.is_empty():_autosave.call_deferred()
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
			if resize_edges[axis]<0:low[axis]=clampf(low[axis]+delta[axis],0,maxf(0,high[axis]-minimum[axis]))
			if resize_edges[axis]>0:high[axis]=clampf(high[axis]+delta[axis],minf(workspace.size[axis],low[axis]+minimum[axis]),workspace.size[axis])
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
