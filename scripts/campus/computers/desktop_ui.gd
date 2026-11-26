extends Control
## One local player's virtual computer. All persistent operations go through ComputerSessions.
signal closed
signal workstation_volume_changed(station: String, value: int)

var session: Node
var game: Node
var snapshot: Dictionary = {}
var workstation_volumes: Dictionary = {}
var volume_button: Button
var volume_popover: PanelContainer
var volume_slider: HSlider
var volume_label: Label
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
var breadcrumbs: HBoxContainer
var executable_textures: Dictionary={}
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
const DevicePerformance=preload("res://scripts/campus/items/device_performance.gd")
var performance: Node
var freeze_overlay: CenterContainer
var performance_status: Label
var pending_app := ""
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
var pinned_apps := []
var selected_shortcut := ""
var shortcuts_by_name := {}
var start_search: LineEdit
var start_account: Label
var start_results: VBoxContainer
var recent_files: Array[String]=[]
var wallpaper_panel: TextureRect
var portable_battery: HBoxContainer
var style_choice := 0
var wallpaper_choice := 0
var wallpaper_image := ""
var wallpaper_material: ShaderMaterial
var wallpaper_pixel: Texture2D
var preferences_timer: Timer
var pending_open_path := ""
var pending_open_editor := ""
var pending_preview := ""
var pending_web_project: Dictionary = {}
var pending_run_path := ""
var file_clipboard := {}
var file_menu: PopupMenu
var file_viewer: Control
var _covered_viewport: Viewport
var _covered_viewport_disabled_3d := false
const Icon = preload("res://scripts/ui/design_system/widgets.gd")
const FileTypes = preload("res://scripts/campus/computers/browser_download.gd")
const VirtualFiles = preload("res://scripts/campus/computers/virtual_files.gd")
const NativeClient=preload("res://scripts/campus/computers/CampusNativeClient.cs")
const NativeWindow=preload("res://scripts/campus/computers/native_windows_surface.gd")
const Viewer = preload("res://scripts/campus/computers/file_viewer.gd")
const Preferences = preload("res://scripts/campus/computers/desktop_preferences.gd")
const Monaco = preload("res://scripts/campus/computers/monaco_surface.gd")
const Execution = preload("res://scripts/campus/computers/ide_execution.gd")
const Apps = preload("res://scripts/campus/computers/application_registry.gd")
const WebSurface = preload("res://scripts/campus/computers/offline_web_surface.gd")
var installed_apps_view: VBoxContainer
var displayed_apps: Dictionary = {}
var installed_shortcuts: GridContainer
var displayed_shortcuts: Dictionary = {}
var execution: Node
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
	if session.has_signal("file_opened"):session.file_opened.connect(_show_file_preview)
	autosave_timer=Timer.new()
	autosave_timer.one_shot=true
	autosave_timer.wait_time=.55
	autosave_timer.timeout.connect(_autosave)
	add_child(autosave_timer)
	preferences_timer=Timer.new()
	preferences_timer.one_shot=true
	preferences_timer.wait_time=.22
	preferences_timer.timeout.connect(_save_os_preferences)
	add_child(preferences_timer)
	execution=Execution.new()
	add_child(execution)
	if multiplayer.is_server():execution.configure_from_host()
	if session.has_signal("power_changed"):session.power_changed.connect(_clear_powered_off)
	_build_shell()
	performance=DevicePerformance.new()
	add_child(performance)
	freeze_overlay=DevicePerformance.freeze_overlay("Laptop is frozen")
	add_child(freeze_overlay)
	freeze_overlay.hide()
	freeze_overlay.z_index=10
	performance_status=Label.new()
	performance_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	performance_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	performance_status.add_theme_stylebox_override("normal",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("142d3fee"),Color("588296"),10))
	add_child(performance_status)
	performance_status.position=Vector2(24,18)
	performance_status.z_index=9
	performance_status.hide()
	performance.freeze_changed.connect(func(frozen: bool):
		freeze_overlay.visible=frozen
		if is_instance_valid(browser_surface):browser_surface.set_device_suspended(frozen))
	performance.crashed.connect(func():
		if is_instance_valid(game):game.ui.log_message("The laptop crashed. Turn it on again to restart Campus OS.")
		_power_off())
	visibility_changed.connect(_update_world_rendering)
	tree_exiting.connect(_restore_world_rendering)

func _update_world_rendering() -> void:
	if snapshot.is_empty() or not is_visible_in_tree():
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

func apply_monitor_preferences(settings: Dictionary) -> void:
	_apply_appearance_preferences(settings)
	for name in app_names:task_buttons[name].visible=name in pinned_apps

func _build_shell(preview := false) -> void:
	var backdrop := TextureRect.new()
	wallpaper_panel=backdrop
	var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	backdrop.texture = ImageTexture.create_from_image(pixel)
	wallpaper_pixel=backdrop.texture
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var waves := Shader.new()
	waves.code = """
shader_type canvas_item;
uniform int scene_id = 0;

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
	if (scene_id == 1) {
		base = mix(vec3(.06,.12,.24), vec3(.34,.19,.29), smoothstep(.03,.78,uv.y));
		float sun = 1.0-smoothstep(.071,.077,length((uv-vec2(.7,.45))*vec2(1.65,1.0)));
		light = vec3(.57,.27,.10)*sun;
		for (int row=0; row<4; row++) {
			float layer=float(row);
			float ridge=.58+layer*.087+sin(uv.x*7.5+layer*2.4)*.10+sin(uv.x*19.0-layer*4.0)*.036;
			base=mix(base+light,mix(vec3(.21,.18,.28),vec3(.024,.078,.12),layer/3.0),smoothstep(ridge,ridge+.003,uv.y));
			light=vec3(0.0);
		}
	} else if (scene_id == 2) {
		vec2 sky=UV*vec2(145.0,96.0);
		float stars=step(.982,fract(sin(dot(floor(sky),vec2(43.71,13.93)))*19741.83))*(1.0-smoothstep(.02,.23,length(fract(sky)-.5)));
		base=vec3(.026,.046,.13)+stars*vec3(.58,.68,.84);
		float veil=.52-.19*sin(uv.x*3.8+.8)+.061*sin(uv.x*11.0);
		light=vec3(.06,.4,.29)*exp(-16.0*abs(uv.y-veil));
		light+=vec3(.13,.09,.4)*exp(-19.0*abs(uv.y-veil-.08));
	} else if (scene_id == 3) {
		vec2 grid=UV*vec2(68.0,41.0);
		vec2 line=abs(fract(grid)-.5);
		float trace=1.0-smoothstep(.009,.037,min(line.x,line.y));
		float led=1.0-smoothstep(.07,.20,length(line));
		float focus=exp(-length((uv-vec2(.73,.42))*vec2(1.1,1.6))*2.7);
		base=vec3(.022,.093,.11);
		light=focus*(vec3(.04,.20,.18)*trace+vec3(.16,.44,.34)*led);
	} else if (scene_id == 5) {
		base=mix(vec3(.05,.06,.18),vec3(.42,.17,.20),smoothstep(.0,.64,uv.y));
		vec2 sun_uv=(uv-vec2(.72,.49))*vec2(1.7,1.0);
		light=vec3(.7,.32,.10)*(1.0-smoothstep(.11,.114,length(sun_uv)))*(1.0-smoothstep(.57,.58,uv.y));
		base=mix(base,vec3(.035,.064,.12),smoothstep(.58,.65,uv.y));
		light+=vec3(.18,.055,.04)*exp(-16.0*abs(uv.y-.6));
	} else if (scene_id == 6) {
		vec2 cell=floor(uv*vec2(56.0,29.0));
		vec2 drop=fract(uv*vec2(56.0,29.0))-.5;
		float chance=fract(sin(dot(cell,vec2(32.17,83.92)))*17432.3);
		base=mix(vec3(.045,.09,.17),vec3(.025,.21,.24),1.0-uv.y);
		light=vec3(.31,.57,.62)*step(.65,chance)*(1.0-smoothstep(.035,.22,length(drop*vec2(2.0,.55))));
	} else if (scene_id == 7) {
		float radius=length((uv-vec2(.73,.46))*vec2(1.65,1.0));
		float rings=1.0-smoothstep(.025,.09,abs(fract(radius*17.0)-.5));
		base=mix(vec3(.055,.039,.071),vec3(.31,.13,.08),exp(-radius*2.0));
		light=vec3(.55,.25,.10)*rings*exp(-radius*3.2);
	} else if (scene_id == 8) {
		base=mix(vec3(.019,.035,.09),vec3(.09,.24,.39),smoothstep(.0,.86,uv.y));
		float ridge=.65+.08*sin(uv.x*8.0)+.04*sin(uv.x*21.0+1.0);
		base=mix(base,vec3(.016,.056,.105),smoothstep(ridge,ridge+.005,uv.y));
		light=vec3(.35,.43,.54)*(1.0-smoothstep(.036,.038,length((uv-vec2(.76,.25))*vec2(1.65,1.0))));
	}
	COLOR = vec4((base + light) * COLOR.rgb, 1.0);
}
"""
	var wallpaper_shader:=ShaderMaterial.new()
	wallpaper_shader.shader=waves
	wallpaper_material=wallpaper_shader
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
	var app_shortcut_scroll:=ScrollContainer.new()
	app_shortcut_scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	app_shortcut_scroll.offset_left=250
	app_shortcut_scroll.offset_right=480
	app_shortcut_scroll.offset_top=8
	app_shortcut_scroll.offset_bottom=-8
	app_shortcut_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app_shortcut_scroll.hide()
	workspace.add_child(app_shortcut_scroll)
	installed_shortcuts=GridContainer.new()
	installed_shortcuts.columns=2
	installed_shortcuts.add_theme_constant_override("h_separation",8)
	installed_shortcuts.add_theme_constant_override("v_separation",6)
	app_shortcut_scroll.add_child(installed_shortcuts)
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
		var app_button := _button("",func():_launch_app(app_name))
		app_button.icon=shortcuts_by_name[name].icon
		app_button.add_theme_constant_override("icon_max_width",25)
		app_button.custom_minimum_size.x=34
		app_button.tooltip_text=name
		app_button.accessibility_name=name
		app_button.visible=name in pinned_apps
		task_buttons[name]=app_button
		taskbar.add_child(app_button)
	taskbar.add_child(desktop_status)
	var tray_spacer:=Control.new()
	tray_spacer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tray_spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	taskbar.add_child(tray_spacer)
	if not preview:
		portable_battery=preload("res://scripts/ui/design_system/device_battery.gd").new()
		portable_battery.hide()
		taskbar.add_child(portable_battery)
		_build_volume_control(taskbar)
	clock_label = Label.new()
	clock_label.custom_minimum_size.x=48
	clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
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
	laptop_display_filter.material=preload("res://scripts/campus/items/device_display.gd").effect()
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
	if not is_instance_valid(portable_battery) or not is_instance_valid(game):return
	var station:=str(snapshot.get("station",""))
	portable_battery.visible=is_instance_valid(game.portable_laptops) and game.portable_laptops.placed.has(station)
	if portable_battery.visible:portable_battery.update_charge(game.device_charging.percent("laptop",station))

