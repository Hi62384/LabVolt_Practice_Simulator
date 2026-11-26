extends VBoxContainer
## Windows gdCEF browser. The process runtime is retained; each device session
## closes its own tabs, renderer surfaces and attachment capability.
const MAX_ATTACHMENT_BYTES:=8*1024*1024
const MAX_TABS:=8
const WHEEL_STEP:=12
const HOME_URL:="https://www.google.com/"
const Policy=preload("res://scripts/campus/ai/browser_assistant_policy.gd")
const Downloads=preload("res://scripts/campus/computers/browser_download.gd")
const WAV=preload("res://scripts/campus/academics/teacher_ai.gd")
const Tokens=preload("res://scripts/ui/design_system/tokens.gd")
const Widgets=preload("res://scripts/ui/design_system/widgets.gd")
static var runtime: Node
static var next_session_serial:=0
var attachment_loader: Callable
var assistant_virtual_save: Callable
var virtual_download_save: Callable
var download_request: HTTPRequest
var download_dialog: ConfirmationDialog
var game: Node
var speaker_world: Node3D
var speaker_position := Vector3.ZERO
var download_destination: Callable
var speaker_clock := 0.0
var speaker_bus := ""
var speaker_volume := 35
var phone_suspended := false
var phone_display_scale := 1.0
var device_kind:=""
var device_id:=""
var lease:=""
var session_key:=""
var candidates: Array=[]
var selected_attachment: Dictionary={}
var tabs: Array=[]
var active:=0
var address: LineEdit
var tab_row: Container
var phone_new_tab: Button
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

var browser_poll := 0.0
var inspect_pending := {}
var context_pending := {}
var inspector: VBoxContainer
var element_tree: Tree
var element_details: TextEdit
var element_styles: TextEdit
var inline_style: LineEdit
var inspected_path: Array
var inspected_browser: WeakRef
var pdf_exports := {}
var pending_pointer := Vector2i(-1,-1)
var pointer_browser: WeakRef

func _ready() -> void:
 get_viewport().size_changed.connect(_resize_tabs)

func _process(delta: float) -> void:
 if phone_suspended:return
 _update_speakers(delta)
 if not is_visible_in_tree():return
 if pointer_browser!=null:
  var browser: Variant=pointer_browser.get_ref()
  if browser==_browser() and is_instance_valid(browser):
   browser.set_mouse_moved(pending_pointer.x,pending_pointer.y)
  pointer_browser=null
 _record_step()
 browser_poll+=delta
 if browser_poll<.05:return
 browser_poll=0.0
 if not inspect_pending.is_empty() and Time.get_ticks_msec()>int(inspect_pending.until):
  inspect_pending.clear()
  status.text="No element inspection report was returned."
 if not context_pending.is_empty() and Time.get_ticks_msec()>int(context_pending.until):
  _finish_context_menu({})
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
 context_pending.clear()
 inspect_pending.clear()
 inspected_browser=null
 assistant_pending.clear();assistant_action.clear();assistant_response=""
 if is_instance_valid(game) and is_instance_valid(game.browser_assistant) and game.browser_assistant.reply_received.is_connected(_assistant_reply):game.browser_assistant.reply_received.disconnect(_assistant_reply)
 for tab in tabs:
  if is_instance_valid(tab.browser):tab.browser.close()
  if is_instance_valid(tab.get("speaker")):
   tab.speaker.stop()
   tab.speaker.queue_free()
 _release_speaker_bus()
 if not session_key.is_empty() and is_instance_valid(runtime) and runtime.has_method("release_context"):runtime.release_context(session_key)
 tabs.clear();active=0;device_kind="";device_id="";lease="";session_key="";candidates.clear();selected_attachment.clear();attachment_loader=Callable();assistant_virtual_save=Callable()
 for child in get_children():remove_child(child);child.queue_free()

func _exit_tree() -> void:
 for tab in tabs:
  if is_instance_valid(tab.get("speaker")):
   tab.speaker.stop()
   tab.speaker.queue_free()
 _release_speaker_bus()
 tabs.clear()

func attachment_bytes() -> PackedByteArray:
 if selected_attachment.is_empty() or not attachment_loader.is_valid():return PackedByteArray()
 var data: Variant=attachment_loader.call(device_kind,device_id,lease,selected_attachment.duplicate(true))
 return data if data is PackedByteArray and data.size()<=MAX_ATTACHMENT_BYTES else PackedByteArray()

func renderer_available() -> bool:
 return is_instance_valid(runtime) and runtime.is_alive() and not tabs.is_empty()

