extends SceneTree
## Native rendering of the actual Audio settings page; sample values are
## synthetic UI state, with no physical microphone or provider request claim.
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(condition: bool,text: String) -> void:
 if not condition:failures.append(text);push_error(text)
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(2);return
 var path:=OS.get_environment("LABVOLT_MIC_RENDER_OUTPUT")
 if path.is_empty():quit(2);return
 create_timer(90.).timeout.connect(func():push_error("MICROPHONE_SETTINGS_RENDER timeout");quit(1))
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for index in 4:await process_frame
 game.client_preferences.set_option("microphone_muted",true)
 game.front.settings_page()
 var settings: Control=game.front.menu_page;settings._select("Audio")
 var meter: Node
 for child in settings.body.get_children():
  if child.get_script()==load("res://scripts/campus/voice/microphone_meter.gd"):meter=child;break
 check(is_instance_valid(meter),"The actual Audio settings must mount the microphone test")
 if not is_instance_valid(meter):quit(1);return
 var scroll: ScrollContainer=settings.body.get_parent()
 for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
  root.size=size
  for index in 8:await process_frame
  scroll.ensure_control_visible(meter)
  for index in 8:await process_frame
  for button: Button in [meter.toggle,meter.record_button,meter.play_button]+meter.test_buttons:
   var rectangle:=button.get_global_rect()
   check(rectangle.position.x>=scroll.global_position.x-1. and rectangle.end.x<=scroll.get_global_rect().end.x+1.,"Microphone button remains inside viewport at "+str(size)+": "+button.text)
   check(rectangle.size.y>=24.,"Microphone buttons have readable hit targets")
  check(not meter.running,"Opening settings must not start the microphone")
  await RenderingServer.frame_post_draw
  check(root.get_texture().get_image().save_png(path.path_join("microphone-settings-%dx%d.png"%[size.x,size.y]))==OK,"Saved native settings screenshot")
 meter.last_sample=PackedByteArray([1,0,1,0]);meter._enable_buttons()
 meter.stages.text="Synthetic UI fixture: 6.00 seconds · Peak −18.2 dB · RMS −31.4 dB · 96000 samples · Local speech detection: below threshold"
 meter.note.text="Sample saved in memory. Play it back to check your microphone; nothing was uploaded."
 for index in 8:await process_frame
 scroll.ensure_control_visible(meter)
 for index in 8:await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(path.path_join("microphone-sample-ready-960x540.png"))==OK,"Saved local sample state")
 var file:=FileAccess.open(path.path_join("result.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"physical_microphone":false,"provider":false,"failures":failures},"  "));file.close()
 game.queue_free();await process_frame
 print("MICROPHONE_SETTINGS_RENDER ","PASS" if failures.is_empty() else "FAIL")
 quit(0 if failures.is_empty() else 1)