func _window_key(name: String) -> String:
	return name

func _create_window(key: String,name: String,viewer_icon: Texture2D = null) -> Dictionary:
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
	badge.texture=viewer_icon if viewer_icon!=null else shortcuts_by_name[name].icon
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
	var footer:=HBoxContainer.new()
	column.add_child(footer)
	var message := Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size",12)
	message.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(message)
	var grip:=Label.new()
	grip.text="◢"
	grip.tooltip_text="Drag to resize the window"
	grip.mouse_filter=Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape=Control.CURSOR_FDIAGSIZE
	grip.add_theme_color_override("font_color",Color("6998aa"))
	grip.gui_input.connect(_resize_window.bind(key))
	footer.add_child(grip)
	var base := Vector2(830,575) if name in ["Files","Text editor","Code editor","Browser","Terminal","Settings"] else Vector2(338,460)
	if name=="Recycle Bin":base=Vector2(650,430) if snapshot.get("recycle_available",false) else Vector2(475,185)
	var offset := float(windows.size()%5)*24.0
	window.position=Vector2(maxf(155.0,workspace.size.x-base.x-12) if name=="Calculator" else 210+offset,12+offset)
	if viewer_icon!=null:
		base=Vector2(540,285) if name=="Audio Player" else Vector2(900,630)
		base=base.min(workspace.size)
		window.position=(workspace.size-base)*.5
	var state := {"shell":window,"title":title,"content":area,"status":message,"app":name,"built":false,"maximized":false,"rect":Rect2(window.position,base),"restore":Rect2(window.position,base)}
	if name=="Recycle Bin" and not snapshot.get("recycle_available",false):
		state.rect=Rect2((workspace.size-base)*.5,base)
		state.restore=state.rect
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
			if state.app=="Recycle Bin":
				window.position=window.position.clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))

func _window_drag(key: String,event: InputEvent) -> void:
	var state: Dictionary=windows.get(key,{})
	if state.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_focus_window(key)
		if event.double_click:_toggle_maximize(key)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not state.maximized:
		var window: PanelContainer=state.shell
		window.position=_recoverable_window_position(window.position+event.relative,window.size)
		if state.app=="Recycle Bin":
			window.position=window.position.clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))
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

func _resize_window(event: InputEvent,key: String) -> void:
	var state: Dictionary=windows.get(key,{})
	if state.is_empty() or state.maximized:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_focus_window(key)
	elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		var window: PanelContainer=state.shell
		var limit: Vector2=(workspace.size-window.position).max(window.get_combined_minimum_size())
		state.rect=Rect2(window.position,(window.size+event.relative).clamp(window.get_combined_minimum_size(),limit))
		_fit_windows()

func _minimize_window(key: String) -> void:
	windows[key].shell.hide()
	if app_window==windows[key].shell:_focus_last_window()

func _close_window(key: String) -> void:
	if not windows.has(key):return
	var state: Dictionary=windows[key]
	if state.has("app_record") and is_visible_in_tree():_save_web_app_state(state)
	if key in ["Text editor","Code editor"] and app_window==state.shell:_capture_draft()
	if state.has("native_surface") and is_instance_valid(state.native_surface):state.native_surface.client.Stop()
	if key=="Browser" and is_instance_valid(browser_surface):
		browser_surface.close_session()
		browser_surface=null
	var focused: bool=app_window==state.shell
	state.shell.hide()
	state.shell.queue_free()
	windows.erase(key)
	if state.has("viewer_task"):state.viewer_task.queue_free()
	else:task_buttons[state.app].visible=state.app in pinned_apps
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

func _launch_app(name: String) -> void:
	if not is_instance_valid(performance) or performance.quality==DevicePerformance.MAX or windows.has(_window_key(name)):
		_switch_app(name)
		return
	if not pending_app.is_empty():return
	pending_app=name
	performance_status.text="Opening %s…"%name
	performance_status.show()
	if not performance.submit(func():
		pending_app=""
		performance_status.hide()
		_switch_app(name),true):
		pending_app=""
		performance_status.hide()

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
		calculator.performance=performance
		calculator.advanced_app=true
		calculator.campus_style = true
		calculator.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		calculator.size_flags_vertical=Control.SIZE_EXPAND_FILL
		content.add_child(calculator)
		for node in calculator.find_children("*","Button",true,false):
			node.custom_minimum_size.y=28
		_fit_windows.call_deferred()
	elif name == "Browser":
		browser_surface=preload("res://scripts/campus/computers/browser_surface.gd").new()
		browser_surface.game=game
		browser_surface.set_playback_quality(int(snapshot.get("audio_quality",3)))
		var station_id:=str(snapshot.get("station",""))
		var adapter: Node=game.get("computer_room_adapter") if game is Node3D else null
		var speaker: Variant=adapter.speaker_position(station_id) if is_instance_valid(adapter) else null
		if speaker is Vector3:
			browser_surface.speaker_world=game
			browser_surface.speaker_position=speaker
			browser_surface.speaker_volume=workstation_volume(station_id)
		browser_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(browser_surface)
		var files: Array=[]
		for row in _file_rows():
			if row is Dictionary:
				var text_value:=str(row.get("text",""))
				files.append({"kind":"virtual_file","name":str(row.get("path","")),"bytes":text_value.to_utf8_buffer().size()})
		browser_surface.configure("computer",str(snapshot.get("station","")),str(snapshot.get("lease","")),files)
		browser_surface.attachment_loader=_browser_attachment
		browser_surface.assistant_virtual_save=_browser_save_answer
		if snapshot.get("public_device",false):
			browser_surface.virtual_download_save=_browser_save_download
			browser_surface.download_destination=func():return "USB Downloads" if session.connected_usb_ports.has(station_id) else "Campus Downloads"
		status_label.visible=not browser_surface.call("renderer_available")
		status_label.text="Embedded browser unavailable on this device." if status_label.visible else ""
	elif name=="Terminal":
		var terminal:=preload("res://scripts/campus/computers/virtual_terminal.gd").new()
		state.terminal=terminal
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
		_launch_app(name);button.accept_event()
	elif event.button_index==MOUSE_BUTTON_RIGHT:
		_select_shortcut(name)
		var menu:=PopupMenu.new()
		add_child(menu)
		menu.add_item("Open",0)
		menu.add_item("Unpin from taskbar" if name in pinned_apps else "Pin to taskbar",1)
		menu.add_item("Properties",2)
		menu.id_pressed.connect(func(id):
			if id==0:_launch_app(name)
			elif id==1:_toggle_pin(name)
			elif id==2:_message(name,_app_description(name)))
		menu.popup_hide.connect(menu.queue_free)
		menu.position=Vector2i(DisplayServer.mouse_get_position())
		menu.popup()
		button.accept_event()

func _app_description(name: String) -> String:
	return {"Files":"Browse and organize virtual workspace files.","Text editor":"Write and autosave plain text notes.","Code editor":"Edit source files and run programs with available runtimes.","Calculator":"Scientific calculator for campus work.","Browser":"Open websites in the isolated Chromium session.","Terminal":"Work with virtual files using commands.","Settings":"Customize this Campus OS desktop."}.get(name,"Campus OS application")

func _toggle_pin(name: String) -> void:
	if name in pinned_apps:pinned_apps.erase(name)
	else:pinned_apps.append(name)
	task_buttons[name].visible=name in pinned_apps or windows.has(name)
	_save_os_preferences()

func _toggle_start(force_open := false) -> void:
	if not is_instance_valid(start_panel):return
	_set_volume_open(false)
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
		var launch:=_button(name,func():_launch_app(name);start_panel.hide())
		launch.icon=shortcuts_by_name[name].icon
		launch.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		launch.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		launch.add_theme_constant_override("icon_max_width", 38)
		launch.add_theme_font_size_override("font_size", 12)
		launch.custom_minimum_size=Vector2(87,66)
		launch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		launch.flat=true
		launchers.add_child(launch)
	for app: Dictionary in snapshot.get("installed_apps",{}).values():
		if not app.shortcut or (not needle.is_empty() and not str(app.name).to_lower().contains(needle)):continue
		var launch:=_button(str(app.name),func():_preview_path(str(app.archive));start_panel.hide())
		launch.icon=Icon.icon("component")
		launch.tooltip_text=str(app.publisher)+" · "+str(app.version)
		launch.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
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
			row.set_icon(0, Icon.icon("folder") if item.get("folder",false) else _file_icon(path))
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

