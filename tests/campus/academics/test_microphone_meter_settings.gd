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
 settings._select("Gameplay")
 await process_frame
 if is_instance_valid(meter) and meter.is_inside_tree():push_error("Microphone test remained mounted after leaving Audio settings");quit(1);return
 print("MICROPHONE_METER_SETTINGS PASS")
 game.queue_free();await process_frame;quit(0)
