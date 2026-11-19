extends VBoxContainer
## Windows gdCEF browser. The process runtime is retained; each device session
## closes its own tabs, renderer surfaces and attachment capability.
const MAX_ATTACHMENT_BYTES:=8*1024*1024
const MAX_TABS:=8
const HOME_URL:="https://www.google.com/"
const Policy=preload("res://scripts/campus/ai/browser_assistant_policy.gd")
const Downloads=preload("res://scripts/campus/computers/browser_download.gd")
const WAV=preload("res://scripts/campus/academics/teacher_ai.gd")
static var runtime: Node
static var next_session_serial:=0
var attachment_loader: Callable
var assistant_virtual_save: Callable
var virtual_download_save: Callable
var download_request: HTTPRequest
var download_dialog: ConfirmationDialog
var game: Node
var device_kind:=""
var device_id:=""
var lease:=""
var session_key:=""
var candidates: Array=[]
var selected_attachment: Dictionary={}
var tabs: Array=[]
var active:=0
var address: LineEdit
var tab_row: HFlowContainer
var back: Button
var forward: Button
var holder: Control
var status: Label
var home_screen: VBoxContainer
var attachment: Label
var assistant_panel: VBoxContainer
var assistant_input: LineEdit
var assistant_answer: Label
var assistant_action_button: Button
var assistant_download_button: Button
var assistant_virtual_button: Button
var assistant_record_button: Button
var assistant_pending: Dictionary={}
var assistant_action: Dictionary={}
var assistant_response: String=""
var assistant_serial:=0
var record_player: AudioStreamPlayer
var record_samples:=PackedByteArray()
var record_phase:=0.0
var record_started:=0
var recording:=false

func _ready() -> void:
 get_viewport().size_changed.connect(_resize_tabs)

func _process(_delta: float) -> void:
 _record_step()
 _assistant_check_title()
 _check_page_download()
 if not is_instance_valid(back) or not is_instance_valid(forward):return
 var browser: Variant=_browser()
 back.disabled=browser==null or not browser.has_previous_page()
 forward.disabled=browser==null or not browser.has_next_page()

func _unhandled_key_input(event: InputEvent) -> void:
 if not is_visible_in_tree() or device_kind.is_empty() or not event is InputEventKey or not event.pressed or event.echo:return
 if device_kind=="computer":
  var window: Node=self
  while window!=null and not window.has_meta("desktop_app"):window=window.get_parent()
  if window==null or window!=window.get_parent().get_child(-1):return
 if event.ctrl_pressed:
  match event.keycode:
   KEY_L:address.grab_focus();address.select_all()
   KEY_T:_add_tab()
   KEY_W:_close_tab()
   KEY_R:
    if _browser()!=null:_browser().reload()
   _:return
 elif event.alt_pressed and event.keycode in [KEY_LEFT,KEY_RIGHT]:
  _history(-1 if event.keycode==KEY_LEFT else 1)
 else:return
 get_viewport().set_input_as_handled()

func configure(kind: String,id: String,session_lease: String,items: Array) -> void:
 close_session()
 device_kind=kind;device_id=id;lease=session_lease
 next_session_serial+=1
 session_key="%s:%s:%s:%d"%[kind,id,session_lease,next_session_serial]
 for item in items:
  if not item is Dictionary:continue
  if int(item.get("bytes",-1))<0 or int(item.get("bytes",-1))>MAX_ATTACHMENT_BYTES or str(item.get("name","")).is_empty():continue
  if kind=="phone" and item.get("kind","")!="photo":continue
  if kind=="computer" and item.get("kind","")!="virtual_file":continue
  candidates.append(item.duplicate(true))
 _build()

func close_session() -> void:
 _cancel_recording()
 if is_instance_valid(download_request):
  download_request.cancel_request()
  download_request.queue_free()
 download_request=null
 if is_instance_valid(download_dialog):download_dialog.queue_free()
 download_dialog=null
 virtual_download_save=Callable()
 assistant_pending.clear();assistant_action.clear();assistant_response=""
 if is_instance_valid(game) and is_instance_valid(game.browser_assistant) and game.browser_assistant.reply_received.is_connected(_assistant_reply):game.browser_assistant.reply_received.disconnect(_assistant_reply)
 for tab in tabs:
  if is_instance_valid(tab.browser):tab.browser.close()
 if not session_key.is_empty() and is_instance_valid(runtime) and runtime.has_method("release_context"):runtime.release_context(session_key)
 tabs.clear();active=0;device_kind="";device_id="";lease="";session_key="";candidates.clear();selected_attachment.clear();attachment_loader=Callable();assistant_virtual_save=Callable()
 for child in get_children():remove_child(child);child.queue_free()

func _exit_tree() -> void:
 tabs.clear()

func attachment_bytes() -> PackedByteArray:
 if selected_attachment.is_empty() or not attachment_loader.is_valid():return PackedByteArray()
 var data: Variant=attachment_loader.call(device_kind,device_id,lease,selected_attachment.duplicate(true))
 return data if data is PackedByteArray and data.size()<=MAX_ATTACHMENT_BYTES else PackedByteArray()

func renderer_available() -> bool:
 return is_instance_valid(runtime) and runtime.is_alive() and not tabs.is_empty()