func _build() -> void:
 var chrome:=VBoxContainer.new();chrome.add_theme_constant_override("separation",4);add_child(chrome)
 if device_kind=="phone":
  var strip:=HBoxContainer.new();chrome.add_child(strip)
  var scroll:=ScrollContainer.new()
  scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER
  scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
  scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  strip.add_child(scroll)
  tab_row=HBoxContainer.new();tab_row.add_theme_constant_override("separation",4);scroll.add_child(tab_row)
  phone_new_tab=Button.new();phone_new_tab.text="+";phone_new_tab.accessibility_name="New tab";phone_new_tab.pressed.connect(_add_tab);strip.add_child(phone_new_tab)
 else:
  phone_new_tab=null
  tab_row=HFlowContainer.new();tab_row.add_theme_constant_override("h_separation",3);chrome.add_child(tab_row)
 var nav:=HBoxContainer.new();nav.add_theme_constant_override("separation",4);chrome.add_child(nav)
 back=Button.new();back.text="‹";back.tooltip_text="Back";back.accessibility_name="Back";back.pressed.connect(func():_history(-1));nav.add_child(back)
 forward=Button.new();forward.text="›";forward.tooltip_text="Forward";forward.accessibility_name="Forward";forward.pressed.connect(func():_history(1));nav.add_child(forward)
 var reload:=Button.new();reload.text="↻";reload.tooltip_text="Reload";reload.accessibility_name="Reload";reload.pressed.connect(func():if _browser()!=null:_browser().reload());nav.add_child(reload)
 var home:=Button.new();home.text="⌂";home.tooltip_text="Home";home.accessibility_name="Home";home.pressed.connect(_home);nav.add_child(home)
 address=LineEdit.new();address.right_icon=preload("res://scripts/ui/design_system/widgets.gd").icon("search");address.placeholder_text="Search or enter address";address.max_length=2048;address.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 nav.add_child(address)
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
 var page_frame:=PanelContainer.new()
 page_frame.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("062434"),Color("326979"),2 if device_kind=="phone" else 9))
 var split:=HSplitContainer.new()
 split.size_flags_vertical=Control.SIZE_EXPAND_FILL
 add_child(split)
 page_frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 split.add_child(page_frame)
 inspector=VBoxContainer.new()
 inspector.custom_minimum_size.x=235
 inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 inspector.size_flags_stretch_ratio=.58
 split.add_child(inspector)
 _build_inspector()
 inspector.hide()
 holder=Control.new();holder.clip_contents=true;holder.custom_minimum_size.y=144 if device_kind=="phone" else 180;holder.size_flags_horizontal=Control.SIZE_EXPAND_FILL;holder.size_flags_vertical=Control.SIZE_EXPAND_FILL;page_frame.add_child(holder)
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
 return ensure_runtime(get_tree())

static func ensure_runtime(tree: SceneTree) -> bool:
 if is_instance_valid(runtime):return runtime.is_alive()
 if OS.get_name()!="Windows":return false
 var cef_class:="GdCEF"
 if not ClassDB.class_exists(cef_class):return false
 runtime=ClassDB.instantiate(cef_class) as Node
 if not is_instance_valid(runtime):return false
 runtime.name="LabVoltCEF";tree.root.add_child(runtime)
 if not runtime.initialize({"incognito":true,"root_cache_path":ProjectSettings.globalize_path("user://cef_cache_root"),"remote_debugging_port":0,"enable_media_stream":false,"use_gpu":false,"command_line_switches":{"force-dark-mode":true},"log_file":ProjectSettings.globalize_path("user://cef.log"),"log_severity":"warning"}):
  runtime.queue_free();runtime=null;return false
 return true

func _add_tab() -> void:
 if not is_instance_valid(runtime) or tabs.size()>=MAX_TABS:return
 var surface:=TextureRect.new();surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);surface.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;surface.stretch_mode=TextureRect.STRETCH_SCALE;surface.focus_mode=Control.FOCUS_ALL;holder.add_child(surface)
 var browser: Variant=runtime.create_browser(HOME_URL,surface,{"allow_downloads":false,"javascript":true,"javascript_access_clipboard":false,"session_key":session_key,"frame_rate":45})
 if not is_instance_valid(browser):surface.queue_free();status.text="Browser tab failed: "+str(runtime.get_error());return
 browser.register_method(self,"_labvolt_element_report")
 browser.register_method(self,"_labvolt_context_report")
 var native_download:=false
 if device_kind=="computer" and browser.has_method("enable_virtual_downloads"):
  var scratch:=ProjectSettings.globalize_path("user://cef_virtual_downloads")
  if DirAccess.make_dir_recursive_absolute(scratch)==OK:
   var folder:=scratch.path_join(Crypto.new().generate_random_bytes(16).hex_encode())
   native_download=bool(browser.enable_virtual_downloads(folder))
   if native_download:
    browser.connect("virtual_download_progress",_native_download_progress.bind(session_key))
    browser.connect("virtual_download_finished",_native_download_finished.bind(session_key))
 tabs.append({"browser":browser,"surface":surface,"title":"Google","native_download":native_download,"speaker":_route_tab_audio(browser)});active=tabs.size()-1
 var browser_ref: WeakRef=weakref(browser)
 browser.connect("on_page_loaded",func(_view,_http_code):if browser_ref.get_ref()!=null:_loaded(browser_ref.get_ref()))
 browser.connect("on_page_failed_loading",func(_code,message,_view):if browser_ref.get_ref()==_browser():
  status.text="Connection failed · "+str(message).left(120)
  if device_kind=="computer":home_screen.hide())
 surface.gui_input.connect(func(event):if browser_ref.get_ref()!=null:_forward(browser_ref.get_ref(),surface,event))
 surface.resized.connect(func():if browser_ref.get_ref()!=null:_resize_browser(browser_ref.get_ref(),surface))
 _resize_browser(browser,surface);_refresh()
 if device_kind=="phone":
  address.text=HOME_URL
  status.text="Loading Google…"