func _confirm_action(message: String, action: Callable, title := "Confirm action", button := "Confirm") -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title=title
	dialog.ok_button_text=button
	dialog.dialog_text=message
	add_child(dialog)
	dialog.get_ok_button().theme_type_variation="DangerButton"
	dialog.confirmed.connect(func():dialog.hide();action.call();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _name_dialog(heading: String, initial: String, submitted: Callable, button := "Save", location := "") -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title=heading
	dialog.ok_button_text=button
	if not location.is_empty():dialog.dialog_text="Save in "+location
	var field:=LineEdit.new()
	field.text=initial
	field.max_length=96
	field.custom_minimum_size=Vector2(310,34)
	dialog.add_child(field)
	add_child(dialog)
	dialog.get_ok_button().theme_type_variation="PrimaryButton"
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

func _build_volume_control(taskbar: HBoxContainer) -> void:
	var tokens=preload("res://scripts/ui/design_system/tokens.gd")
	volume_button=Button.new()
	volume_button.icon=Icon.icon("volume")
	volume_button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	volume_button.add_theme_constant_override("icon_max_width",22)
	volume_button.custom_minimum_size=Vector2(40,36)
	volume_button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	volume_button.accessibility_name="Computer volume"
	volume_button.toggle_mode=true
	volume_button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	volume_button.add_theme_stylebox_override("hover",tokens.surface(Color("143b4f"),Color("386479"),6))
	volume_button.add_theme_stylebox_override("pressed",tokens.surface(Color("144e5b"),Color("68cbbb"),6))
	volume_button.toggled.connect(_set_volume_open)
	taskbar.add_child(volume_button)

	volume_popover=PanelContainer.new()
	volume_popover.custom_minimum_size.x=254
	var card: StyleBoxFlat=tokens.surface(Color("0c2a3b"),Color("32768a"),14)
	card.shadow_color=Color("040e19b8")
	card.shadow_size=8
	card.shadow_offset=Vector2(0,4)
	volume_popover.add_theme_stylebox_override("panel",card)
	volume_popover.hide()
	add_child(volume_popover)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	volume_popover.add_child(body)
	var heading:=HBoxContainer.new()
	body.add_child(heading)
	var caption:=Label.new()
	caption.text="Computer volume"
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	volume_label=Label.new()
	volume_label.custom_minimum_size.x=42
	volume_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	volume_label.add_theme_color_override("font_color",tokens.ACCENT)
	heading.add_child(volume_label)

	volume_slider=HSlider.new()
	volume_slider.custom_minimum_size.y=26
	volume_slider.max_value=100
	volume_slider.step=1
	volume_slider.accessibility_name="Computer volume"
	for part in ["slider","grabber_area","grabber_area_highlight"]:
		var color: Color=Color("061923") if part=="slider" else tokens.ACCENT
		var groove: StyleBoxFlat=tokens.surface(color,color,0)
		groove.set_corner_radius_all(3)
		groove.content_margin_top=3
		groove.content_margin_bottom=3
		volume_slider.add_theme_stylebox_override(part,groove)
	volume_slider.value_changed.connect(func(value: float):set_workstation_volume(str(snapshot.get("station","")),int(value)))
	body.add_child(volume_slider)
	resized.connect(_position_volume_popover)
	_sync_volume_slider()

func _set_volume_open(open: bool) -> void:
	if not is_instance_valid(volume_popover):return
	open=open and not snapshot.is_empty()
	volume_button.set_pressed_no_signal(open)
	volume_popover.visible=open
	if open:
		start_panel.hide()
		volume_popover.move_to_front()
		_position_volume_popover()
		volume_slider.grab_focus()

func _position_volume_popover() -> void:
	if not volume_popover.visible:return
	volume_popover.reset_size()
	var anchor:=volume_button.get_global_rect().position-global_position
	volume_popover.position=Vector2(
		clampf(anchor.x+volume_button.size.x*.5-volume_popover.size.x*.5,8,maxf(8,size.x-volume_popover.size.x-14)),
		anchor.y-volume_popover.size.y-12)

func workstation_volume(station: String) -> int:
	return int(workstation_volumes.get(station,35))

func set_workstation_volume(station: String, value: int) -> void:
	if station.is_empty():return
	value=clampi(value,0,100)
	if value==workstation_volume(station):return
	workstation_volumes[station]=value
	if is_instance_valid(browser_surface) and station==browser_surface.device_id:
		browser_surface.set_speaker_volume(value)
	if station==str(snapshot.get("station","")):
		_sync_volume_slider()
		if is_instance_valid(preferences_timer):preferences_timer.start()
	workstation_volume_changed.emit(station,value)

func _sync_volume_slider() -> void:
	if not is_instance_valid(volume_slider):return
	var value:=workstation_volume(str(snapshot.get("station","")))
	volume_slider.set_value_no_signal(value)
	volume_label.text="%d%%"%value
	volume_button.tooltip_text="Computer volume · %d%%"%value

func _save_os_preferences() -> void:
	var volume:=workstation_volume(str(snapshot.get("station","")))
	if snapshot.has("usb_storage"):
		_send({"op":"save_preferences","settings":{"style":style_choice,"wallpaper":wallpaper_choice,"image":wallpaper_image,"pinned":pinned_apps,"volume":volume}})
		return
	var cfg:=ConfigFile.new()
	cfg.set_value("desktop","pinned",pinned_apps)
	cfg.set_value("desktop","pins_configured",true)
	cfg.set_value("desktop","style",style_choice)
	cfg.set_value("desktop","wallpaper",wallpaper_choice)
	cfg.set_value("desktop","image",wallpaper_image)
	cfg.set_value("desktop","volume",volume)
	var error:=cfg.save(_os_prefs_path())
	if error!=OK:desktop_status.text="Desktop preferences could not be saved."

func _load_os_preferences() -> void:
	var cfg:=ConfigFile.new()
	var settings:={"style":0,"wallpaper":0,"image":"","pinned":[],"volume":35}
	if cfg.load(_os_prefs_path())==OK:
		var saved: Variant=cfg.get_value("desktop","pinned",[])
		var old_defaults: bool=not cfg.get_value("desktop","pins_configured",false) and saved==["Files","Browser"]
		settings=Preferences.clean({"style":cfg.get_value("desktop","style",0),"wallpaper":cfg.get_value("desktop","wallpaper",0),"image":cfg.get_value("desktop","image",""),"pinned":saved if not old_defaults else [],"volume":cfg.get_value("desktop","volume",35)})
	if not snapshot.get("usb_preferences",{}).is_empty():settings=snapshot.usb_preferences
	_apply_appearance_preferences(settings)
	var station:=str(snapshot.get("station",""))
	if not station.is_empty():
		var volume:=int(settings.get("volume",35))
		if volume!=workstation_volume(station):
			workstation_volumes[station]=volume
			if is_instance_valid(browser_surface) and station==browser_surface.device_id:browser_surface.set_speaker_volume(volume)
			workstation_volume_changed.emit(station,volume)
		_sync_volume_slider()
	for name in app_names:task_buttons[name].visible=name in pinned_apps or windows.has(name)

func _apply_appearance_preferences(settings: Dictionary) -> void:
	pinned_apps=settings.get("pinned",[])
	style_choice=settings.get("style",0)
	wallpaper_choice=settings.get("wallpaper",0)
	wallpaper_image=settings.get("image","")
	_apply_wallpaper()

func _apply_wallpaper() -> void:
	if wallpaper_choice==Preferences.CUSTOM_WALLPAPER and not wallpaper_image.is_empty():
		var source:=Marshalls.base64_to_raw(wallpaper_image)
		var image:=Image.new()
		if Preferences.valid_image(source) and image.load_jpg_from_buffer(source)==OK:
			wallpaper_panel.material=null
			wallpaper_panel.texture=ImageTexture.create_from_image(image)
			wallpaper_panel.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			wallpaper_panel.modulate=Color.WHITE
			return
	wallpaper_panel.material=wallpaper_material
	wallpaper_panel.texture=wallpaper_pixel
	wallpaper_panel.stretch_mode=TextureRect.STRETCH_SCALE
	wallpaper_material.set_shader_parameter("scene_id",clampi(wallpaper_choice,0,Preferences.WALLPAPERS.size()-1))
	wallpaper_panel.modulate=[Color.WHITE,Color("9dbad9"),Color("83c8bb")][style_choice]

func _choose_wallpaper(selector: OptionButton) -> void:
	var picker:=FileDialog.new()
	picker.title="Choose a desktop image"
	picker.access=FileDialog.ACCESS_FILESYSTEM
	picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	picker.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp ; Images"])
	picker.use_native_dialog=true
	add_child(picker)
	var lease: Variant=snapshot.get("lease")
	picker.file_selected.connect(func(path: String):
		var source:=FileAccess.open(path,FileAccess.READ)
		var image:=Image.new()
		if lease==snapshot.get("lease") and source!=null and source.get_length()<=16*1024*1024 and image.load(path)==OK:
			var aspect:=minf(1.0,minf(1920.0/image.get_width(),1200.0/image.get_height()))
			if aspect<1.0:image.resize(maxi(1,roundi(image.get_width()*aspect)),maxi(1,roundi(image.get_height()*aspect)),Image.INTERPOLATE_LANCZOS)
			var encoded:=image.save_jpg_to_buffer(.88)
			while encoded.size()>Preferences.MAX_IMAGE_BYTES and image.get_width()>120:
				var scale:=clampf(sqrt(float(Preferences.MAX_IMAGE_BYTES)/encoded.size()),.65,.92)
				image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
				encoded=image.save_jpg_to_buffer(.86)
			if Preferences.valid_image(encoded):
				wallpaper_image=Marshalls.raw_to_base64(encoded)
				wallpaper_choice=Preferences.CUSTOM_WALLPAPER
				if is_instance_valid(selector):selector.set_item_disabled(wallpaper_choice,false);selector.select(wallpaper_choice)
				_apply_wallpaper()
				_save_os_preferences()
			else:_message("Desktop image","This image could not be prepared.")
		elif lease==snapshot.get("lease"):_message("Desktop image","Choose a readable image under 16 MiB.")
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered(Vector2i(650,440))

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
	var wallpaper_heading:=Label.new()
	wallpaper_heading.text="Desktop background"
	appearance.add_child(wallpaper_heading)
	var wallpapers:=OptionButton.new()
	for name in Preferences.WALLPAPERS:wallpapers.add_item(name)
	wallpapers.set_item_disabled(Preferences.CUSTOM_WALLPAPER,wallpaper_image.is_empty())
	wallpapers.select(wallpaper_choice)
	wallpapers.item_selected.connect(func(index: int):
		wallpaper_choice=index
		_apply_wallpaper()
		_save_os_preferences())
	appearance.add_child(wallpapers)
	appearance.add_child(_button("Choose image from this computer…",_choose_wallpaper.bind(wallpapers)))
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
	var runtimes:=VBoxContainer.new()
	runtimes.name="Programming"
	sections.add_child(runtimes)
	var provider_status:=Label.new()
	provider_status.text="Judge0 remote compiler · "+("Available on this host" if not execution.endpoint.is_empty() and multiplayer.is_server() else "Host setup required")
	provider_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	runtimes.add_child(provider_status)
	var runtime_info:=TextEdit.new()
	runtime_info.editable=false
	runtime_info.size_flags_vertical=Control.SIZE_EXPAND_FILL
	runtime_info.text="Remote runs send source code and standard input to the configured provider after you confirm.\nEach run allows up to 3 CPU seconds, 8 seconds of elapsed execution and 256 MiB of memory."
	runtimes.add_child(runtime_info)
	var test_connection:=_button("Test Connection",func():
		provider_status.text="Checking Judge0…"
		var result: Dictionary=await execution.supported_runtimes()
		if not is_instance_valid(provider_status):return
		provider_status.text=str(result.error) if result.has("error") else "Judge0 connected · %d runtimes"%result.runtimes.size()
		if result.has("runtimes"):
			var names:=PackedStringArray()
			for runtime in result.runtimes:names.append(runtime.name)
			runtime_info.text="\n".join(names))
	test_connection.disabled=not multiplayer.is_server() or execution.endpoint.is_empty()
	runtimes.add_child(test_connection)
	var installed:=ScrollContainer.new()
	installed.name="Installed Apps"
	installed.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sections.add_child(installed)
	installed_apps_view=VBoxContainer.new()
	installed_apps_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	installed.add_child(installed_apps_view)
	_refresh_installed_apps()
	var group:=ButtonGroup.new()
	var section_icons:=["settings","palette","inventory","info","code","component"]
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
		var extension := ".py" if name=="Code editor" else ".txt"
		var directory:=folder_path
		_name_dialog("New virtual file","untitled"+extension,func(filename):
			if filename.is_empty() or filename.contains("/"):return
			var destination: String=filename if directory.is_empty() else directory+"/"+filename
			if not _valid_path(destination) or _virtual_path_exists(destination):
				desktop_status.text="Choose an unused virtual filename."
				return
			pending_open_path=destination
			pending_open_editor=name if name!="Files" else ""
			_send({"op":"save","path":destination,"text":"","version":0}),"Save",_display_workspace_path(directory)))
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
		var save_button:=_button("Save  Ctrl+S",_editor_action.bind("save"))
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
	var path_scroll:=ScrollContainer.new()
	path_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	path_scroll.follow_focus=true
	trail_panel.add_child(path_scroll)
	breadcrumbs=HBoxContainer.new()
	breadcrumbs.add_theme_constant_override("separation",5)
	path_scroll.add_child(breadcrumbs)
	var up:=_button("↑",_folder_up)
	up.custom_minimum_size.x=34
	up.tooltip_text="Parent folder"
	trail.add_child(up)
	trail.visible=name=="Files"
	if name=="Files" and snapshot.get("public_device",false):
		toolbar.add_child(_button("Import file…",_import_local_file))
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
	file_list.gui_input.connect(_file_list_input)
	split.add_child(file_list)
	file_list.visible = name == "Files"
	if name=="Files":
		var storage:=HBoxContainer.new()
		storage.name="USBStorage"
		content.add_child(storage)
		var storage_text:=Label.new()
		storage_text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		storage_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		storage.add_child(storage_text)
		var storage_meter:=ProgressBar.new()
		storage_meter.show_percentage=false
		storage_meter.custom_minimum_size=Vector2(112,8)
		storage_meter.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		storage.add_child(storage_meter)
		file_list.set_meta("usb_storage",storage)
		_update_usb_storage(file_list)
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
		for keyword in ["let","print","def","func","var","const","if","elif","else","for","while","return","import","class","true","false"]:
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
			var surface: Variant=windows.get(name,{}).get("monaco")
			if is_instance_valid(surface) and surface.initialized:
				surface.action("actions.find")
				surface.grab_focus()
				return
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
	if name=="Code editor" and DisplayServer.get_name()!="headless":
		var local_editor:=editor
		var monaco:=Monaco.new()
		document.add_child(monaco)
		monaco.hide()
		if monaco.start():
			windows[name].monaco=monaco
			var syntax:=OptionButton.new()
			syntax.tooltip_text="Syntax language for the active document"
			syntax.add_item("Automatic syntax")
			var modes: Array=Monaco.LANGUAGES.values()
			var unique:=PackedStringArray(["plaintext"])
			for language in modes:
				if language not in unique:unique.append(language)
			unique.sort()
			for language in unique:syntax.add_item(language.capitalize())
			syntax.item_selected.connect(func(index: int):
				monaco.set_language(current_path,unique[index-1] if index>0 else Monaco.LANGUAGES.get(current_path.get_extension().to_lower(),"plaintext")))
			actions.add_child(syntax)
			windows[name].syntax=syntax
			windows[name].syntax_modes=unique
			monaco.ready_to_edit.connect(func():
				local_editor.hide()
				monaco.show()
				if active_app==name:monaco.grab_focus())
			monaco.source_too_large.connect(func():
				if active_app==name:status_label.text="Source limit reached · 32 KiB per file.")
			monaco.source_changed.connect(func(path: String,value: String,kind: String):
				if active_app!=name or path!=current_path:
					if value!=str(_file(path).get("text","")):drafts[path]=value
					else:drafts.erase(path)
					return
				local_editor.text=value
				_on_text_changed()
				if kind=="save":_save_file()
				elif kind=="run":_run_code_editor())
		else:monaco.queue_free()
	if name != "Files":
		var footer:=PanelContainer.new()
		footer.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("0b3448"),Color("22586f"),8))
		var footer_content:=HBoxContainer.new()
		footer.add_child(footer_content)
		var saved_location:=Label.new()
		saved_location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		saved_location.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		footer_content.add_child(saved_location)
		var reveal:=_button("Show in Files",_reveal_current_file)
		reveal.tooltip_text="Open the folder and select this file"
		footer_content.add_child(reveal)
		windows[name].saved_location=saved_location
		windows[name].reveal_file=reveal
		var caret := Label.new()
		caret.add_theme_color_override("font_color", Color("a0c2d4"))
		document.add_child(footer)
		footer_content.add_child(caret)
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
		windows[name].program_output=output
		var run_button:=_button("Run",_editor_action.bind("run"))
		run_button.icon=Icon.icon("play")
		run_button.theme_type_variation="PrimaryButton"
		toolbar.add_child(run_button)
		toolbar.add_child(_button("Stop",execution.stop))

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