func _build() -> void:
 var chrome:=VBoxContainer.new();chrome.add_theme_constant_override("separation",4);add_child(chrome)
 tab_row=HFlowContainer.new();tab_row.add_theme_constant_override("h_separation",3);chrome.add_child(tab_row)
 var nav:=HBoxContainer.new();nav.add_theme_constant_override("separation",4);chrome.add_child(nav)
 back=Button.new();back.text="‹";back.tooltip_text="Back";back.accessibility_name="Back";back.pressed.connect(func():_history(-1));nav.add_child(back)
 forward=Button.new();forward.text="›";forward.tooltip_text="Forward";forward.accessibility_name="Forward";forward.pressed.connect(func():_history(1));nav.add_child(forward)
 var reload:=Button.new();reload.text="↻";reload.tooltip_text="Reload";reload.accessibility_name="Reload";reload.pressed.connect(func():if _browser()!=null:_browser().reload());nav.add_child(reload)
 var home:=Button.new();home.text="⌂";home.tooltip_text="Home";home.accessibility_name="Home";home.pressed.connect(_home);nav.add_child(home)
 address=LineEdit.new();address.placeholder_text="Search or enter address";address.max_length=2048;address.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if device_kind=="phone":chrome.add_child(address)
 else:nav.add_child(address)
 address.text_submitted.connect(func(_text):_navigate())
 var menu:=MenuButton.new();menu.text="⋯";menu.tooltip_text="Browser tools";menu.accessibility_name="Browser tools";nav.add_child(menu)
 var popup:=menu.get_popup()
 popup.add_item("Attach photo" if device_kind=="phone" else "Attach virtual file",0)
 popup.add_item("Assistant",1)
 if device_kind=="computer":popup.add_item("Download address to virtual files",2)
 popup.id_pressed.connect(func(id: int):
  if id==0:_choose_attachment()
  elif id==1 and is_instance_valid(assistant_panel):assistant_panel.visible=not assistant_panel.visible
  elif id==2:_download_address())
 attachment=Label.new();attachment.add_theme_font_size_override("font_size",12);chrome.add_child(attachment)
 holder=Control.new();holder.clip_contents=true;holder.custom_minimum_size.y=220 if device_kind=="phone" else 180;holder.size_flags_horizontal=Control.SIZE_EXPAND_FILL;holder.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(holder)
 home_screen=VBoxContainer.new();home_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);home_screen.alignment=BoxContainer.ALIGNMENT_CENTER;home_screen.add_theme_constant_override("separation",12);holder.add_child(home_screen)
 var home_title:=Label.new();home_title.text="Campus Browser";home_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;home_title.add_theme_font_size_override("font_size",30);home_screen.add_child(home_title)
 var home_subtitle:=Label.new();home_subtitle.text="Enter a website or search in the address bar above.";home_subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;home_subtitle.add_theme_color_override("font_color",Color("b6cad4"));home_screen.add_child(home_subtitle)
 var quick:=HBoxContainer.new();quick.alignment=BoxContainer.ALIGNMENT_CENTER;quick.add_theme_constant_override("separation",10);home_screen.add_child(quick)
 for site in [{"label":"Google","url":"https://www.google.com"},{"label":"Wikipedia","url":"https://www.wikipedia.org"}]:
  var shortcut:=Button.new();shortcut.text=str(site.label);shortcut.pressed.connect(func():address.text=str(site.url);_navigate());quick.add_child(shortcut)
 status=Label.new();status.mouse_filter=Control.MOUSE_FILTER_IGNORE
 status.add_theme_color_override("font_color",Color("ffe1bc"))
 status.add_theme_font_size_override("font_size",12)
 status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 status.offset_top=-25;status.offset_left=6;status.offset_right=-6
 status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 status.z_index=2
 holder.add_child(status)
 assistant_panel=VBoxContainer.new();assistant_panel.hide();add_child(assistant_panel)
 var privacy:=Label.new();privacy.text="Ask about this page. Visible page text, your question and chosen attachment go through the host to OpenAI.";privacy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;assistant_panel.add_child(privacy)
 assistant_input=LineEdit.new();assistant_input.placeholder_text="Ask about the current page";assistant_input.max_length=Policy.MAX_QUESTION;assistant_input.text_submitted.connect(func(_value: String):_assistant_ask());assistant_panel.add_child(assistant_input)
 var controls:=HFlowContainer.new();assistant_panel.add_child(controls)
 var ask:=Button.new();ask.text="Ask";ask.pressed.connect(_assistant_ask);controls.add_child(ask)
 assistant_record_button=Button.new();assistant_record_button.text="Record question";assistant_record_button.pressed.connect(_toggle_recording);controls.add_child(assistant_record_button)
 assistant_answer=Label.new();assistant_answer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;assistant_answer.custom_minimum_size.y=36;assistant_panel.add_child(assistant_answer)
 assistant_action_button=Button.new();assistant_action_button.text="Apply suggested page action";assistant_action_button.hide();assistant_action_button.pressed.connect(_assistant_apply_action);assistant_panel.add_child(assistant_action_button)
 assistant_download_button=Button.new();assistant_download_button.text="Download answer";assistant_download_button.hide();assistant_download_button.pressed.connect(_assistant_download);assistant_panel.add_child(assistant_download_button)
 if device_kind=="computer":
  assistant_virtual_button=Button.new();assistant_virtual_button.text="Save to virtual files";assistant_virtual_button.hide();assistant_virtual_button.pressed.connect(_assistant_save_virtual);assistant_panel.add_child(assistant_virtual_button)
 if is_instance_valid(game) and is_instance_valid(game.browser_assistant) and not game.browser_assistant.reply_received.is_connected(_assistant_reply):game.browser_assistant.reply_received.connect(_assistant_reply)
 if not _runtime_ready():status.text="Chromium could not start. Check the installed browser files and restart the game.";_refresh();return
 _add_tab()