func _route_tab_audio(browser: Node) -> AudioStreamPlayer3D:
 if not is_instance_valid(speaker_world) or not browser.has_method("set_audio_stream"):return null
 if speaker_bus.is_empty():
  speaker_bus="Campus workstation %d"%get_instance_id()
  var index:=AudioServer.bus_count
  AudioServer.add_bus()
  AudioServer.set_bus_name(index,speaker_bus)
 var generator:=AudioStreamGenerator.new()
 generator.mix_rate=48000.0 # Matches gdCEF's capture rate, independent of the output device.
 generator.buffer_length=.25
 var speaker:=AudioStreamPlayer3D.new()
 speaker.name="CampusComputerSpeaker"
 speaker.stream=generator
 speaker.bus=speaker_bus
 speaker.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
 speaker_world.add_child(speaker)
 speaker.global_position=speaker_position
 speaker.play()
 var playback:=speaker.get_stream_playback() as AudioStreamGeneratorPlayback
 if playback!=null:browser.set_audio_stream(playback)
 if browser.has_method("set_audio_drive"):browser.set_audio_drive(_speaker_drive())
 return speaker

func _speaker_drive() -> float:
 return lerpf(1.0,24.0,pow(clampf((speaker_volume-65.0)/35.0,0.0,1.0),2.0))

func set_speaker_volume(value: int) -> void:
 var volume:=clampi(value,0,100)
 if speaker_volume==volume:return
 speaker_volume=volume
 for tab in tabs:
  if is_instance_valid(tab.browser) and tab.browser.has_method("set_audio_drive"):
   tab.browser.set_audio_drive(_speaker_drive())
 _update_speakers(.08)

func set_phone_suspended(suspended: bool) -> void:
 if device_kind!="phone" or phone_suspended==suspended:return
 phone_suspended=suspended
 for tab in tabs:
  if is_instance_valid(tab.browser) and tab.browser.has_method("set_page_suspended"):
   tab.browser.set_page_suspended(suspended)
  if is_instance_valid(tab.speaker):
   if suspended:
    if is_instance_valid(tab.browser):tab.browser.set_audio_stream(null)
    tab.speaker.stop()
   else:
    tab.speaker.play()
    var playback:=tab.speaker.get_stream_playback() as AudioStreamGeneratorPlayback
    if playback!=null and is_instance_valid(tab.browser):tab.browser.set_audio_stream(playback)
 if not suspended:_update_speakers(.08)

func _update_speakers(delta: float) -> void:
 if phone_suspended:return
 if not is_instance_valid(speaker_world) or tabs.is_empty():return
 speaker_clock+=delta
 if speaker_clock<.08:return
 speaker_clock=0.0
 var listener:=speaker_world.get_viewport().get_camera_3d()
 if listener==null:return
 var distance:=listener.global_position.distance_to(speaker_position)
 var reach:=lerpf(4.0,32.0,pow(speaker_volume/100.0,.9))
 var falloff:=1.0-smoothstep(2.4,reach,distance)
 var gain:=pow(minf(speaker_volume/65.0,1.0),1.5)*falloff
 var bus_index:=AudioServer.get_bus_index(speaker_bus)
 if bus_index>0:
  AudioServer.set_bus_volume_db(bus_index,linear_to_db(maxf(gain,.0001)))
  AudioServer.set_bus_mute(bus_index,speaker_volume==0 or distance>=reach)

func _release_speaker_bus() -> void:
 if speaker_bus.is_empty():return
 var index:=AudioServer.get_bus_index(speaker_bus)
 if index>0:AudioServer.remove_bus(index)
 speaker_bus=""

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
 if get_viewport().get_meta("parked_preview",false):return
 if surface.size.x<2 or surface.size.y<2:return
 var desired:=surface.size*_desktop_pixel_scale()*phone_display_scale
 var factor:=minf(1.0,minf(1440.0/desired.x,900.0/desired.y))
 var pixels:=(desired*factor).round()
 if pixels==surface.get_meta("cef_pixels",Vector2.ZERO):return
 surface.set_meta("cef_pixels",pixels)
 browser.resize(pixels)
 browser.set_zoom_level(log(pixels.x/surface.size.x)/log(1.2))

func move_speaker(point: Vector3) -> void:
 if speaker_position.is_equal_approx(point):return
 speaker_position=point
 for tab in tabs:
  if is_instance_valid(tab.get("speaker")):tab.speaker.global_position=point