func _display_workspace_path(path: String) -> String:
	var root_name: String=str(snapshot.get("usb_storage",{}).get("name","Workspace"))
	return root_name+"/"+path

func _reveal_current_file() -> void:
	var path:=current_path
	if _file(path).is_empty():return
	_switch_app("Files")
	_navigate_folder(_parent_folder(path))
	for row in file_list.get_root().get_children():
		var metadata: Variant=row.get_metadata(0)
		if metadata is Dictionary and metadata.get("path")==path:
			row.select(0)
			file_list.scroll_to_item(row)
			break

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
	for row in _file_rows():choices.add_item(str(row.path),_file_icon(str(row.path)))
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

func _file_list_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_RIGHT or not event.pressed:return
	var row:=file_list.get_item_at_position(event.position)
	var entry: Variant=row.get_metadata(0) if row!=null else null
	if entry is Dictionary:row.select(0)
	_show_file_menu(entry if entry is Dictionary else {},file_list.get_global_mouse_position())
	file_list.accept_event()

func _show_file_menu(entry: Dictionary, pointer: Vector2) -> void:
	if is_instance_valid(file_menu):file_menu.queue_free()
	file_menu=PopupMenu.new()
	var menu:=file_menu
	var actions: Array[Callable]=[]
	var add:=func(label: String, action: Callable, icon := ""):
		var id:=actions.size()
		actions.append(action)
		if icon.is_empty():menu.add_item(label,id)
		else:menu.add_icon_item(Icon.icon(icon),label,id)
	var path:=str(entry.get("path",""))
	var folder:=bool(entry.get("folder",false))
	var ext:=path.get_extension().to_lower()
	var is_zip:=not folder and ext=="zip"
	var public_device:=bool(snapshot.get("public_device",false))
	var directory:=path if folder else folder_path
	if not path.is_empty():
		add.call("Open",func():_open_workspace_file(path),"folder" if folder else "course")
		if not folder and (FileTypes.is_text(ext) or not _file(path).is_empty()):
			add.call("Open in Text editor",func():_open_workspace_file(path,"Text editor"))
			add.call("Open in Code editor",func():_open_workspace_file(path,"Code editor"))
			if ext=="campus":add.call("Run in Terminal",func():_run_workspace_script(path),"play")
		if is_zip and public_device:
			add.call("Extract ZIP…",func():_archive_entry(path,"extract"),"download")
		menu.add_separator()
		add.call("Cut",func():file_clipboard={"path":path,"cut":true})
		add.call("Copy",func():file_clipboard={"path":path,"cut":false})
	if not file_clipboard.is_empty() and (entry.is_empty() or folder):
		add.call("Paste",func():_paste_entry(directory))
	if path.is_empty() and public_device:
		add.call("New folder…",func():_name_dialog("New folder","",func(name_value):
			var destination:=_join_virtual(directory,name_value)
			if _valid_path(destination) and not name_value.contains("/"):_send({"op":"mkdir","path":destination})
		,"Create"),"folder")
	elif not path.is_empty():
		add.call("Rename…",func():_rename_entry(path))
		if public_device:
			if not is_zip:add.call("Compress to ZIP…",func():_archive_entry(path,"zip"))
			add.call("Delete…",func():_delete_path(path),"trash")
		add.call("Properties",func():_entry_properties(path,folder),"info")
	if actions.is_empty():menu.queue_free();return
	add_child(menu)
	menu.id_pressed.connect(func(id: int):
		if id in range(actions.size()):actions[id].call())
	menu.popup_hide.connect(menu.queue_free)
	menu.position=Vector2i(pointer)
	menu.popup()