func _runtime_ready() -> bool:
 if is_instance_valid(runtime):return runtime.is_alive()
 if OS.get_name()!="Windows":return false
 var cef_class:="GdCEF"
 if not ClassDB.class_exists(cef_class):return false
 runtime=ClassDB.instantiate(cef_class) as Node
 if not is_instance_valid(runtime):return false
 runtime.name="LabVoltCEF";get_tree().root.add_child(runtime)
 if not runtime.initialize({"incognito":true,"root_cache_path":ProjectSettings.globalize_path("user://cef_cache_root"),"remote_debugging_port":0,"enable_media_stream":false,"use_gpu":false,"log_file":ProjectSettings.globalize_path("user://cef.log"),"log_severity":"warning"}):
  runtime.queue_free();runtime=null;return false
 return true

func _add_tab() -> void:
 if not is_instance_valid(runtime) or tabs.size()>=MAX_TABS:return
 var surface:=TextureRect.new();surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);surface.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;surface.stretch_mode=TextureRect.STRETCH_SCALE;surface.focus_mode=Control.FOCUS_ALL;holder.add_child(surface)
 var browser: Variant=runtime.create_browser(HOME_URL if device_kind=="computer" else "about:blank",surface,{"allow_downloads":false,"javascript":true,"javascript_access_clipboard":false,"session_key":session_key})
 if not is_instance_valid(browser):surface.queue_free();status.text="Browser tab failed: "+str(runtime.get_error());return
 tabs.append({"browser":browser,"surface":surface,"title":"New tab"});active=tabs.size()-1
 var browser_ref: WeakRef=weakref(browser)
 browser.connect("on_page_loaded",func(_view,_http_code):if browser_ref.get_ref()!=null:_loaded(browser_ref.get_ref()))
 browser.connect("on_page_failed_loading",func(_code,message,_view):if browser_ref.get_ref()==_browser():
  status.text="Connection failed · "+str(message).left(120)
  if device_kind=="computer":home_screen.hide())
 surface.gui_input.connect(func(event):if browser_ref.get_ref()!=null:_forward(browser_ref.get_ref(),surface,event))
 surface.resized.connect(func():if browser_ref.get_ref()!=null:_resize_browser(browser_ref.get_ref(),surface))
 _resize_browser(browser,surface);_refresh()

func _desktop_pixel_scale() -> Vector2:
 var desktop_viewport:=get_viewport() as SubViewport
 if desktop_viewport==null or not desktop_viewport.size_2d_override_stretch:return Vector2.ONE
 var logical:=desktop_viewport.size_2d_override
 if logical.x<2 or logical.y<2:return Vector2.ONE
 return Vector2(desktop_viewport.size)/Vector2(logical)

func _resize_tabs() -> void:
 for tab in tabs:
  if is_instance_valid(tab.browser) and is_instance_valid(tab.surface):_resize_browser(tab.browser,tab.surface)

func _resize_browser(browser: Variant,surface: TextureRect) -> void:
 if surface.size.x<2 or surface.size.y<2:return
 var scale_factor:=_desktop_pixel_scale()
 browser.resize((surface.size*scale_factor).round())
 browser.set_zoom_level(log(scale_factor.x)/log(1.2))

func parked_tabs() -> Dictionary:
 var urls: Array[String]=[]
 for tab in tabs:
  if is_instance_valid(tab.browser):urls.append(str(tab.browser.get_url()))
 return {"urls":urls,"active":active}

func restore_parked_tabs(record: Dictionary) -> void:
 if tabs.is_empty():return
 var urls: Array=record.get("urls",[])
 for index in mini(urls.size(),MAX_TABS):
  if index>=tabs.size():_add_tab()
  if index>=tabs.size():break
  var url := str(urls[index])
  if url.begins_with("https://") or url.begins_with("http://"):
   tabs[index].browser.load_url(url)
 active=clampi(int(record.get("active",0)),0,tabs.size()-1)
 _refresh()

func _browser() -> Variant:
 if active<0 or active>=tabs.size():return null
 return tabs[active].browser if is_instance_valid(tabs[active].browser) else null

