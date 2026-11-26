extends TextureRect

const Browser = preload("res://scripts/campus/computers/browser_surface_native.gd")
const ORIGIN := "https://campus-app.invalid/"
const STATE_PATH := "__campus__/state.json"
var browser: Node
var context_key := ""
var entry_url := ""

static func available() -> bool:
	return DisplayServer.get_name()!="headless" and ClassDB.class_exists("GdBrowserView") and ClassDB.class_has_method("GdBrowserView","is_offline_project")

func open_project(entry: String, assets: Dictionary, initial_state: String = "") -> bool:
	if not available() or not assets.has(entry) or not Browser.ensure_runtime(get_tree()):return false
	if not initial_state.is_empty() and not ClassDB.class_has_method("GdBrowserView","get_offline_state"):return false
	var files:=assets.duplicate()
	files.erase(STATE_PATH)
	if not initial_state.is_empty():files[STATE_PATH]=initial_state.to_utf8_buffer()
	context_key="offline:"+Crypto.new().generate_random_bytes(16).hex_encode()
	entry_url=ORIGIN+entry.uri_encode().replace("%2F","/")
	expand_mode=EXPAND_IGNORE_SIZE
	size_flags_vertical=SIZE_EXPAND_FILL
	focus_mode=FOCUS_ALL
	browser=Browser.runtime.create_browser(entry_url,self,{"session_key":context_key,
		"offline_files":files,"allow_downloads":false,"javascript":true,"javascript_access_clipboard":false,
		"javascript_dom_paste":false,"frame_rate":30}) as Node
	if not is_instance_valid(browser) or not browser.is_offline_project():return false
	resized.connect(func():browser.resize(size.max(Vector2(1,1))))
	gui_input.connect(_forward)
	return true

func reload_project() -> void:
	if is_instance_valid(browser):browser.load_url(entry_url)

func app_state() -> String:
	return browser.get_offline_state() if is_instance_valid(browser) and browser.has_method("get_offline_state") else ""

func _forward(event: InputEvent) -> void:
	if not is_instance_valid(browser):return
	if event is InputEventMouse:
		browser.set_mouse_moved(roundi(event.position.x),roundi(event.position.y))
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			grab_focus()
			if event.pressed:browser.set_mouse_left_down()
			else:browser.set_mouse_left_up()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			browser.set_mouse_wheel_vertical(120 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -120,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
		accept_event()
	elif event is InputEventKey:
		var key: int=event.keycode if event.keycode!=KEY_NONE else event.physical_keycode
		if (event.ctrl_pressed or event.meta_pressed) and key in [KEY_C,KEY_V,KEY_X,KEY_INSERT] or event.shift_pressed and key in [KEY_INSERT,KEY_DELETE]:
			accept_event()
			return
		if event.unicode>=32 and event.unicode!=127 and not event.meta_pressed and not (event.ctrl_pressed and not event.alt_pressed):key=event.unicode
		if key!=KEY_NONE:browser.set_key_pressed(key,event.pressed,event.shift_pressed,event.alt_pressed,event.ctrl_pressed)
		accept_event()

func _exit_tree() -> void:
	if is_instance_valid(browser):browser.close()
	if not context_key.is_empty() and is_instance_valid(Browser.runtime):Browser.runtime.release_context(context_key)