func _join_virtual(directory: String, filename: String) -> String:
	return filename if directory.is_empty() else directory+"/"+filename

func _rename_entry(source: String) -> void:
	_name_dialog("Rename "+source.get_file(),source.get_file(),func(filename):
		var target:=_join_virtual(_parent_folder(source),filename)
		if filename.contains("/") or not _valid_path(target) or _virtual_path_exists(target):
			status_label.text="Choose an unused name."
			return
		_capture_draft()
		pending_folder_source=source
		pending_folder_target=target
		_send({"op":"rename","path":source,"new_path":target})
	,"Rename")

func _paste_entry(directory: String) -> void:
	var source:=str(file_clipboard.get("path",""))
	if not _virtual_path_exists(source):file_clipboard.clear();return
	var cut:=bool(file_clipboard.get("cut",false))
	var name:=source.get_file()
	var target:=_join_virtual(directory,name)
	if not cut and _virtual_path_exists(target):
		var extension:=name.get_extension()
		if source in snapshot.get("folders",[]):extension=""
		var stem:=name if extension.is_empty() else name.get_basename()
		for index in range(1,100):
			var suffix:=" copy%s"%("" if index==1 else " "+str(index))
			target=_join_virtual(directory,stem.left(32-suffix.length()-(extension.length()+1 if not extension.is_empty() else 0))+suffix+("."+extension if not extension.is_empty() else ""))
			if not _virtual_path_exists(target):break
	if not _valid_path(target) or _virtual_path_exists(target) or target.begins_with(source+"/"):
		status_label.text="Choose an unused destination outside the source folder."
		return
	if cut:
		_capture_draft()
		pending_folder_source=source
		pending_folder_target=target
	_send({"op":"rename" if cut else "copy","path":source,"new_path":target})

func _archive_entry(source: String, operation: String) -> void:
	var extracting:=operation=="extract"
	var name:=source.get_file()
	var suggested:=name.get_basename() if extracting else name.left(28)+".zip"
	if extracting and _virtual_path_exists(_join_virtual(folder_path,suggested)):suggested=suggested.left(22)+" extracted"
	_name_dialog("Extract ZIP" if extracting else "Compress to ZIP",suggested,func(filename):
		if filename.contains("/"):return
		if not extracting and not filename.to_lower().ends_with(".zip"):filename+=".zip"
		var target:=_join_virtual(_parent_folder(source),filename)
		if _valid_path(target):_send({"op":operation,"path":source,"new_path":target})
	,"Extract" if extracting else "Compress")

func _entry_properties(path: String, folder: bool) -> void:
	var location:=_parent_folder(path)
	var size: int=snapshot.get("binary_files",{}).get(path,str(_file(path).get("text","")).to_utf8_buffer().size())
	var detail:="Folder" if folder else String.humanize_size(size)
	_message(path.get_file(),"%s\nLocation  /%s\nModified  %s"%[detail,location,_modified_label(path)])

func _run_workspace_script(path: String) -> void:
	var file:=_file(path)
	if file.is_empty():
		if snapshot.get("binary_files",{}).has(path):
			pending_run_path=path
			_send({"op":"open_text","path":path})
		return
	_switch_app("Terminal")
	var terminal: Variant=windows.get("Terminal",{}).get("terminal")
	if is_instance_valid(terminal):terminal.run_program(path,str(file.text))

func _editor_action(kind: String) -> void:
	var surface: Variant=windows.get(active_app,{}).get("monaco")
	if is_instance_valid(surface) and surface.initialized:
		surface.submit_source(kind)
	elif kind=="save":_save_file()
	else:_run_code_editor()

func _run_code_editor() -> void:
	if active_app!="Code editor" or not is_instance_valid(editor):return
	var output: TextEdit=windows["Code editor"].program_output
	if current_path.is_empty():
		output.text="Save this file before running it."
		return
	_run_source(current_path,editor.text,func(result: String):if is_instance_valid(output):output.text=result)

func _show_web_project(path: String, archive: PackedByteArray) -> void:
	var project:=pending_web_project
	pending_web_project={}
	var finished: Callable=project.finished
	var result: Dictionary=Apps.Packages.Zip.new().Unpack(archive,Apps.Packages.MAX_EXPANDED)
	if result.has("error"):
		finished.call(str(result.error))
		return
	var assets: Dictionary=result.files
	var entry:=path.get_file()
	var prefix:=path.get_base_dir()+"/" if not path.get_base_dir().is_empty() else ""
	for draft_path: String in drafts:
		if not draft_path.begins_with(prefix):continue
		var relative:=draft_path.trim_prefix(prefix)
		if assets.has(relative):assets[relative]=str(drafts[draft_path]).to_utf8_buffer()
	assets[entry]=str(project.source).to_utf8_buffer()
	var extension:=entry.get_extension().to_lower()
	if extension not in ["html","htm"]:
		var filename:=entry.uri_encode()
		var tag: String='<link rel="stylesheet" href="%s">'%filename if extension=="css" else '<script type="module" src="%s"></script>'%filename
		if assets.has("index.html"):
			entry="index.html"
		else:
			entry="_campus-preview.html"
			while assets.has(entry):entry="_"+entry
			assets[entry]=('<!doctype html><meta charset="utf-8"><title>Web Preview</title>'+tag).to_utf8_buffer()
	var key:="web:"+path
	_close_window(key)
	finished.call("Web preview opened." if _open_web_window(key,path.get_file()+" · Web Preview",entry,assets) else "The offline project renderer could not start.")

func _run_source(path: String, source: String, finished: Callable) -> void:
	var ext:=path.get_extension().to_lower()
	if ext in ["html","htm","css","js","mjs"]:
		if not WebSurface.available() or not snapshot.get("public_device",false):
			finished.call("The offline project renderer is unavailable on this device.")
			return
		if not pending_web_project.is_empty() or not pending_preview.is_empty():
			finished.call("Wait for the current file to finish opening.")
			return
		pending_web_project={"path":path,"source":source,"finished":finished}
		_send({"op":"read_project","path":path})
		return
	if ext=="json":
		finished.call(Execution.validate_json(source))
		return
	if ext=="campus":
		finished.call("CampusScript files can be opened as text.")
		return
	if multiplayer.is_server():execution.configure_from_host()
	if not multiplayer.is_server() or execution.endpoint.is_empty():
		finished.call("Set up the remote code runner in Singleplayer or Host Game → Programming Setup." if multiplayer.is_server() else "The session host manages remote code execution.")
		return
	if execution.running:
		finished.call("A program is already running.")
		return
	var lease: Variant=snapshot.get("lease")
	var dialog:=ConfirmationDialog.new()
	dialog.title="Run with Judge0"
	dialog.ok_button_text="Send and run"
	var form:=VBoxContainer.new()
	form.custom_minimum_size.x=400
	dialog.add_child(form)
	var notice:=Label.new()
	notice.text="%s and the standard input below will be sent to the host's Judge0 service."%path.get_file()
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	form.add_child(notice)
	var runtime:=OptionButton.new()
	runtime.add_item("Match runtime to file",0)
	form.add_child(runtime)
	var standard_input:=TextEdit.new()
	standard_input.custom_minimum_size.y=86
	standard_input.placeholder_text="Standard input (optional)"
	form.add_child(standard_input)
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(func():
		var stdin:=standard_input.text
		var runtime_id:=runtime.get_selected_id()
		dialog.queue_free()
		if lease!=snapshot.get("lease"):return
		finished.call("Running…")
		var result: String=await execution.execute(path,source,stdin,runtime_id)
		if lease==snapshot.get("lease"):finished.call(result))
	dialog.popup_centered()
	var catalog: Dictionary=await execution.supported_runtimes()
	if not is_instance_valid(dialog) or not dialog.visible:return
	for entry in catalog.get("runtimes",[]):runtime.add_item(str(entry.name),int(entry.id))

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