func preview_texture() -> Texture2D:
 if active not in range(tabs.size()) or not is_instance_valid(tabs[active].surface):return null
 return tabs[active].surface.texture

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
 if inspected_browser!=null and inspected_browser.get_ref()!=_browser():inspector.hide()
 for child in tab_row.get_children():tab_row.remove_child(child);child.queue_free()
 for i in tabs.size():
  var index:=i
  var shell:=PanelContainer.new()
  var skin:=StyleBoxFlat.new()
  skin.bg_color=Color("17566e") if i==active else Color("0a3042")
  skin.border_color=Color("3b91a5") if i==active else Color("245264")
  skin.set_border_width_all(1)
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
 var plus:=phone_new_tab
 if not is_instance_valid(plus):
  plus=Button.new();plus.text="+";plus.pressed.connect(_add_tab);tab_row.add_child(plus)
 plus.disabled=tabs.size()>=MAX_TABS or not is_instance_valid(runtime)
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
 if is_instance_valid(tab.get("speaker")):tab.speaker.queue_free()
 if is_instance_valid(tab.surface):tab.surface.queue_free()
 tabs.remove_at(index)
 if index<active:active-=1
 active=mini(active,tabs.size()-1)
 _refresh()

func _home() -> void:
 var browser: Variant=_browser()
 if browser==null:return
 browser.load_url(HOME_URL)
 if is_instance_valid(home_screen):home_screen.hide()
 address.clear()
 status.text=""

func _input(event: InputEvent) -> void:
 if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
 if not is_instance_valid(address):return
 var focused:=get_viewport().gui_get_focus_owner()
 var hovered:=get_viewport().gui_get_hovered_control()
 if focused!=address and (focused==null or not is_ancestor_of(focused)) and (hovered==null or not is_ancestor_of(hovered)):return
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
 if inspected_browser!=null and inspected_browser.get_ref()==browser:
  inspected_browser=null
  inspector.hide()
 for i in tabs.size():
  if tabs[i].browser!=browser:continue
  tabs[i].title=str(browser.get_title()) if not str(browser.get_title()).is_empty() else str(browser.get_url()).left(24)
  browser.execute_javascript(_upload_script())
  if device_kind=="computer" and not tabs[i].native_download:
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
 var max_wire:=Downloads.LEGACY_PAGE_BYTES*2
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
 var extension:=Downloads.extension_for(str(payload.get("name","")),str(payload.get("mime","")))
 var body:=Marshalls.base64_to_raw(str(payload.get("data","")))
 var origin:=str(tab.browser.get_url()).get_slice("://",0)+"://"+str(tab.browser.get_url()).get_slice("://",1).get_slice("/",0)
 _offer_download(str(payload.get("name","")),extension,body,origin.left(85))

func _native_download_progress(received: int,total: int,expected_session: String) -> void:
 if expected_session!=session_key:return
 status.text="Downloading… %d / %d KB"%[ceili(received/1024.0),ceili(total/1024.0)] if total>0 else "Downloading… %d KB"%ceili(received/1024.0)

func _native_download_finished(name: String,mime: String,body: PackedByteArray,error: String,expected_session: String) -> void:
 if expected_session!=session_key or not virtual_download_save.is_valid():return
 if not error.is_empty():
  status.text=error
  return
 var extension:=Downloads.extension_for(name,mime)
 _offer_download(name,extension,body,"Chromium")

func _offer_download(name: String,extension: String,body: PackedByteArray,_source: String) -> void:
 if not Downloads.valid(body,extension):
  status.text="The website offered an unsupported or invalid file."
  return
 if is_instance_valid(download_dialog):
  status.text="Confirm or dismiss the previous download first."
  return
 var filename:=Downloads.filename(name.left(128),extension)
 var expected_session:=session_key
 var destination_name: String=download_destination.call() if download_destination.is_valid() else "Downloads"
 download_dialog=ConfirmationDialog.new()
 download_dialog.title="Save to "+destination_name
 download_dialog.theme=_download_theme()
 download_dialog.ok_button_text="Save"
 var fields:=VBoxContainer.new()
 fields.custom_minimum_size.x=330
 fields.add_theme_constant_override("separation",9)
 var destination:=PanelContainer.new()
 destination.add_theme_stylebox_override("panel",Tokens.surface(Color("ecf5f7"),Color("cbdee3"),10))
 fields.add_child(destination)
 var summary:=HBoxContainer.new()
 summary.add_theme_constant_override("separation",10)
 destination.add_child(summary)
 var icon:=TextureRect.new()
 icon.texture=Widgets.icon("folder")
 icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 icon.custom_minimum_size=Vector2(26,26)
 icon.modulate=Color("196879")
 summary.add_child(icon)
 var details:=VBoxContainer.new()
 details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 summary.add_child(details)
 var folder_label:=Label.new()
 folder_label.text=destination_name
 details.add_child(folder_label)
 var metadata:=Label.new()
 metadata.text="%s file · %s"%[extension.to_upper(),String.humanize_size(body.size())]
 metadata.add_theme_color_override("font_color",Color("496574"))
 metadata.add_theme_font_size_override("font_size",13)
 details.add_child(metadata)
 var name_label:=Label.new()
 name_label.text="File name"
 fields.add_child(name_label)
 var name_field:=LineEdit.new()
 name_field.text=filename
 name_field.max_length=25
 name_field.accessibility_name="File name"
 name_field.custom_minimum_size.y=38
 fields.add_child(name_field)
 add_child(download_dialog)
 download_dialog.add_child(fields)
 download_dialog.register_text_enter(name_field)
 download_dialog.get_ok_button().theme_type_variation="DownloadSaveButton"
 download_dialog.confirmed.connect(func():
  if session_key==expected_session and virtual_download_save.is_valid():
   status.text="Saving to "+destination_name+"…"
   var requested:=name_field.text.strip_edges()
   if not requested.to_lower().ends_with("."+extension):requested+="."+extension
   virtual_download_save.call(Downloads.filename(requested,extension),body)
 )
 download_dialog.confirmed.connect(download_dialog.queue_free)
 download_dialog.canceled.connect(func():if session_key==expected_session:status.text="")
 download_dialog.canceled.connect(download_dialog.queue_free)
 status.text=""
 download_dialog.popup_centered()
 name_field.grab_focus()
 name_field.select(0,filename.get_basename().length())

