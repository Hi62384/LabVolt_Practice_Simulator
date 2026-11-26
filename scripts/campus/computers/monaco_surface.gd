extends TextureRect

signal source_changed(path: String, text: String, kind: String)
signal source_too_large
signal ready_to_edit

const Browser = preload("res://scripts/campus/computers/browser_surface_native.gd")
const AssetServer = preload("res://scripts/campus/computers/EditorAssetServer.cs")
const LANGUAGES := {
	"html":"html","htm":"html","css":"css","scss":"scss","sass":"scss","js":"javascript","mjs":"javascript","cjs":"javascript",
	"jsx":"javascript","ts":"typescript","tsx":"typescript","json":"json","py":"python","pyw":"python","c":"c","h":"c",
	"cpp":"cpp","cc":"cpp","cxx":"cpp","hpp":"cpp","cs":"csharp","java":"java","kt":"kotlin","kts":"kotlin",
	"lua":"lua","rs":"rust","go":"go","rb":"ruby","php":"php","sql":"sql","md":"markdown","sh":"shell","bash":"shell",
	"ps1":"powershell","bat":"bat","cmd":"bat","xml":"xml","svg":"xml","yaml":"yaml","yml":"yaml","ini":"ini",
	"r":"r","dart":"dart","swift":"swift","ex":"elixir","fs":"fsharp","vb":"vb","scala":"scala","v":"verilog"
}

var assets: RefCounted
var browser: Node
var context_key := ""
var url := ""
var token := ""
var documents := {}
var language_overrides := {}
var pending := []
var project_sources: Dictionary = {}
var sent_project_sources: Dictionary = {}
var initialized := false
var started := 0

func start() -> bool:
	if not Browser.ensure_runtime(get_tree()):return false
	var bundle:=FileAccess.get_file_as_bytes("res://assets/campus_monaco_0.55.1.zip")
	var page:=FileAccess.get_file_as_bytes("res://scripts/campus/computers/monaco_editor.html")
	if bundle.is_empty() or page.is_empty():return false
	assets=AssetServer.new()
	url=assets.Start(bundle,page)
	if url.is_empty():return false
	context_key="monaco:"+Crypto.new().generate_random_bytes(16).hex_encode()
	token=Crypto.new().generate_random_bytes(16).hex_encode()
	expand_mode=EXPAND_IGNORE_SIZE
	size_flags_vertical=SIZE_EXPAND_FILL
	focus_mode=FOCUS_ALL
	browser=Browser.runtime.create_browser("about:blank",self,{"session_key":context_key,"allow_downloads":false,"javascript":true,"javascript_access_clipboard":false,"frame_rate":30}) as Node
	if not is_instance_valid(browser):return false
	browser.register_method(self,"_campus_monaco_report")
	browser.load_url(url)
	started=Time.get_ticks_msec()
	resized.connect(func():browser.resize(size.max(Vector2(1,1))))
	gui_input.connect(_forward)
	focus_entered.connect(func():if initialized:browser.execute_javascript("window.campusEditorFocus()"))
	return true

func _process(_delta: float) -> void:
	if initialized or not is_instance_valid(browser):return
	if browser.get_url()==url and browser.get_title()=="Campus editor ready":
		initialized=true
		_show_source()
		ready_to_edit.emit()
	elif Time.get_ticks_msec()-started>10000:
		set_process(false)

func show_source(path: String, value: String, sources: Dictionary = {}) -> void:
	var id:=path.sha256_text().left(24)
	documents[id]=path
	pending=[id,path,language_overrides.get(path,LANGUAGES.get(path.get_extension().to_lower(),"plaintext")),value,token]
	project_sources=sources
	_show_source()

func _show_source() -> void:
	if initialized and not pending.is_empty():
		browser.execute_javascript("window.campusSource(...%s)"%JSON.stringify(pending))
		if project_sources!=sent_project_sources:
			sent_project_sources=project_sources
			browser.execute_javascript("window.campusProjectSources(%s)"%JSON.stringify(project_sources))

func action(name: String) -> void:
	if initialized:browser.execute_javascript("window.campusEditorAction(%s)"%JSON.stringify(name))

func set_language(path: String,language: String) -> void:
	language_overrides[path]=language
	if initialized:browser.execute_javascript("window.campusEditorLanguage(%s)"%JSON.stringify(language))

func submit_source(kind: String) -> void:
	if initialized:browser.execute_javascript("window.campusSubmitSource(%s)"%JSON.stringify(kind))

func _campus_monaco_report(raw: Variant) -> void:
	if not initialized or not is_instance_valid(browser) or browser.get_url()!=url or not raw is String or raw.length()>45000:return
	var result: Variant=JSON.parse_string(raw)
	if not result is Dictionary or result.get("token")!=token or not documents.has(result.get("id","")):return
	var kind: String=str(result.get("kind",""))
	if kind=="limit":source_too_large.emit();return
	if kind not in ["edit","save","run"] or not result.get("text") is String:return
	var bytes:=Marshalls.base64_to_raw(result.text)
	var value:=bytes.get_string_from_utf8()
	if bytes.size()<=32768 and value.to_utf8_buffer()==bytes:
		source_changed.emit(documents[result.id],value,kind)

func _forward(event: InputEvent) -> void:
	if not initialized:return
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
		if event.unicode>=32 and event.unicode!=127 and not event.meta_pressed and not (event.ctrl_pressed and not event.alt_pressed):key=event.unicode
		if key!=KEY_NONE:browser.set_key_pressed(key,event.pressed,event.shift_pressed,event.alt_pressed,event.ctrl_pressed)
		accept_event()

func _exit_tree() -> void:
	if is_instance_valid(browser):browser.close()
	if not context_key.is_empty() and is_instance_valid(Browser.runtime):Browser.runtime.release_context(context_key)
	if assets!=null:assets.Stop()