func _refresh() -> void:
 if not is_instance_valid(tab_row):return
 for child in tab_row.get_children():tab_row.remove_child(child);child.queue_free()
 for i in tabs.size():
  var index:=i
  var shell:=PanelContainer.new()
  var skin:=StyleBoxFlat.new()
  skin.bg_color=Color("405369") if i==active else Color("2b3b50")
  skin.corner_radius_top_left=8;skin.corner_radius_top_right=8
  skin.content_margin_left=3;skin.content_margin_right=3
  shell.add_theme_stylebox_override("panel",skin)
  tab_row.add_child(shell)
  var line:=HBoxContainer.new()
  line.add_theme_constant_override("separation",2)
  shell.add_child(line)
  var button:=Button.new()
  button.flat=true
  var browser: Variant=tabs[i].browser
  var url:=str(browser.get_url()) if is_instance_valid(browser) else ""
  var glyph:="G" if url.begins_with(HOME_URL) else "◎"
  button.text=glyph+"  "+str(tabs[i].title).left(12 if device_kind=="phone" else 22)
  button.pressed.connect(func():active=index;status.text="";_refresh())
  line.add_child(button)
  var stop:=Button.new();stop.flat=true;stop.text="×";stop.tooltip_text="Close tab"
  stop.disabled=tabs.size()<=1;stop.pressed.connect(func():_close_tab_at(index));line.add_child(stop)
 var plus:=Button.new();plus.text="+";plus.disabled=tabs.size()>=MAX_TABS or not is_instance_valid(runtime);plus.pressed.connect(_add_tab);tab_row.add_child(plus)
 for i in tabs.size():tabs[i].surface.visible=i==active
 var browser: Variant=_browser()
 if is_instance_valid(home_screen):home_screen.visible=device_kind!="computer" and (browser==null or str(browser.get_url())=="about:blank")
 address.text=str(browser.get_url()) if browser!=null and str(browser.get_url())!="about:blank" else ""
 back.disabled=browser==null or not browser.has_previous_page()
 forward.disabled=browser==null or not browser.has_next_page()
 attachment.visible=not selected_attachment.is_empty()
 attachment.text="Attachment · "+str(selected_attachment.get("name",""))

func _close_tab() -> void:
 _close_tab_at(active)

func _close_tab_at(index: int) -> void:
 if tabs.size()<=1 or index<0 or index>=tabs.size():return
 var tab: Dictionary=tabs[index]
 if is_instance_valid(tab.browser):tab.browser.close()
 if is_instance_valid(tab.surface):tab.surface.queue_free()
 tabs.remove_at(index)
 if index<active:active-=1
 active=mini(active,tabs.size()-1)
 _refresh()

func _home() -> void:
 var browser: Variant=_browser()
 if browser==null:return
 browser.load_url(HOME_URL if device_kind=="computer" else "about:blank")
 if is_instance_valid(home_screen):home_screen.visible=device_kind!="computer"
 address.clear()
 status.text=""

func _input(event: InputEvent) -> void:
 if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
 if not is_instance_valid(address):return
 var focused:=get_viewport().gui_get_focus_owner()
 var hovered:=get_viewport().gui_get_hovered_control()
 if focused!=address and not is_ancestor_of(focused) and not is_ancestor_of(hovered):return
 if event.ctrl_pressed:
  match event.keycode:
   KEY_L:address.grab_focus();address.select_all()
   KEY_T:_add_tab()
   KEY_W:_close_tab()
   KEY_R:
    var browser: Variant=_browser()
    if browser!=null:browser.reload()
   _:return
  get_viewport().set_input_as_handled()

func _navigate() -> void:
 var url:=address.text.strip_edges()
 if not url.contains("://"):
  url="https://"+url if url.contains(".") else "https://www.google.com/search?q="+url.uri_encode()
 var host:=url.trim_prefix("https://").trim_prefix("http://").get_slice("/",0)
 if url.length()>2048 or not (url.begins_with("https://") or url.begins_with("http://")) or host.is_empty() or url.contains(" "):status.text="Enter a valid http:// or https:// address.";return
 var browser: Variant=_browser()
 if browser!=null:
  if is_instance_valid(home_screen):home_screen.hide()
  browser.load_url(url);status.text="Loading "+url.left(100)

func _history(direction: int) -> void:
 var browser: Variant=_browser()
 if browser==null:return
 if direction<0 and browser.has_previous_page():browser.previous_page()
 if direction>0 and browser.has_next_page():browser.next_page()

func _loaded(browser: Variant) -> void:
 for i in tabs.size():
  if tabs[i].browser!=browser:continue
  tabs[i].title=str(browser.get_title()) if not str(browser.get_title()).is_empty() else str(browser.get_url()).left(24)
  browser.execute_javascript(_upload_script())
  if device_kind=="computer":
   var token: String=tabs[i].get("page_download",{}).get("token","")
   if token.is_empty():token=Crypto.new().generate_random_bytes(12).hex_encode()
   tabs[i].page_download={"token":token,"index":0,"parts":PackedStringArray(),"length":0,"last":0}
   browser.execute_javascript(Downloads.page_script(token))
  if i==active:status.text="";_refresh()
  return

