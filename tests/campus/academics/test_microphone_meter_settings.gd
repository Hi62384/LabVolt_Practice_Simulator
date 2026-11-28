extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.settings_page()
 var settings: Control=game.front.menu_page
 settings._select("Audio")
 var meter: Node
 for child in settings.body.get_children():
  if child.get_script()!=null and child.get_script().resource_path=="res://scripts/campus/voice/microphone_meter.gd":meter=child;break
 if not is_instance_valid(meter) or meter.running or meter.player!=null:
  push_error("Audio settings started or omitted the microphone test");quit(1);return
 # Exercise the settings node with the same tree-pause state used in a
 # singleplayer game. Device signal accuracy is checked by the capture test.
 paused=true
 if not meter._start() or not meter.microphone.can_process() or not meter.player.can_process():
  push_error("Paused Audio settings could not start and process the local microphone test");quit(1);return
 meter._stop()
 paused=false
 settings._select("Gameplay")
 await process_frame
 if is_instance_valid(meter) and meter.is_inside_tree():push_error("Microphone test remained mounted after leaving Audio settings");quit(1);return
 print("MICROPHONE_METER_SETTINGS PASS")
 game.queue_free();await process_frame;quit(0)
