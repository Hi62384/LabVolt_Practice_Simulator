extends SceneTree
var held := false
const COMMAND = "res://tests/live_student_command.json"
func key(value: bool):
 if held == value: return
 held = value
 var event := InputEventKey.new()
 event.physical_keycode = KEY_W
 event.pressed = value
 Input.parse_input_event(event)
func _initialize(): call_deferred("run")
func run():
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 for i in 4: await process_frame
 game.session.message_received.connect(func(message): print("NOTICE ",message))
 game.front.network_page(true)
 game.front.join_code.text = "SH3VEXSDS3@arshya-ghafaryan"
 game.front.join_connect.pressed.emit()
 var end = Time.get_ticks_msec() + 25000
 while Time.get_ticks_msec() < end and game.front.joining: await create_timer(0.25).timeout
 if game.session.roster.size() < 2:
  print("JOIN_FAILED ", game.front.status.text)
  quit(1)
  return
 print("CONTROL_CONNECTED ", game.session.roster)
 var last_check := 0
 while game.session.online:
  await physics_frame
  if game.session.poses.has(1):
   var offset: Vector3 = game.session.poses[1].position - game.player.position
   offset.y = 0
   if offset.length() > 2.3:
    game.player.yaw_target = atan2(-offset.x, -offset.z)
    key(true)
   elif offset.length() < 1.8: key(false)
  if Time.get_ticks_msec() - last_check > 500:
   last_check = Time.get_ticks_msec()
   if FileAccess.file_exists(COMMAND):
    var command = JSON.parse_string(FileAccess.get_file_as_string(COMMAND))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(COMMAND))
    if command is Dictionary:
     if command.get("op","") == "inspect":
      print("STUDENT_POS ",game.player.global_position," HOST_POS ",game.session.poses.get(1,{})," STATIONS ",game.station_snapshots)
      for i in game.session.labs.size(): print("POSITIONS ",i," ",game.session.labs[i].positions)
     else:
      print("REQUEST ",command)
      game.session.request(command)
 key(false)
 print("CONTROL_DISCONNECTED")
 quit(1)