func _update_usb_storage(tree: Tree) -> void:
	var storage: HBoxContainer=tree.get_meta("usb_storage",null) if tree.has_meta("usb_storage") else null
	if not is_instance_valid(storage):return
	var usage: Dictionary=snapshot.get("usb_storage",{})
	storage.visible=not usage.is_empty()
	if usage.is_empty():return
	var label: Label=storage.get_child(0)
	var meter: ProgressBar=storage.get_child(1)
	label.text="%s  ·  %s / %s used"%[usage.name,String.humanize_size(usage.used),String.humanize_size(usage.capacity)]
	label.tooltip_text=label.text
	meter.max_value=usage.capacity
	meter.value=usage.used

func _refresh_file_list() -> void:
	var files_tree: Tree=windows.get("Files",{}).get("file_list")
	if is_instance_valid(files_tree):_update_usb_storage(files_tree)
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
	_refresh_breadcrumbs()
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
		row.set_icon(0, _file_icon(path))
		row.set_text(1, path.get_extension().to_upper() if not path.get_extension().is_empty() else "File")
		row.set_text(2, String.humanize_size(str(value.get("text", "")).to_utf8_buffer().size()))
		row.set_text(3,_modified_label(path))
		row.set_metadata(0, {"path":path,"folder":false})
	for path: String in snapshot.get("binary_files",{}):
		if _parent_folder(path)!=folder_path:continue
		var row:=file_list.create_item(root_item)
		row.set_text(0,path.get_file())
		row.set_icon(0,_file_icon(path))
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

func _refresh_breadcrumbs() -> void:
	if not breadcrumbs.is_visible_in_tree():return
	if breadcrumbs.has_meta("path") and breadcrumbs.get_meta("path")==folder_path:return
	breadcrumbs.set_meta("path",folder_path)
	for child in breadcrumbs.get_children():
		breadcrumbs.remove_child(child)
		child.queue_free()
	var path: String=""
	var segments := folder_path.split("/",false)
	segments.insert(0,"Workspace")
	for index in segments.size():
		if index>0:
			var arrow:=Label.new()
			arrow.text="›"
			arrow.mouse_filter=Control.MOUSE_FILTER_IGNORE
			breadcrumbs.add_child(arrow)
			path=segments[index] if path.is_empty() else path+"/"+segments[index]
		var crumb:=Button.new()
		crumb.text=segments[index]
		crumb.tooltip_text=path if not path.is_empty() else "Workspace"
		crumb.flat=true
		crumb.disabled=index==segments.size()-1
		crumb.pressed.connect(_navigate_folder.bind(path))
		breadcrumbs.add_child(crumb)
	var scroll:=breadcrumbs.get_parent() as ScrollContainer
	scroll.set_deferred("scroll_horizontal",2147483647)

func _file_icon(path: String) -> Texture2D:
	var extension:=path.get_extension().to_lower()
	if extension in ["exe","dll"]:
		var icon: PackedByteArray=snapshot.get("executable_icons",{}).get(path,PackedByteArray())
		if icon.size()>=24 and icon.size()<=4096 and icon.decode_u32(16)==0x18000000 and icon.decode_u32(20)==0x18000000:
			var cache_key:=icon.hex_encode()
			if not executable_textures.has(cache_key):
				var image:=Image.new()
				if image.load_png_from_buffer(icon)==OK:
					if executable_textures.size()>=64:executable_textures.erase(executable_textures.keys()[0])
					executable_textures[cache_key]=ImageTexture.create_from_image(image)
			if executable_textures.has(cache_key):return executable_textures[cache_key]
		return Icon.icon("mode_operate")
	if extension in ["zip","7z","rar","tar","gz","tgz","bz2","xz"]:return Icon.icon("inventory")
	if extension in FileTypes.IMAGE_EXTENSIONS:return Icon.icon("palette")
	if extension in FileTypes.VIDEO_EXTENSIONS:return Icon.icon("play")
	if extension in FileTypes.AUDIO_EXTENSIONS:return Icon.icon("volume")
	if extension in FileTypes.MODEL_EXTENSIONS:return Icon.icon("component")
	if extension in FileTypes.CODE_EXTENSIONS or extension in ["json","jsonl","xml","html","css","yaml","yml"]:return Icon.icon("code")
	if extension in ["csv","tsv","xls","xlsx","ods"]:return Icon.icon("keyboard")
	if extension in ["pdf","doc","docx","odt","md","txt","rtf","epub"]:return Icon.icon("course")
	return Icon.icon("info")

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
		row.set_icon(0, _file_icon(path))
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
	_delete_path(str(selected.path))

func _delete_path(path: String) -> void:
	_capture_draft()
	for draft in drafts:
		if str(draft)==path or str(draft).begins_with(path+"/"):
			status_label.text="Save or discard changes before deleting.";return
	var recoverable: bool=snapshot.get("recycle_available",false)
	_confirm_action(("Move %s to Recycle Bin?" if recoverable else "Delete %s permanently from this drive?") % path.get_file(),func():
		_send({"op":"trash" if recoverable else "delete","path":path})
		if current_path==path or current_path.begins_with(path+"/"):
			current_path="";_load_editor(),"Recycle item" if recoverable else "Delete item","Move to Recycle Bin" if recoverable else "Delete")

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
		if window.has("monaco"):
			var project_sources:={}
			var extension:=current_path.get_extension().to_lower()
			if extension in ["js","jsx","mjs","cjs","ts","tsx"]:
				var folder:=current_path.get_base_dir()
				var files: Dictionary=snapshot.get("files",{})
				for path: String in files:
					if path==current_path or path.get_extension().to_lower() not in ["js","jsx","mjs","cjs","ts","tsx"]:continue
					if (folder.is_empty() and path.contains("/")) or (not folder.is_empty() and not path.begins_with(folder+"/")):continue
					project_sources[path]=str(drafts.get(path,files[path].get("text","")))
			window.monaco.show_source(current_path,next_text,project_sources)
			window.syntax.select(window.syntax_modes.find(window.monaco.language_overrides.get(current_path,""))+1)
		if window.has("saved_location"):
			var location: String=_display_workspace_path(current_path) if not current_path.is_empty() else "Unsaved file"
			window.saved_location.text=location
			window.saved_location.tooltip_text=location
			window.reveal_file.disabled=current_path.is_empty() or _file(current_path).is_empty()
		if window.has("tabs"):
			if not current_path.is_empty() and not current_path in window.documents:
				window.documents.append(current_path)
				if window.documents.size()>8:window.documents.pop_front()
			var tabs: TabBar=window.tabs
			_rendering=true
			tabs.clear_tabs()
			for path in window.documents:
				tabs.add_tab(str(path).get_file())
				tabs.set_tab_tooltip(tabs.tab_count-1,_display_workspace_path(str(path)))
			if current_path.is_empty():tabs.add_tab("Untitled")
			var selected: int=window.documents.find(current_path)
			tabs.current_tab=selected if selected>=0 else tabs.tab_count-1
			_rendering=false
		app_window_title.text=(current_path.get_file() if not current_path.is_empty() else "Untitled")+"  ·  "+active_app
	if path_field != null:
		path_field.text = current_path
	if visible:
		var surface: Variant=windows.get(active_app,{}).get("monaco")
		if is_instance_valid(surface) and surface.initialized:surface.grab_focus()
		else:editor.grab_focus()

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
	_open_workspace_file(str(selected.path))

func _open_workspace_file(path: String, preferred := "") -> void:
	if Viewer.app_for(path)!="File Viewer":_preview_path(path);return
	if not _file(path).is_empty():_open_path(path,true,preferred);return
	if path in snapshot.get("folders",[]):_navigate_folder(path);return
	var size: int=snapshot.get("binary_files",{}).get(path,-1)
	if size<0:return
	if FileTypes.is_text(path.get_extension().to_lower()) and size<=VirtualFiles.MAX_FILE_BYTES:
		pending_open_path=path
		pending_open_editor=preferred
		_send({"op":"open_text","path":path})
	else:_preview_path(path)

func _preview_path(path: String) -> void:
	if not pending_web_project.is_empty():return
	if not snapshot.get("binary_files",{}).has(path):
		if _file(path).is_empty():return
		pending_preview=path
		_show_file_preview(path,str(_file(path).text).to_utf8_buffer())
		return
	pending_preview=path
	_send({"op":"read_file","path":path})