func _check_page_download() -> void:
 if not virtual_download_save.is_valid() or tabs.is_empty():return
 var tab: Dictionary=tabs[active]
 if not tab.has("page_download") or not is_instance_valid(tab.browser):return
 var transfer: Dictionary=tab.page_download
 var title:=str(tab.browser.get_title())
 var prefix: String="__LVD__"+transfer.token+"|"
 if not title.begins_with(prefix):return
 var pieces:=title.substr(prefix.length()).split("|",true,2)
 if pieces.size()!=3 or pieces[1] not in ["0","1"] or not pieces[0].is_valid_int() or int(pieces[0])!=int(transfer.index):return
 if transfer.index==0:transfer.last=Time.get_ticks_msec()
 var piece: String=pieces[2]
 var max_wire:=Downloads.MAX_BYTES*2
 if piece.length()>Downloads.PAGE_CHUNK or int(transfer.length)+piece.length()>max_wire or Time.get_ticks_msec()-int(transfer.last)>20000:
  _finish_page_report(tab,transfer)
  status.text="The page download exceeded its transfer limit."
  return
 transfer.parts.append(piece)
 transfer.length+=piece.length()
 if pieces[1]=="0":
  transfer.index+=1
  tab.browser.execute_javascript("window.__labvoltDownload?.(%s,%d)"%[JSON.stringify(transfer.token),transfer.index])
  return
 var payload: Variant=JSON.parse_string(Marshalls.base64_to_raw("".join(transfer.parts)).get_string_from_utf8())
 _finish_page_report(tab,transfer)
 if not payload is Dictionary:return
 if payload.has("error"):
  status.text=str(payload.error).left(120)
  return
 var extension: String=Downloads.EXTENSIONS.get(str(payload.get("mime","")),"")
 var body:=Marshalls.base64_to_raw(str(payload.get("data","")))
 if not Downloads.valid(body,extension):
  status.text="The page offered an unsupported or invalid file."
  return
 if is_instance_valid(download_dialog):return
 var filename:=Downloads.filename(str(payload.get("name","")).left(128),extension)
 var origin:=str(tab.browser.get_url()).get_slice("://",0)+"://"+str(tab.browser.get_url()).get_slice("://",1).get_slice("/",0)
 var expected_session:=session_key
 download_dialog=ConfirmationDialog.new()
 download_dialog.title="Save website download"
 download_dialog.dialog_text="%s offered %s (%d bytes). Save it to virtual Downloads?"%[origin.left(85),filename,body.size()]
 download_dialog.ok_button_text="Save"
 add_child(download_dialog)
 download_dialog.confirmed.connect(func():
  if session_key==expected_session and virtual_download_save.is_valid():
   status.text="Saving to Downloads…"
   virtual_download_save.call(filename,body)
 )
 download_dialog.confirmed.connect(download_dialog.queue_free)
 download_dialog.canceled.connect(download_dialog.queue_free)
 download_dialog.popup_centered()

func _finish_page_report(tab: Dictionary,transfer: Dictionary) -> void:
 # Block duplicate reads until CEF has acknowledged the report.
 transfer.index=-1
 transfer.parts=PackedStringArray()
 transfer.length=0
 var token: String=transfer.token
 tab.browser.execute_javascript("window.__labvoltDownload?.(%s,-1)"%JSON.stringify(token))
 _reset_page_report(tab,token)

func _reset_page_report(tab: Dictionary,token: String) -> void:
 await get_tree().create_timer(.2).timeout
 if tab.get("page_download",{}).get("token")==token:tab.page_download.index=0

func _download_address() -> void:
 if not virtual_download_save.is_valid():status.text="This computer has no Downloads folder.";return
 if is_instance_valid(download_request):status.text="A download is already in progress.";return
 var url:=address.text.strip_edges()
 if not (url.begins_with("https://") or url.begins_with("http://")) or url.length()>2048:
  status.text="Enter a direct HTTP or HTTPS file address."
  return
 var request:=HTTPRequest.new()
 request.body_size_limit=Downloads.MAX_BYTES
 request.max_redirects=0
 request.accept_gzip=false
 request.timeout=15.0
 add_child(request)
 download_request=request
 request.request_completed.connect(_download_finished.bind(url,session_key,request),CONNECT_ONE_SHOT)
 if request.request(url)!=OK:
  _download_finished(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray(),url,session_key,request)
 else:status.text="Downloading to this computer…"

func _download_finished(result: int,code: int,headers: PackedStringArray,body: PackedByteArray,url: String,session_id: String,request: HTTPRequest) -> void:
 request.queue_free()
 if request!=download_request:return
 download_request=null
 if session_id!=session_key or not virtual_download_save.is_valid():return
 if result==HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
  status.text="The file exceeds this computer's 256 KB download limit."
  return
 if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
  status.text="Could not download this address. Use a direct file link."
  return
 var mime:=""
 for header in headers:
  if header.get_slice(":",0).strip_edges().to_lower()=="content-type":
   mime=header.substr(header.find(":")+1).get_slice(";",0).strip_edges().to_lower()
 var extension: String=Downloads.EXTENSIONS.get(mime,"")
 if not Downloads.valid(body,extension):
  status.text="Unsupported or invalid file. Text files are limited to 32 KB."
  return
 var filename:=Downloads.filename(url.get_slice("?",0).get_slice("#",0).uri_decode(),extension)
 status.text="Saving to Downloads…"
 virtual_download_save.call(filename,body)

