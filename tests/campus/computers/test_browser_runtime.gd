extends SceneTree

var failures: Array[String]=[]
var loaded:=false

func _initialize() -> void:
 call_deferred("_run")

func _run() -> void:
 var surface:=preload("res://scripts/campus/computers/browser_surface.gd").new()
 root.add_child(surface)
 surface.size=Vector2(900,600)
 surface.configure("computer","fixture","lease",[{"kind":"virtual_file","name":"notes.txt","bytes":5}])
 surface.attachment_loader=func(_kind,_id,_lease,_item):return "hello".to_utf8_buffer()
 if not surface.renderer_available():
  var cef_classes: Array=[]
  for name in ClassDB.get_class_list():
   if str(name).to_lower().contains("cef"):cef_classes.append(name)
  print("BROWSER_DIAGNOSTIC classes=",cef_classes," status=",surface.status.text)
  failures.append("gdCEF renderer did not initialize or create a tab")
  _finish(surface)
  return
 var browser: Variant=surface.tabs[0].browser
 browser.connect("on_page_loaded",func(_view,_http_code):loaded=true)
 browser.load_data_uri("<html><head><title>LabVolt Browser Fixture</title></head><body><input id='key-test' autofocus style='position:absolute;left:10px;top:10px;width:300px;height:30px'><h1 style='margin-top:60px'>Browser paint</h1><input type='file'></body></html>","text/html")
 var deadline:=Time.get_ticks_msec()+12000
 while (not loaded or browser.get_title()!="LabVolt Browser Fixture") and Time.get_ticks_msec()<deadline:await process_frame
 if browser.get_title()!="LabVolt Browser Fixture":failures.append("Local HTML title did not load")
 if browser.get_texture()==null:failures.append("Browser texture was not created")
 if loaded:
  await create_timer(.3).timeout
  var click:=InputEventMouseButton.new()
  click.position=Vector2(40,22)
  click.button_index=MOUSE_BUTTON_LEFT
  click.pressed=true
  surface._forward(browser,surface.tabs[0].surface,click)
  click.pressed=false
  surface._forward(browser,surface.tabs[0].surface,click)
  browser.execute_javascript("document.querySelector('#key-test').focus();")
  await create_timer(.2).timeout
  for glyph in "hello world! É":
   var key:=InputEventKey.new()
   key.unicode=glyph.unicode_at(0)
   key.keycode=glyph.to_upper().unicode_at(0)
   key.shift_pressed=glyph in ["!","É"]
   key.pressed=true
   surface._forward(browser,surface.tabs[0].surface,key)
   var release:=key.duplicate() as InputEventKey
   release.pressed=false
   surface._forward(browser,surface.tabs[0].surface,release)
  await create_timer(.3).timeout
  browser.execute_javascript("document.title='typed:'+document.activeElement.id+':'+document.hasFocus()+':'+document.querySelector('#key-test').value;")
  if not await _wait_title(browser,"typed:key-test:true:hello world! É",5000):failures.append("Chromium typed an incorrect case, character or symbol: "+str(browser.get_title()))
 if loaded:
  for i in 10:await process_frame
  surface.selected_attachment=surface.candidates[0].duplicate(true)
  browser.execute_javascript("document.querySelector('input[type=file]').click();")
  for i in 10:await process_frame
  surface._supply_upload(browser)
  for i in 10:await process_frame
  browser.execute_javascript("document.title='upload:'+document.querySelector('input[type=file]').files[0]?.name+':'+document.querySelector('input[type=file]').files[0]?.size;")
  var upload_deadline:=Time.get_ticks_msec()+5000
  while not str(browser.get_title()).begins_with("upload:") and Time.get_ticks_msec()<upload_deadline:await process_frame
  if browser.get_title()!="upload:notes.txt:5":failures.append("Virtual document was not attached to the HTML file input")
 if OS.get_environment("LABVOLT_BROWSER_TEST_HTTPS")=="1":
  browser.load_url("https://example.com/")
  if not await _wait_title(browser,"Example Domain",12000):failures.append("Public HTTPS page did not load")
 var base:=OS.get_environment("LABVOLT_BROWSER_FIXTURE_URL")
 if not base.is_empty():
  var virtual_downloads:={}
  surface.virtual_download_save=func(filename: String,contents: PackedByteArray):virtual_downloads[filename]=contents
  for fixture in ["/notes.txt","/manual.pdf","/invalid.png"]:
   surface.address.text=base+fixture
   surface._download_address()
   var download_deadline:=Time.get_ticks_msec()+5000
   while is_instance_valid(surface.download_request) and Time.get_ticks_msec()<download_deadline:await process_frame
  if virtual_downloads.size()!=2 or virtual_downloads.get("notes.txt",PackedByteArray()).get_string_from_utf8()!="Campus lab notes" or not virtual_downloads.has("manual.pdf"):
   failures.append("Browser did not save validated virtual downloads or reject invalid images")
  surface.address.text=base+"/login"
  surface._navigate()
  if not await _wait_title(browser,"LOGIN",8000):failures.append("HTTP login page did not load")
  else:
   if OS.get_environment("LABVOLT_BROWSER_TEST_HTTPS")=="1":
    if not await _wait_history(browser,-1,3000):failures.append("Back navigation was unavailable")
    else:
     surface._history(-1)
     if not await _wait_title(browser,"Example Domain",8000):failures.append("Back navigation did not restore the HTTPS page")
     if not await _wait_history(browser,1,3000):failures.append("Forward navigation was unavailable")
     surface._history(1)
     if not await _wait_title(browser,"LOGIN",8000):failures.append("Forward navigation did not restore the login page")
   for i in 20:await process_frame
   var down:=InputEventMouseButton.new();down.position=Vector2(50,40);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true
   var up:=InputEventMouseButton.new();up.position=down.position;up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false
   surface._forward(browser,surface.tabs[0].surface,down)
   surface._forward(browser,surface.tabs[0].surface,up)
   if not await _wait_title(browser,"SIGNED_IN",8000):failures.append("Form login and session cookie failed")
   else:
    await create_timer(.2).timeout
    surface._forward(browser,surface.tabs[0].surface,down)
    surface._forward(browser,surface.tabs[0].surface,up)
    var page_deadline:=Time.get_ticks_msec()+10000
    while not is_instance_valid(surface.download_dialog) and Time.get_ticks_msec()<page_deadline:await process_frame
    if not is_instance_valid(surface.download_dialog) or virtual_downloads.has("lecture.pdf"):
     failures.append("Authenticated website download did not request explicit virtual save approval")
    else:
     surface.download_dialog.confirmed.emit()
     if virtual_downloads.get("lecture.pdf",PackedByteArray()).size()!=16509:
      failures.append("Chunked website download failed to preserve the file bytes")
  surface._add_tab()
  var second: Variant=surface._browser()
  second.load_url(base+"/private")
  if not await _wait_title(second,"SIGNED_IN",8000):failures.append("Tabs on one device did not share login")
  surface._close_tab()
 surface.close_session()
 await create_timer(.3).timeout
 surface.configure("phone","phone-fixture","phone-lease",[{"kind":"virtual_file","name":"reject.txt","bytes":3},{"kind":"photo","name":"image.jpg","bytes":3}])
 if surface.candidates.size()!=1 or str(surface.candidates[0].get("kind",""))!="photo":failures.append("Phone chooser accepted a non-photo attachment")
 if not surface.renderer_available():failures.append("Browser did not reopen after closing a device session")
 var photo_browser: Variant=surface._browser()
 photo_browser.load_data_uri("<html><title>PHOTO</title><input type='file' accept='image/*'></html>","text/html")
 if not await _wait_title(photo_browser,"PHOTO",8000):failures.append("Phone browser did not load an upload page")
 else:
  for i in 20:await process_frame
  surface.attachment_loader=func(_kind,_id,_lease,_item):return PackedByteArray([1,2,3])
  surface.selected_attachment=surface.candidates[0].duplicate(true)
  photo_browser.execute_javascript("document.querySelector('input').click();")
  for i in 10:await process_frame
  surface._supply_upload(photo_browser)
  photo_browser.execute_javascript("document.title='photo:'+document.querySelector('input').files[0]?.name+':'+document.querySelector('input').files[0]?.type;")
  if not await _wait_title(photo_browser,"photo:image.jpg:image/jpeg",5000):failures.append("Phone photo was not attached with an image MIME type")
 photo_browser.load_data_uri("<html><title>IFRAME</title><iframe style='position:absolute;left:0;top:0;border:0;width:200px;height:100px' srcdoc=\"<input type='file' style='position:absolute;left:0;top:0;width:180px;height:80px'>\"></iframe></html>","text/html")
 if not await _wait_title(photo_browser,"IFRAME",8000):failures.append("Embedded file-input page did not load")
 else:
  for i in 20:await process_frame
  var blocked_before: int=photo_browser.blocked_file_dialogs()
  var iframe_down:=InputEventMouseButton.new();iframe_down.position=Vector2(50,40);iframe_down.button_index=MOUSE_BUTTON_LEFT;iframe_down.pressed=true
  var iframe_up:=InputEventMouseButton.new();iframe_up.position=iframe_down.position;iframe_up.button_index=MOUSE_BUTTON_LEFT;iframe_up.pressed=false
  surface._forward(photo_browser,surface.tabs[0].surface,iframe_down)
  surface._forward(photo_browser,surface.tabs[0].surface,iframe_up)
  var dialog_deadline:=Time.get_ticks_msec()+3000
  while photo_browser.blocked_file_dialogs()==blocked_before and Time.get_ticks_msec()<dialog_deadline:await process_frame
  if photo_browser.blocked_file_dialogs()==blocked_before:failures.append("An iframe file input did not reach the native host-picker guard")
 if not base.is_empty():
  var phone_browser: Variant=surface._browser()
  phone_browser.load_url(base+"/private")
  if not await _wait_title(phone_browser,"SIGNED_OUT",8000):failures.append("A new device inherited the previous device's login cookie")
 _finish(surface)

func _wait_title(browser: Variant,title: String,timeout_ms: int) -> bool:
 var deadline:=Time.get_ticks_msec()+timeout_ms
 while is_instance_valid(browser) and browser.get_title()!=title and Time.get_ticks_msec()<deadline:await process_frame
 return is_instance_valid(browser) and browser.get_title()==title

func _wait_history(browser: Variant,direction: int,timeout_ms: int) -> bool:
 var deadline:=Time.get_ticks_msec()+timeout_ms
 while is_instance_valid(browser) and not (browser.has_previous_page() if direction<0 else browser.has_next_page()) and Time.get_ticks_msec()<deadline:await process_frame
 return is_instance_valid(browser) and (browser.has_previous_page() if direction<0 else browser.has_next_page())

func _finish(surface: Node) -> void:
 surface.close_session()
 for failure in failures:push_error(failure)
 print("BROWSER_RUNTIME ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
 quit(0 if failures.is_empty() else 1)
