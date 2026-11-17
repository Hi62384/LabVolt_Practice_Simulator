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
 browser.load_data_uri("<html><head><title>LabVolt Browser Fixture</title></head><body><h1>Browser paint</h1><input type='file'></body></html>","text/html")
 var deadline:=Time.get_ticks_msec()+12000
 while (not loaded or browser.get_title()!="LabVolt Browser Fixture") and Time.get_ticks_msec()<deadline:await process_frame
 if browser.get_title()!="LabVolt Browser Fixture":failures.append("Local HTML title did not load")
 if browser.get_texture()==null:failures.append("Browser texture was not created")
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