func _show_file_preview(path: String, bytes: PackedByteArray) -> void:
	if is_visible_in_tree() and pending_web_project.get("path","")==path:
		_show_web_project(path,bytes)
		return
	if not is_visible_in_tree() or pending_preview!=path:return
	pending_preview=""
	for app: Dictionary in snapshot.get("installed_apps",{}).values():
		if app.archive==path:
			if Apps.sha256(bytes)!=app.sha256:
				_message("Application could not open","The installed package is damaged. Open the original package and choose Repair.")
				return
			_open_installed_app(app,bytes)
			return
	var key:="viewer:"+path
	_capture_draft()
	if windows.has(key):
		file_viewer=windows[key].viewer
		_focus_window(key)
		return
	var app:=Viewer.app_for(path)
	var icon:=_file_icon(path)
	var state:=_create_window(key,app,icon)
	var task:=_button("",func():
		if app_window==state.shell:_minimize_window(key)
		else:_focus_window(key))
	task.icon=icon
	task.add_theme_constant_override("icon_max_width",24)
	task.custom_minimum_size.x=34
	task.tooltip_text=path.get_file()+" · "+app
	task.accessibility_name=task.tooltip_text
	var tray:=start_button.get_parent()
	tray.add_child(task)
	tray.move_child(task,desktop_status.get_index())
	file_viewer=Viewer.new()
	file_viewer.native_enabled=_native_allowed()
	file_viewer.playback_quality=int(snapshot.get("audio_quality",3))
	file_viewer.size_flags_vertical=Control.SIZE_EXPAND_FILL
	state.content.add_child(file_viewer)
	state.viewer=file_viewer
	state.viewer_task=task
	state.title.text=task.tooltip_text
	file_viewer.extract_requested.connect(_archive_entry.bind("extract"))
	file_viewer.install_requested.connect(func(source: String):_install_app(source,bytes))
	file_viewer.run_windows.connect(func(source: String):_confirm_windows_run(source.get_file(),bytes))
	file_viewer.install_windows.connect(func(source: String):_confirm_portable_install(source,bytes))
	file_viewer.run_setup.connect(func(source: String):_confirm_windows_run(source.get_file(),bytes,"",true))
	_focus_window(key)
	file_viewer.show_file(path,bytes)
	_fit_windows.call_deferred()

func _native_allowed() -> bool:
	return is_instance_valid(game) and not game.session.online and snapshot.has("lease") and NativeClient.new().Available()

func _confirm_windows_run(title: String, bytes: PackedByteArray, storage_key: String="", setup := false) -> void:
	if not _native_allowed():
		_message("Windows app unavailable","The isolated Windows runtime requires a local Campus OS session.")
		return
	var info: Dictionary=preload("res://scripts/campus/computers/WindowsExecutableInspector.cs").new().Inspect(bytes)
	if not Apps._supported_windows(info):
		_message("Unsupported Windows app","Use a compatible standalone Windows desktop executable.")
		return
	var lease: Variant=snapshot.lease
	var digest: String=info.sha256
	var details: String=" On success, import standalone executables written to its working folder." if setup else ""
	_confirm_action("Run "+title+" on this PC?\nThe app uses a private Windows desktop with limited file access."+details+"\nSHA-256 "+digest,func():
		if lease==snapshot.get("lease") and is_visible_in_tree() and _native_allowed():_open_windows_runtime(title,bytes,storage_key,setup))

func _open_windows_runtime(title: String, bytes: PackedByteArray, storage_key: String, setup: bool) -> void:
	const key:="native:windows"
	if windows.has(key):
		_focus_window(key)
		return
	var surface:=NativeWindow.new()
	if not surface.start(bytes,storage_key,setup):
		surface.free()
		_message("Windows app unavailable","An isolated runtime is already in use or unavailable.")
		return
	var lease: Variant=snapshot.get("lease")
	surface.output_requested.connect(func(name: String,data: PackedByteArray):
		if lease==snapshot.get("lease") and is_visible_in_tree() and _native_allowed():_browser_save_download(name,data))
	var state:=_create_window(key,"Windows",Icon.icon("component"))
	state.title.text=title
	state.content.add_child(surface)
	surface.size_flags_vertical=Control.SIZE_EXPAND_FILL
	state.native_surface=surface
	var task:=_button(title,func():
		if app_window==state.shell:_minimize_window(key)
		else:_focus_window(key))
	task.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	task.custom_minimum_size.x=90
	task.tooltip_text=title
	var tray:=start_button.get_parent()
	tray.add_child(task)
	tray.move_child(task,desktop_status.get_index())
	state.viewer_task=task
	_focus_window(key)
	_fit_windows.call_deferred()

func _confirm_portable_install(path: String, bytes: PackedByteArray) -> void:
	if not _native_allowed():return
	var digest:=Apps.sha256(bytes)
	var record: Dictionary=snapshot.get("installed_apps",{}).get("windows."+digest.left(32),{})
	var lease: Variant=snapshot.lease
	_confirm_action("Install a portable copy of "+path.get_file()+" on the active virtual drive?",func():
		if lease==snapshot.get("lease") and _native_allowed():
			_send({"op":"install_app","path":path,"sha256":digest,"folder":"win-"+digest.left(17),
				"replace":not record.is_empty(),"shortcut":true,"desktop_shortcut":true}))

func _install_app(path: String, bytes: PackedByteArray) -> void:
	var info:=Apps.Packages.inspect(bytes)
	if info.has("error"):
		_message("Installation unavailable",str(info.error))
		return
	var manifest: Dictionary=info.manifest
	var app: Dictionary=snapshot.get("installed_apps",{}).get(manifest.id,{})
	var setup:=ConfirmationDialog.new()
	setup.title=("Repair "+str(manifest.name)) if app.get("version","")==manifest.version else ("Install "+str(manifest.name)) if app.is_empty() else ("Update "+str(manifest.name))
	setup.ok_button_text="Install" if app.is_empty() else "Replace package"
	var body:=VBoxContainer.new()
	body.custom_minimum_size.x=360
	setup.add_child(body)
	var details:=Label.new()
	details.text="%s · v%s\nPublisher: %s\n%s\n\n%s on the current virtual drive."%[manifest.name,manifest.version,manifest.publisher,manifest.description,String.humanize_size(bytes.size())]
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(details)
	var folder:=LineEdit.new()
	folder.placeholder_text="Installation folder under Program Files"
	folder.max_length=30
	folder.text=str(manifest.id).left(20)+"-"+str(manifest.id).sha256_text().left(8) if app.is_empty() else str(app.archive).get_base_dir().get_file()
	folder.editable=app.is_empty()
	body.add_child(folder)
	var shortcut:=CheckBox.new()
	shortcut.text="Show in Start menu"
	shortcut.button_pressed=app.get("shortcut",true)
	body.add_child(shortcut)
	var desktop_shortcut:=CheckBox.new()
	desktop_shortcut.text="Create desktop shortcut"
	desktop_shortcut.button_pressed=app.get("desktop_shortcut",false)
	body.add_child(desktop_shortcut)
	var separation:=HSeparator.new()
	body.add_child(separation)
	add_child(setup)
	var lease: Variant=snapshot.get("lease")
	setup.confirmed.connect(func():
		if lease==snapshot.get("lease"):
			_send({"op":"install_app","path":path,"sha256":Apps.sha256(bytes),"folder":folder.text,
				"replace":not app.is_empty(),"shortcut":shortcut.button_pressed,"desktop_shortcut":desktop_shortcut.button_pressed})
		setup.queue_free())
	setup.canceled.connect(setup.queue_free)
	setup.popup_centered()

func _refresh_desktop_app_shortcuts() -> void:
	if not is_instance_valid(installed_shortcuts):return
	var links:={}
	for app: Dictionary in snapshot.get("installed_apps",{}).values():
		if app.get("desktop_shortcut",false):links[app.archive]=app.name
	if links==displayed_shortcuts:return
	displayed_shortcuts=links
	for child in installed_shortcuts.get_children():
		installed_shortcuts.remove_child(child)
		child.queue_free()
	installed_shortcuts.get_parent().visible=not links.is_empty()
	for path: String in links:
		var launch:=_button(str(links[path]),_preview_path.bind(path))
		launch.icon=Icon.icon("component")
		launch.flat=true
		launch.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		launch.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		launch.add_theme_constant_override("icon_max_width",48)
		launch.custom_minimum_size=Vector2(104,70)
		launch.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		launch.tooltip_text=launch.text
		installed_shortcuts.add_child(launch)

func _refresh_installed_apps() -> void:
	if not is_instance_valid(installed_apps_view):return
	var apps: Dictionary=snapshot.get("installed_apps",{}).duplicate(true)
	for app: Dictionary in apps.values():app.erase("state")
	if not installed_apps_view.get_children().is_empty() and apps==displayed_apps:return
	displayed_apps=apps
	for row in installed_apps_view.get_children():
		installed_apps_view.remove_child(row)
		row.queue_free()
	if apps.is_empty():
		var empty:=Label.new()
		empty.text="Open a .campusapp package from Files to install it."
		installed_apps_view.add_child(empty)
	for app: Dictionary in apps.values():
		var row:=HBoxContainer.new()
		var title:=Label.new()
		title.text="%s · %s\n%s · %s"%[app.name,app.version,app.publisher,String.humanize_size(app.bytes)]
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(title)
		row.add_child(_button("Open",_preview_path.bind(str(app.archive))))
		row.add_child(_button("Uninstall",_uninstall_app.bind(app)))
		installed_apps_view.add_child(row)