func _forward(browser: Variant,surface: TextureRect,event: InputEvent) -> void:
 if browser!=_browser() or not is_instance_valid(browser):return
 if event is InputEventMouseMotion:
  var point: Vector2=(event.position*_desktop_pixel_scale()).round()
  browser.set_mouse_moved(int(point.x),int(point.y))
 elif event is InputEventMouseButton:
  var point: Vector2=(event.position*_desktop_pixel_scale()).round()
  surface.grab_focus();browser.set_mouse_moved(int(point.x),int(point.y))
  if event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed:browser.set_mouse_left_down()
   else:browser.set_mouse_left_up()
  elif event.button_index==MOUSE_BUTTON_RIGHT:
   if event.pressed:browser.set_mouse_right_down()
   else:browser.set_mouse_right_up()
  elif event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:browser.set_mouse_wheel_vertical(1,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
  elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:browser.set_mouse_wheel_vertical(-1,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
 elif event is InputEventKey:
  if event.keycode in [KEY_SHIFT,KEY_ALT,KEY_CTRL,KEY_META,KEY_CAPSLOCK,KEY_NUMLOCK,KEY_SCROLLLOCK]:return
  # Godot's keycode names letters in uppercase. Unicode is the character
  # already resolved by the OS keyboard layout, Shift and Caps Lock.
  var key: int=event.keycode if event.keycode!=KEY_NONE else event.physical_keycode
  if event.unicode>=32 and event.unicode!=127 and not event.meta_pressed and not (event.ctrl_pressed and not event.alt_pressed):
   key=event.unicode
  if key!=KEY_NONE:browser.set_key_pressed(key,event.pressed,event.shift_pressed,event.alt_pressed,event.ctrl_pressed)

func _choose_attachment(browser: Variant=null) -> void:
 if not is_instance_valid(browser):browser=_browser()
 var picker:=ConfirmationDialog.new();picker.title="Choose a phone photo" if device_kind=="phone" else "Choose a virtual file";picker.ok_button_text="Select";add_child(picker)
 var list:=ItemList.new();list.custom_minimum_size=Vector2(330,250);picker.add_child(list)
 for item in candidates:list.add_item("%s · %.1f KB"%[item.name,float(item.bytes)/1024.0])
 picker.get_ok_button().disabled=true
 list.item_selected.connect(func(_index):picker.get_ok_button().disabled=false)
 picker.confirmed.connect(func():
  var selected:=list.get_selected_items()
  if not selected.is_empty():
   selected_attachment=candidates[int(selected[0])].duplicate(true);_refresh()
   if is_instance_valid(browser):_supply_upload(browser)
  picker.queue_free())
 picker.canceled.connect(func():picker.queue_free());picker.popup_centered()

func _supply_upload(browser: Variant) -> void:
 if browser!=_browser():return
 var data:=attachment_bytes()
 if data.is_empty():status.text="Selected attachment is unavailable.";return
 var name:=str(selected_attachment.get("name","attachment")).get_file()
 var extension:=name.get_extension().to_lower()
 var mime:="application/octet-stream"
 if extension in ["jpg","jpeg"]:mime="image/jpeg"
 elif extension=="png":mime="image/png"
 elif extension=="webp":mime="image/webp"
 elif extension=="gif":mime="image/gif"
 elif extension=="txt":mime="text/plain"
 elif extension=="pdf":mime="application/pdf"
 browser.execute_javascript("window.__labvoltUpload("+JSON.stringify({"name":name,"mime":mime,"data":Marshalls.raw_to_base64(data)})+");")
 status.text="Attachment selected. Use the page's upload or submit control."

func _upload_script() -> String:
 return """(function(){if(window.__labvoltUpload)return;let pending=null;function choose(input){pending=input;input.style.outline='2px solid #55cdaa';}document.addEventListener('click',function(e){let input=e.target;if(!(input instanceof HTMLInputElement)||input.type!=='file')return;e.preventDefault();e.stopImmediatePropagation();choose(input);},true);let oldClick=HTMLInputElement.prototype.click;HTMLInputElement.prototype.click=function(){if(this.type==='file'){choose(this);return;}return oldClick.call(this);};if(HTMLInputElement.prototype.showPicker){let oldPicker=HTMLInputElement.prototype.showPicker;HTMLInputElement.prototype.showPicker=function(){if(this.type==='file'){choose(this);return;}return oldPicker.call(this);};}window.__labvoltUpload=function(value){let input=pending||document.querySelector('input[type=file]');if(!input)return;let binary=atob(value.data),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);let transfer=new DataTransfer();transfer.items.add(new File([bytes],value.name,{type:value.mime}));input.files=transfer.files;input.dispatchEvent(new Event('change',{bubbles:true}));input.style.outline='';pending=null;};})();"""

func _assistant_ask() -> void:
 _assistant_request_page(assistant_input.text.strip_edges(),PackedByteArray())

func _assistant_request_page(question: String,wav: PackedByteArray) -> void:
 if not assistant_pending.is_empty() or (question.is_empty() and wav.is_empty()):return
 if not renderer_available() or not is_instance_valid(game) or not is_instance_valid(game.browser_assistant):assistant_answer.text="The browser assistant is unavailable on this device.";return
 var browser: Variant=_browser()
 if browser==null or str(browser.get_url())=="about:blank":assistant_answer.text="Open a page before asking the assistant.";return
 var chosen: Dictionary=selected_attachment.duplicate(true)
 var photo:=PackedByteArray()
 if not chosen.is_empty() and device_kind=="phone":
  var raw: PackedByteArray=attachment_bytes()
  var image:=Image.new()
  if raw.is_empty() or image.load_jpg_from_buffer(raw)!=OK:assistant_answer.text="The selected phone photo is unavailable.";return
  if image.get_width()>768 or image.get_height()>768:
   var scale:=768.0/float(maxi(image.get_width(),image.get_height()))
   image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
  photo=image.save_jpg_to_buffer(.72)
  if photo.size()>game.browser_assistant.MAX_PHOTO_BYTES:assistant_answer.text="Choose a smaller phone photo.";return
 assistant_serial+=1
 var token:=str(Time.get_ticks_usec())+":"+str(assistant_serial)
 assistant_pending={"request_id":assistant_serial,"token":token,"browser":browser,"question":question,"wav":wav,"attachment":chosen,"photo":photo,"session":session_key,"phase":"page"}
 assistant_input.clear();assistant_answer.text="Reading this page…";assistant_action_button.hide();assistant_download_button.hide()
 if is_instance_valid(assistant_virtual_button):assistant_virtual_button.hide()
 browser.execute_javascript(_assistant_context_script(token))
 _assistant_page_timeout(token)

func _assistant_page_timeout(token: String) -> void:
 await get_tree().create_timer(5.0).timeout
 if assistant_pending.get("phase","")=="page" and assistant_pending.get("token","")==token:
  assistant_pending.clear();assistant_answer.text="Could not read this page. Try again after it finishes loading."

func _assistant_context_script(token: String) -> String:
 return """(function(){const token=TOKEN;const url=location.href;const nodes=[];const items=[];for(const el of document.querySelectorAll('a[href],input,textarea')){if(items.length>=12)break;const rect=el.getBoundingClientRect();const style=getComputedStyle(el);if(rect.width<2||rect.height<2||style.display==='none'||style.visibility==='hidden')continue;let kind='';if(el.tagName==='A'){try{const link=new URL(el.href,url);if(link.origin!==location.origin||!['http:','https:'].includes(link.protocol))continue;kind='click';}catch(_){continue;}}else if(el.tagName==='TEXTAREA'||(el.tagName==='INPUT'&&['text','search','email','url'].includes(el.type)))kind='fill';else continue;const label=(el.innerText||el.getAttribute('aria-label')||el.placeholder||el.name||el.href||'').trim().slice(0,48);items.push({kind:kind,label:label,index:items.length});nodes.push(el);}window.__labvoltAssistantTargets={url:url,nodes:nodes,items:items};window.__labvoltAssistantAct=function(action){const state=window.__labvoltAssistantTargets;if(!state||state.url!==location.href||!action||!Number.isInteger(action.index))return false;const el=state.nodes[action.index],info=state.items[action.index];if(!el||!el.isConnected||!info||info.kind!==action.kind)return false;if(info.kind==='click'){try{const link=new URL(el.href,location.href);if(link.origin!==location.origin||!['http:','https:'].includes(link.protocol))return false;el.click();return true;}catch(_){return false;}}if(info.kind==='fill'&&typeof action.value==='string'&&action.value.length<=300){el.value=action.value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return true;}return false;};const text=(document.body?document.body.innerText:'').slice(0,1800);const report={token:token,url:url,title:document.title,text:text,targets:items};window.__labvoltAssistantOriginalTitle=document.title;document.title='__LVAI__'+token+'|'+btoa(unescape(encodeURIComponent(JSON.stringify(report))));})();""".replace("TOKEN",JSON.stringify(token))

func _assistant_check_title() -> void:
 if assistant_pending.get("phase","")!="page":return
 var browser: Variant=assistant_pending.get("browser")
 if browser!=_browser():return
 var title:=str(browser.get_title())
 var prefix:="__LVAI__"+str(assistant_pending.token)+"|"
 if not title.begins_with(prefix):return
 var raw:=Marshalls.base64_to_raw(title.trim_prefix(prefix)).get_string_from_utf8()
 browser.execute_javascript("document.title=window.__labvoltAssistantOriginalTitle||document.title;")
 assistant_page_report(raw)

func assistant_page_report(raw: String) -> void:
 var browser: Variant=assistant_pending.get("browser")
 if assistant_pending.get("phase","")!="page" or browser!=_browser() or raw.length()>12000:return
 var report: Variant=JSON.parse_string(raw)
 if not report is Dictionary or str(report.get("token",""))!=str(assistant_pending.token) or str(report.get("url",""))!=str(browser.get_url()):return
 var view: Dictionary=Policy.page(report)
 if view.is_empty():assistant_pending.clear();assistant_answer.text="This page cannot be shared with the assistant.";return
 assistant_pending.phase="answer"
 assistant_pending.page=view
 var payload:={"request_id":int(assistant_pending.request_id),"kind":device_kind,"device_id":device_id,"lease":lease,"question":str(assistant_pending.question),"wav":assistant_pending.wav,"page":view,"attachment":assistant_pending.attachment,"photo":assistant_pending.photo}
 assistant_answer.text="Waiting for the host assistant…"
 game.browser_assistant.ask(payload)
 _assistant_answer_timeout(int(assistant_pending.request_id),session_key)

func _assistant_answer_timeout(request_id: int,expected_session: String) -> void:
 await get_tree().create_timer(55.0).timeout
 if int(assistant_pending.get("request_id",0))==request_id and assistant_pending.get("phase","")=="answer" and session_key==expected_session:
  assistant_pending.clear();assistant_answer.text="The host assistant did not respond. Please try again."

func _assistant_reply(request_id: int,result: Dictionary) -> void:
 if assistant_pending.is_empty() or int(assistant_pending.get("request_id",0))!=request_id or str(assistant_pending.get("session",""))!=session_key:return
 var browser: Variant=assistant_pending.browser
 var page: Dictionary=assistant_pending.get("page",{})
 assistant_pending.clear()
 if result.has("error"):assistant_answer.text=str(result.error);return
 assistant_response=str(result.get("answer","")).left(1600)
 assistant_answer.text=assistant_response
 assistant_download_button.visible=not assistant_response.is_empty()
 if is_instance_valid(assistant_virtual_button):assistant_virtual_button.visible=not assistant_response.is_empty()
 assistant_action.clear();assistant_action_button.hide()
 var action: Variant=result.get("action",{})
 if action is Dictionary and not action.is_empty() and browser==_browser() and str(browser.get_url())==str(page.get("url","")) and int(action.get("index",-1))>=0 and int(action.get("index",-1))<page.get("targets",[]).size() and str(action.get("kind",""))==str(page.targets[int(action.index)].kind):
  assistant_action={"browser":browser,"url":str(page.url),"action":action}
  assistant_action_button.text="Apply: "+str(action.kind).capitalize()+" "+str(page.targets[int(action.index)].label).left(38)
  assistant_action_button.show()

func _assistant_apply_action() -> void:
 if assistant_action.is_empty():return
 var browser: Variant=assistant_action.browser
 if browser!=_browser() or str(browser.get_url())!=str(assistant_action.url):assistant_action.clear();assistant_action_button.hide();assistant_answer.text="Page changed. Ask again before applying an action.";return
 browser.execute_javascript("window.__labvoltAssistantAct("+JSON.stringify(assistant_action.action)+");")
 assistant_action.clear();assistant_action_button.hide()

func _assistant_download() -> void:
 if assistant_response.is_empty():return
 var folder:=ProjectSettings.globalize_path("user://browser_assistant_downloads")
 if DirAccess.make_dir_recursive_absolute(folder)!=OK:assistant_answer.text="Could not create the game downloads folder.";return
 var filename:="answer_"+Time.get_datetime_string_from_system().replace(":","").replace("-","").replace("T","_")+".txt"
 var path:=folder.path_join(filename)
 var file:=FileAccess.open(path,FileAccess.WRITE)
 if file==null:assistant_answer.text="Could not save the answer.";return
 file.store_string(assistant_response);file.close()
 status.text="Answer saved to "+path

func _assistant_save_virtual() -> void:
 if not assistant_response.is_empty() and assistant_virtual_save.is_valid():assistant_virtual_save.call(assistant_response)

func _toggle_recording() -> void:
 if recording:_finish_recording();return
 if not assistant_pending.is_empty() or not is_instance_valid(game) or not is_instance_valid(game.voice_chat) or not is_instance_valid(game.voice_chat.capture):return
 game.voice_chat.capture.clear_buffer();record_samples.clear();record_phase=0.0;record_started=Time.get_ticks_msec();recording=true
 record_player=AudioStreamPlayer.new();record_player.bus="VoiceCapture";record_player.stream=AudioStreamMicrophone.new();add_child(record_player);record_player.play()
 assistant_record_button.text="Stop and ask";assistant_answer.text="Recording up to six seconds. Audio is sent to the host and OpenAI only when you stop."

func _record_step() -> void:
 if not recording:return
 var capture: AudioEffectCapture=game.voice_chat.capture
 if not is_instance_valid(capture):_cancel_recording();return
 var count:=mini(capture.get_frames_available(),AudioServer.get_mix_rate()/10)
 if count>0:
  var frames:=capture.get_buffer(count)
  var stride:=float(AudioServer.get_mix_rate())/16000.0
  while record_phase<float(frames.size()):
   if record_samples.size()>=192000:break
   var i:=mini(frames.size()-1,int(record_phase))
   var sample:=roundi(clampf((frames[i].x+frames[i].y)*.5,-1.0,1.0)*32767.0)
   record_samples.append(sample&255);record_samples.append((sample>>8)&255)
   record_phase+=stride
  record_phase-=float(frames.size())
 if Time.get_ticks_msec()-record_started>=6000:_finish_recording()

func _cancel_recording() -> void:
 recording=false;record_samples.clear()
 if is_instance_valid(record_player):record_player.stop();record_player.queue_free()
 record_player=null
 if is_instance_valid(assistant_record_button):assistant_record_button.text="Record question"

func _finish_recording() -> void:
 if not recording:return
 var samples:=record_samples.duplicate()
 _cancel_recording()
 if samples.size()<32000:assistant_answer.text="Record at least one second of speech.";return
 _assistant_request_page("",WAV.wav_16k(samples))