func _download_theme() -> Theme:
 var skin:=Theme.new()
 var frame:=Tokens.surface(Color("123e50"),Color("377483"),1)
 frame.expand_margin_top=36
 skin.set_stylebox("embedded_border","Window",frame)
 skin.set_stylebox("embedded_unfocused_border","Window",frame)
 skin.set_color("title_color","Window",Color("edf6fa"))
 skin.set_stylebox("panel","AcceptDialog",Tokens.surface(Color("f9fcfd"),Color("cbdee3"),16))
 skin.set_color("font_color","Label",Color("183b4c"))
 skin.set_color("font_color","LineEdit",Color("183b4c"))
 skin.set_color("caret_color","LineEdit",Color("183b4c"))
 skin.set_color("selection_color","LineEdit",Color("1a6e80"))
 skin.set_stylebox("normal","LineEdit",Tokens.surface(Color.WHITE,Color("aac4cc"),8))
 var focus:=StyleBoxFlat.new()
 focus.draw_center=false
 focus.border_color=Color("3e8898")
 focus.set_border_width_all(2)
 focus.set_corner_radius_all(Tokens.RADIUS)
 skin.set_stylebox("focus","LineEdit",focus)
 skin.set_stylebox("focus","Button",focus)
 skin.set_type_variation("DownloadSaveButton","Button")
 for state in ["normal","hover","pressed"]:
  var shade:=Color("edf4f6") if state=="normal" else Color("dcebef")
  skin.set_stylebox(state,"Button",Tokens.surface(shade,Color("b9cdd3"),8))
  skin.set_stylebox(state,"DownloadSaveButton",Tokens.surface(Color("176778") if state=="normal" else Color("0b5060"),Color("176778"),8))
 for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
  skin.set_color(state,"Button",Color("183b4c"))
  skin.set_color(state,"DownloadSaveButton",Color.WHITE)
 return skin

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
 _download_url(address.text.strip_edges())

func _download_url(url: String) -> void:
 if not virtual_download_save.is_valid():status.text="This computer has no Downloads folder.";return
 if is_instance_valid(download_request):status.text="A download is already in progress.";return
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
  status.text="The file exceeds this computer's %s download limit."%String.humanize_size(Downloads.MAX_BYTES)
  return
 if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
  status.text="Could not download this address. Use a direct file link."
  return
 var mime:=""
 for header in headers:
  if header.get_slice(":",0).strip_edges().to_lower()=="content-type":
   mime=header.substr(header.find(":")+1).get_slice(";",0).strip_edges().to_lower()
 var name:=url.get_slice("?",0).get_slice("#",0).get_file().uri_decode()
 var extension:=Downloads.extension_for(name,mime)
 if not Downloads.valid(body,extension):
  status.text="Unsupported or invalid file."
  return
 _offer_download(name,extension,body,"Website")