func _uninstall_app(app: Dictionary) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title="Uninstall "+str(app.name)+"?"
	dialog.ok_button_text="Uninstall"
	var keep:=CheckBox.new()
	keep.text="Keep saved application data"
	keep.button_pressed=true
	dialog.add_child(keep)
	add_child(dialog)
	var lease: Variant=snapshot.get("lease")
	dialog.confirmed.connect(func():
		if lease==snapshot.get("lease"):
			var key:="app:"+str(app.id)
			if windows.has(key):
				windows[key].erase("app_record")
				_close_window(key)
			if app.get("runtime")=="windows":
				if windows.has("native:windows"):_close_window("native:windows")
				if not keep.button_pressed and _native_allowed():NativeClient.new().Forget(_native_storage_key(app))
			_send({"op":"uninstall_app","app_id":app.id,"keep_data":keep.button_pressed})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _native_storage_key(app: Dictionary) -> String:
	var volume:=str(snapshot.get("app_volume",""))
	if volume.is_empty():volume=str(snapshot.get("station",""))
	return JSON.stringify([OS.get_user_data_dir(),str(game.school.local_identity),volume,str(app.id)]).sha256_text()

func _open_installed_app(app: Dictionary,bytes: PackedByteArray) -> void:
	if app.get("runtime")=="windows":
		_confirm_windows_run(str(app.name),bytes,_native_storage_key(app))
		return
	var project:=Apps.Packages.open_package(bytes)
	if project.has("error"):
		_message("Application could not open",str(project.error))
		return
	if project.manifest.id!=app.id or not _open_web_window("app:"+str(app.id),str(app.name),str(project.manifest.entry),project.assets,app):
		_message("Application could not open","The package identity or offline project renderer is unavailable.")

func _open_web_window(key: String,title: String,entry: String,assets: Dictionary,app: Dictionary = {}) -> bool:
	if windows.has(key):
		_focus_window(key)
		return true
	if not WebSurface.available():return false
	var web_windows:=0
	for open_key: String in windows:
		if open_key.begins_with("app:") or open_key.begins_with("web:"):web_windows+=1
	if web_windows>=4:return false
	var icon: Texture2D=Icon.icon("component")
	var state:=_create_window(key,title,icon)
	var task:=_button("",func():
		if app_window==state.shell:_minimize_window(key)
		else:_focus_window(key))
	task.icon=icon
	task.tooltip_text=title
	task.accessibility_name=title
	task.add_theme_constant_override("icon_max_width",24)
	var tray:=start_button.get_parent()
	tray.add_child(task)
	tray.move_child(task,desktop_status.get_index())
	state.viewer_task=task
	state.title.text=title
	var browser:=WebSurface.new()
	var toolbar:=HBoxContainer.new()
	state.content.add_child(toolbar)
	toolbar.add_child(_button("Reload",browser.reload_project))
	state.content.add_child(browser)
	state.viewer=browser
	_focus_window(key)
	if not browser.open_project(entry,assets,str(app.get("state",""))):
		_close_window(key)
		return false
	if not app.is_empty():
		state.app_record=app
		state.app_lease=snapshot.get("lease")
		state.app_volume=snapshot.get("app_volume","")
		var storage:=Label.new()
		storage.text="App data · This drive"
		toolbar.add_child(storage)
		var sync:=Timer.new()
		sync.wait_time=1.5
		browser.add_child(sync)
		sync.timeout.connect(func():_save_web_app_state(state))
		sync.start()
	_fit_windows.call_deferred()
	return true

func _save_web_app_state(window: Dictionary) -> void:
	if not window.has("app_record") or window.app_lease!=snapshot.get("lease") or window.app_volume!=snapshot.get("app_volume",""):return
	var app: Dictionary=window.app_record
	var installed: Dictionary=snapshot.get("installed_apps",{}).get(app.id,{})
	if installed.get("sha256","")!=app.sha256:return
	var payload: String=window.viewer.app_state()
	if not Apps.valid_state(payload) or payload==installed.get("state","") or payload==window.get("last_sent_state",""):return
	window.last_sent_state=payload
	_send({"op":"save_app_state","app_id":app.id,"sha256":app.sha256,"state":payload})

func _open_path(path: String, remember := true, preferred := "") -> void:
	if Viewer.app_for(path)!="File Viewer":_preview_path(path);return
	if _file(path).is_empty():return
	var extension:=path.get_extension().to_lower()
	var code_file:=extension in FileTypes.CODE_EXTENSIONS or extension in ["json","jsonl","html","xml","css","yaml","yml","toml","md","svg"]
	_switch_app(preferred if preferred in ["Code editor","Text editor"] else "Code editor" if code_file else "Text editor")
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
	var delayed_op: bool=payload.get("op","") in ["save","mkdir","delete","rename","answer","submit","refresh"]
	if delayed_op and performance.quality<DevicePerformance.MAX:
		if not performance.submit(func():
			if snapshot.is_empty() or snapshot.get("lease")!=payload.lease:return
			payload.revision=snapshot.get("revision",0)
			session.request(payload)):
			status_label.text="Laptop busy. Try again."
		return
	var delay: int = int(tiers.get(tier, {}).get("delay_ms", 0)) if not snapshot.has("performance") else 0
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
	if not pending_web_project.is_empty():
		pending_web_project.finished.call(message)
	if pending_browser_download and is_instance_valid(browser_surface):browser_surface.status.text=message
	pending_browser_download=false
	pending_rename = ""
	pending_folder_source="";pending_folder_target=""
	saving_path=""
	pending_paper_id=0
	pending_open_path=""
	pending_open_editor=""
	pending_preview=""
	pending_web_project.clear()
	pending_run_path=""
	if is_instance_valid(file_list) and file_list.has_meta("pending_location"):file_list.remove_meta("pending_location")
	if not snapshot.is_empty() and is_instance_valid(status_label):
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
	if windows.has("native:windows"):_close_window("native:windows")
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

func _import_local_file() -> void:
	var picker:=FileDialog.new()
	picker.title="Import file to Downloads"
	picker.use_native_dialog=true
	picker.access=FileDialog.ACCESS_FILESYSTEM
	picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	add_child(picker)
	var lease: Variant=snapshot.get("lease")
	picker.file_selected.connect(func(path: String):
		if visible and lease==snapshot.get("lease"):
			var source:=FileAccess.open(path,FileAccess.READ)
			if source==null or source.get_length()>FileTypes.MAX_BYTES:
				_message("Import file","Choose a readable file up to 8 MiB.")
			else:
				_browser_save_download(path.get_file(),source.get_buffer(source.get_length()))
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered(Vector2i(650,440))

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
		performance.configure("",DevicePerformance.MAX)
		pending_app=""
		performance_status.hide()
		preferences_timer.stop()
		if is_instance_valid(execution):execution.stop()
		file_clipboard.clear()
		pending_preview=""
		pending_web_project.clear()
		pending_run_path=""
		for key in windows.keys():
			if windows[key].has("viewer") or windows[key].has("native_surface"):_close_window(key)
		file_viewer=null
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
		_set_volume_open(false)
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
	performance.configure(station,int(value.get("performance",DevicePerformance.MAX)))
	_refresh_desktop_app_shortcuts()
	for key: String in windows.keys():
		var window: Dictionary=windows[key]
		if not window.has("app_record"):continue
		var app: Dictionary=window.app_record
		var installed: Dictionary=snapshot.get("installed_apps",{}).get(app.id,{})
		if window.app_volume!=snapshot.get("app_volume","") or installed.get("sha256","")!=app.sha256:
			window.erase("app_record")
			_close_window(key)
	_refresh_installed_apps()
	_sync_volume_slider()
	if resumed and is_instance_valid(browser_surface):browser_surface.lease=str(snapshot.get("lease",""))
	parked_device=""
	parked_cycle=-1
	var grain:=float(snapshot.get("display_noise",0.0))
	laptop_display_filter.visible=grain>0.0
	var filter:=laptop_display_filter.material as ShaderMaterial
	filter.set_shader_parameter("grain",grain)
	filter.set_shader_parameter("fps",float(snapshot.get("display_fps",60)))
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
		var preferred:=pending_open_editor
		pending_open_path=""
		pending_open_editor=""
		_open_path.call_deferred(new_path,false,preferred)
	if not pending_run_path.is_empty() and not _file(pending_run_path).is_empty():
		var path:=pending_run_path
		pending_run_path=""
		_run_workspace_script.call_deferred(path)
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
	if is_instance_valid(performance) and performance.frozen and visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_request_exit()
		get_viewport().set_input_as_handled()
		return
	if not visible or snapshot.is_empty():
		return
	if volume_popover.visible and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if not volume_popover.get_global_rect().has_point(event.position) and not volume_button.get_global_rect().has_point(event.position):
			_set_volume_open(false)
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
	var focused:=get_viewport().gui_get_focus_owner()
	if active_app=="Files" and is_instance_valid(file_list) and focused==file_list:
		var selected:=_selected_entry()
		if event.ctrl_pressed and event.keycode in [KEY_X,KEY_C] and not selected.is_empty():
			file_clipboard={"path":selected.path,"cut":event.keycode==KEY_X}
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode==KEY_V:
			_paste_entry(folder_path)
			get_viewport().set_input_as_handled()
			return
		if event.keycode==KEY_DELETE and snapshot.get("public_device",false) and not selected.is_empty():
			_delete_path(str(selected.path))
			get_viewport().set_input_as_handled()
			return
	if event.keycode==KEY_ENTER and is_instance_valid(get_viewport().gui_get_focus_owner()) and get_viewport().gui_get_focus_owner() in shortcuts_by_name.values() and not selected_shortcut.is_empty():
		_launch_app(selected_shortcut)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if volume_popover.visible:
			_set_volume_open(false)
			volume_button.grab_focus()
		elif start_panel.visible:start_panel.hide()
		else:_request_exit()
		get_viewport().set_input_as_handled()
	elif event.alt_pressed and event.keycode == KEY_F4 and is_instance_valid(app_window):
		_close_window(str(app_window.get_meta("desktop_app")))
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_file()
		get_viewport().set_input_as_handled()