func _forward(browser: Variant,surface: TextureRect,event: InputEvent) -> void:
 if browser!=_browser() or not is_instance_valid(browser):return
 if event is InputEventMouseMotion:
  pending_pointer=_browser_point(surface,event.position)
  pointer_browser=weakref(browser)
 elif event is InputEventMouseButton:
  var point:=_browser_point(surface,event.position)
  pointer_browser=null
  surface.grab_focus();browser.set_mouse_moved(point.x,point.y)
  if event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed:browser.set_mouse_left_down()
   else:browser.set_mouse_left_up()
  elif event.button_index==MOUSE_BUTTON_MIDDLE:
   if event.pressed:browser.set_mouse_middle_down()
   else:browser.set_mouse_middle_up()
  elif event.button_index==MOUSE_BUTTON_RIGHT:
   if not event.pressed:_page_context_menu(browser,point,surface.get_global_mouse_position())
   surface.accept_event()
  elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
   if event.pressed:
    var amount:=maxi(1,roundi(WHEEL_STEP*event.factor))
    if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
     var direction:=1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1
     browser.set_mouse_wheel_vertical(direction*amount,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
    else:
     var direction:=1 if event.button_index==MOUSE_BUTTON_WHEEL_LEFT else -1
     browser.set_mouse_wheel_horizontal(direction*amount,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
   surface.accept_event()
 elif event is InputEventKey:
  if event.keycode in [KEY_SHIFT,KEY_ALT,KEY_CTRL,KEY_META,KEY_CAPSLOCK,KEY_NUMLOCK,KEY_SCROLLLOCK]:return
  # Godot's keycode names letters in uppercase. Unicode is the character
  # already resolved by the OS keyboard layout, Shift and Caps Lock.
  var key: int=event.keycode if event.keycode!=KEY_NONE else event.physical_keycode
  if event.unicode>=32 and event.unicode!=127 and not event.meta_pressed and not (event.ctrl_pressed and not event.alt_pressed):
   key=event.unicode
  if key!=KEY_NONE:browser.set_key_pressed(key,event.pressed,event.shift_pressed,event.alt_pressed,event.ctrl_pressed)

func _browser_point(surface: TextureRect,position: Vector2) -> Vector2i:
 var pixels: Vector2=surface.get_meta("cef_pixels",surface.size)
 return Vector2i((position*pixels/surface.size.max(Vector2.ONE)).round())

func _page_context_menu(browser: Variant,point: Vector2i,menu_position: Vector2) -> void:
 var token:=Crypto.new().generate_random_bytes(12).hex_encode()
 context_pending={"browser":weakref(browser),"point":point,"position":menu_position,"token":token,"until":Time.get_ticks_msec()+350}
 browser.execute_javascript("""
 (() => {
   const el = document.elementFromPoint(%d / devicePixelRatio, %d / devicePixelRatio);
   const image = el?.closest('img');
   const link = el?.closest('a[href]');
   window.godotMethods?.labvolt_context_report?.(JSON.stringify({
     token:%s, image:(image?.currentSrc || image?.src || '').slice(0, 1048576),
     link:(link?.href || '').slice(0, 2048)
   }));
 })();
 """ % [point.x,point.y,JSON.stringify(token)])

func _labvolt_context_report(raw: Variant) -> void:
 if context_pending.is_empty() or not raw is String or raw.length()>1051000:return
 var data: Variant=JSON.parse_string(raw)
 if data is Dictionary and data.get("token","")==context_pending.token:_finish_context_menu.call_deferred(data)

func _finish_context_menu(data: Dictionary) -> void:
 if context_pending.is_empty() or (not data.is_empty() and data.get("token","")!=context_pending.token):return
 var pending:=context_pending
 context_pending={}
 var browser: Variant=pending.browser.get_ref()
 if not is_visible_in_tree() or not is_instance_valid(browser) or browser!=_browser():return
 var point: Vector2i=pending.point
 var link:=str(data.get("link",""))
 var image:=str(data.get("image",""))
 var has_link:=link.begins_with("https://") or link.begins_with("http://")
 var has_image:=image.begins_with("https://") or image.begins_with("http://") or image.begins_with("data:image/")
 var can_save:=virtual_download_save.is_valid()
 var popup:=PopupMenu.new()
 var panel:=StyleBoxFlat.new()
 panel.bg_color=Color("ffffff")
 panel.border_color=Color("ccd5df")
 panel.set_border_width_all(1)
 panel.set_corner_radius_all(8)
 panel.set_content_margin_all(7)
 panel.shadow_color=Color(0,0,0,.2)
 panel.shadow_size=6
 var hover:=StyleBoxFlat.new()
 hover.bg_color=Color("e5eff7")
 hover.set_corner_radius_all(4)
 var light:=Theme.new()
 light.set_stylebox("panel","PopupMenu",panel)
 light.set_stylebox("hover","PopupMenu",hover)
 light.set_color("font_color","PopupMenu",Color("1d3343"))
 light.set_color("font_hover_color","PopupMenu",Color("102433"))
 light.set_color("font_disabled_color","PopupMenu",Color("768895"))
 popup.theme=light
 popup.hide_on_item_selection=true
 if has_image:
  popup.add_item("Open image in new tab",7)
  popup.add_item("Copy image address",8)
  if can_save:popup.add_item("Save image as…",9)
 if has_link:
  popup.add_item("Open link in new tab",10)
  popup.add_item("Copy link address",11)
  if can_save:popup.add_item("Save link as…",12)
 if has_image or has_link:popup.add_separator()
 popup.add_item("Back",0)
 popup.set_item_disabled(popup.get_item_index(0),not browser.has_previous_page())
 popup.add_item("Forward",1)
 popup.set_item_disabled(popup.get_item_index(1),not browser.has_next_page())
 popup.add_item("Reload",2)
 if can_save and browser.has_method("save_page_as_pdf"):popup.add_item("Save page as PDF…",13)
 popup.add_separator()
 popup.add_item("Copy selection",5)
 popup.add_item("Paste",6)
 popup.add_item("Copy page address",3)
 popup.add_item("Inspect element",4)
 add_child(popup)
 var reference: WeakRef=weakref(browser)
 var choose:=func(id:int):
  var target: Variant=reference.get_ref()
  if not is_instance_valid(target) or target!=_browser():return
  match id:
   0:_history(-1)
   1:_history(1)
   2:target.reload()
   3:DisplayServer.clipboard_set(str(target.get_url()))
   4:_inspect_element(target,point)
   5:target.copy()
   6:target.paste()
   7:_open_context_url(image)
   8:DisplayServer.clipboard_set(image)
   9:_save_context_url(target,image)
   10:_open_context_url(link)
   11:DisplayServer.clipboard_set(link)
   12:_save_context_url(target,link)
   13:_save_page_pdf(target)
 popup.id_pressed.connect(choose)
 popup.popup_hide.connect(popup.queue_free)
 popup.position=Vector2i(pending.position)
 popup.popup()

func _open_context_url(url: String) -> void:
 var previous_count:=tabs.size()
 _add_tab()
 if tabs.size()>previous_count:_browser().load_url(url)

func _save_context_url(browser: Variant,url: String) -> void:
 if url.begins_with("data:image/"):
  var metadata:=url.get_slice(",",0)
  if not metadata.ends_with(";base64") or not url.contains(","):
   status.text="This embedded image format is unsupported."
   return
  var mime:=metadata.trim_prefix("data:").trim_suffix(";base64")
  _offer_download("image",Downloads.EXTENSIONS.get(mime,""),Marshalls.base64_to_raw(url.get_slice(",",1)),"Embedded image")
 elif bool(tabs[active].native_download) and browser.has_method("download_file"):
  browser.download_file(url)
  status.text="Downloading…"
 else:
  _download_url(url)

func _save_page_pdf(browser: Variant) -> void:
 var browser_id: int=browser.get_instance_id()
 if pdf_exports.has(browser_id):return
 var folder:=ProjectSettings.globalize_path("user://cef_virtual_downloads")
 if DirAccess.make_dir_recursive_absolute(folder)!=OK:
  status.text="Could not prepare the PDF."
  return
 var path:=folder.path_join(Crypto.new().generate_random_bytes(12).hex_encode()+".pdf")
 var expected:=session_key
 var title:=str(browser.get_title())
 pdf_exports[browser_id]=path
 browser.connect("on_pdf_saved",func(result: String,success: bool,_view: Variant):
  pdf_exports.erase(browser_id)
  if result!=path:return
  var output:=FileAccess.open(path,FileAccess.READ) if success else null
  var bytes:=output.get_buffer(output.get_length()) if output!=null and output.get_length()<=Downloads.MAX_BYTES else PackedByteArray()
  if output!=null:output.close()
  if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
  if expected!=session_key:return
  if bytes.is_empty():status.text="Could not save this page as a PDF."
  else:_offer_download(title,"pdf",bytes,"PDF")
 ,CONNECT_ONE_SHOT)
 browser.save_page_as_pdf(path)

func _inspect_element(browser: Variant,point: Vector2i,path: Variant=null) -> void:
 var token:=Crypto.new().generate_random_bytes(12).hex_encode()
 inspect_pending={"browser":weakref(browser),"token":token,"until":Time.get_ticks_msec()+3500}
 browser.execute_javascript("""
 (() => {
   const path = %s;
   const el = path ? path.reduce((node, index) => node?.children[index], document.documentElement) :
     document.elementFromPoint(%d / devicePixelRatio, %d / devicePixelRatio);
   if (!el) return;
   const pathTo = node => {
     const path = [];
     while (node?.parentElement) {
       path.unshift(Array.prototype.indexOf.call(node.parentElement.children, node));
       node = node.parentElement;
     }
     return path;
   };
   const summary = node => node && ({
     label: '<' + node.tagName.toLowerCase() + (node.id ? '#' + node.id.slice(0,40) : '') + '>',
     path: pathTo(node)
   });
   const bounds = el.getBoundingClientRect();
   const css = getComputedStyle(el);
   const report = {token:%s, tag:el.tagName.toLowerCase(), html:el.outerHTML.slice(0,2400),
     size:[Math.round(bounds.width),Math.round(bounds.height)],
     parent:summary(el.parentElement), element:summary(el),
     children:Array.from(el.children).slice(0,12).map(summary),
     inlineStyle:(el.getAttribute('style') || '').slice(0,800),
     styles:{display:css.display, position:css.position, color:css.color, background:css.backgroundColor,
       font:css.font, margin:css.margin, padding:css.padding, border:css.border}};
   window.godotMethods?.labvolt_element_report?.(JSON.stringify(report));
 })();
 """ % [JSON.stringify(path),point.x,point.y,JSON.stringify(token)])

func _labvolt_element_report(raw: Variant) -> void:
 if inspect_pending.is_empty() or not raw is String or raw.length()>12000:return
 var browser: Variant=inspect_pending.browser.get_ref()
 if not is_instance_valid(browser) or browser!=_browser() or Time.get_ticks_msec()>int(inspect_pending.until):return
 var data: Variant=JSON.parse_string(raw)
 if not data is Dictionary or data.get("token","")!=inspect_pending.token:return
 if not data.get("html") is String or not data.get("size") is Array or data.size.size()!=2:return
 inspect_pending.clear()
 _show_element_report.call_deferred(browser,data)

func _build_inspector() -> void:
 var toolbar:=HBoxContainer.new()
 inspector.add_child(toolbar)
 var heading:=Label.new()
 heading.text="Page inspector"
 heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 toolbar.add_child(heading)
 var close:=Button.new()
 close.text="×"
 close.accessibility_name="Close page inspector"
 close.pressed.connect(inspector.hide)
 toolbar.add_child(close)
 var panes:=VSplitContainer.new()
 panes.size_flags_vertical=Control.SIZE_EXPAND_FILL
 inspector.add_child(panes)
 element_tree=Tree.new()
 element_tree.hide_root=true
 element_tree.size_flags_vertical=Control.SIZE_EXPAND_FILL
 panes.add_child(element_tree)
 element_tree.item_activated.connect(func():
  var browser: Variant=inspected_browser.get_ref() if inspected_browser!=null else null
  var row:=element_tree.get_selected()
  if is_instance_valid(browser) and browser==_browser() and row!=null:
   _inspect_element(browser,Vector2i.ZERO,row.get_metadata(0)))
 element_tree.tooltip_text="Double-click an element to inspect it"
 var views:=TabContainer.new()
 views.size_flags_vertical=Control.SIZE_EXPAND_FILL
 panes.add_child(views)
 element_details=TextEdit.new()
 element_details.name="Markup"
 element_details.editable=false
 element_details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
 views.add_child(element_details)
 var styles:=VBoxContainer.new()
 styles.name="Styles"
 views.add_child(styles)
 var edit_row:=HBoxContainer.new()
 styles.add_child(edit_row)
 inline_style=LineEdit.new()
 inline_style.placeholder_text="Inline CSS"
 inline_style.accessibility_name="Inline CSS for the selected element"
 inline_style.max_length=800
 inline_style.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 inline_style.text_submitted.connect(func(_value:String):_apply_inline_style())
 edit_row.add_child(inline_style)
 var apply:=Button.new()
 apply.text="Apply"
 apply.pressed.connect(_apply_inline_style)
 edit_row.add_child(apply)
 element_styles=TextEdit.new()
 element_styles.editable=false
 element_styles.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
 element_styles.size_flags_vertical=Control.SIZE_EXPAND_FILL
 styles.add_child(element_styles)

func _apply_inline_style() -> void:
 var browser: Variant=inspected_browser.get_ref() if inspected_browser!=null else null
 if not is_instance_valid(browser) or browser!=_browser():return
 browser.execute_javascript("""
 (() => {
   const el = %s.reduce((node, index) => node?.children[index], document.documentElement);
   if (el) el.setAttribute('style', %s);
 })();
 """ % [JSON.stringify(inspected_path),JSON.stringify(inline_style.text)])
 _inspect_element(browser,Vector2i.ZERO,inspected_path)

func _show_element_report(browser: Variant,data: Dictionary) -> void:
 if not is_visible_in_tree() or not is_instance_valid(browser) or browser!=_browser():return
 inspected_browser=weakref(browser)
 element_tree.clear()
 var root:=element_tree.create_item()
 var parent_row:=_element_row(root,data.get("parent"))
 var selected:=_element_row(parent_row if parent_row!=null else root,data.get("element"))
 if selected!=null:
  selected.select(0)
  inspected_path=selected.get_metadata(0)
  var children: Variant=data.get("children",[])
  if children is Array:
   for child in children.slice(0,12):_element_row(selected,child)
 element_details.text="%s × %s\n\n%s"%[str(data.size[0]).left(12),str(data.size[1]).left(12),str(data.html)]
 inline_style.text=str(data.get("inlineStyle","")).left(800)
 element_styles.text=""
 var styles: Variant=data.get("styles")
 if styles is Dictionary:
  for key in ["display","position","color","background","font","margin","padding","border"]:
   element_styles.text+="%s: %s\n"%[key,str(styles.get(key,"")).left(160)]
 inspector.show()

func _element_row(parent: TreeItem,data: Variant) -> TreeItem:
 if not data is Dictionary or not data.get("path") is Array:return null
 var row:=element_tree.create_item(parent)
 row.set_text(0,str(data.get("label","Element")).left(80))
 row.set_metadata(0,data.path)
 return row

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
