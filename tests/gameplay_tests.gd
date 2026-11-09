extends SceneTree
var game: Node
var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,text: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL GAMEPLAY: "+text)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func request(action: Dictionary) -> void:
	# Domain reach checks use the last authoritative pose; simulate actual walking.
	game.session.poses[1] = {"position":game.player.position}
	game.session.request(action)
	await wait(.1)

func aim(body: StaticBody3D) -> void:
	game.player.position = body.global_position + Vector3(0,-.8,1.3)
	game.player.position.y = maxf(game.player.position.y,0)
	game.session.poses[1] = {"position":game.player.position}
	game.current_target = body

func run() -> void:
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await wait(.4)
	check(game.snapshot.cables.is_empty(),"game starts unwired")
	check(game.front.screen.visible and not game.ui.menu.visible,"title menu replaces lobby")
	check(game.player is CharacterBody3D,"collision-based first person body")
	if OS.get_cmdline_user_args().has("--visual"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/menu_preview.png")
	game.capture()
	await wait(.3)
	check(game.player.is_on_floor(),"floor collision")
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_SPACE
	jump.pressed = true
	Input.parse_input_event(jump)
	await wait(.2)
	check(game.player.position.y>.2,"jump lifts collision body")
	jump.pressed = false
	Input.parse_input_event(jump)
	await wait(1)
	check(game.player.is_on_floor(),"gravity returns player to floor")
	game.player.position=Vector3(0,0,-.7)
	await request({"op":"drawer"})
	await wait(.35)
	check(game.snapshot.drawer_open and game.drawer.tray.position.z>.8,"drawer slides open")
	var rack: StaticBody3D = game.drawer.bags[0]
	check(rack!=null,"physical cable rack")
	aim(rack)
	game.activate()
	await wait(.1)
	check(game.snapshot.cables.size()==1 and game.snapshot.cables[0].owner==1,"actual rack interaction picks up cable")
	aim(game.terminal_bodies.P_A)
	game.camera.look_at(game.terminal_bodies.P_A.global_position,Vector3.UP)
	check(is_instance_valid(game._get_target()) and game._get_target().get_meta("id","")=="P_A","crosshair ray resolves actual socket within physical reach")
	game.activate()
	await wait(.1)
	check(game.snapshot.cables[0].a=="P_A" and game.snapshot.cables[0].b=="","first end independently attached")
	aim(game.terminal_bodies.R0_P)
	game.activate()
	await wait(.1)
	check(game.snapshot.cables[0].owner==0 and game.snapshot.cables[0].b=="R0_P","second end attached")
	game.player.position = Vector3(rack.global_position.x,0,rack.global_position.z+1.0)
	await request({"op":"pickup","color":3})
	aim(game.terminal_bodies.R0_N)
	game.activate()
	await wait(.1)
	aim(game.terminal_bodies.P_N)
	game.activate()
	await wait(.1)
	var switch: StaticBody3D = game.switch_meshes.R_0.handle.get_parent()
	aim(switch)
	game.activate()
	await wait(.1)
	check(game.snapshot.switches.R[0],"physical switch interaction changes circuit")
	aim(game.control_bodies.power)
	game.activate()
	await wait(.1)
	check(game.snapshot.powered,"power control energized")
	check(absf(game.snapshot.readings.p-12)<.001,"real circuit power in game")
	aim(game.control_bodies.power)
	game.activate()
	await wait(.1)
	check(not game.snapshot.powered,"power control de-energized")
	game._receive_pose(42,{"position":Vector3(1,0,0),"yaw":.5,"pitch":0,"crouch":true})
	await wait(.1)
	check(game.avatars.has(42) and game.avatars[42].has_node("CharacterModel"),"visible remote avatar")
	check(game.avatars[42].scale.y<.9,"remote crouch interpolates")
	game.avatars[42].queue_free()
	game.avatars.erase(42)
	game.avatar_targets.erase(42)
	aim(game.terminal_bodies.P_A)
	game.unplug()
	await wait(.1)
	check(game.snapshot.cables[0].a=="" and game.snapshot.cables[0].owner==1,"physical cable removal")
	await request({"op":"return"})
	await request({"op":"reset"})
	check(game.snapshot.cables.is_empty() and not game.snapshot.switches.R.has(true),"game reset")
	game.current_target=null
	var zoom := InputEventMouseButton.new()
	zoom.button_index=MOUSE_BUTTON_WHEEL_UP
	zoom.pressed=true
	var old_fov: float = game.camera.fov
	game._input(zoom)
	check(game.camera.fov<old_fov,"camera zoom input")
	aim(game.control_bodies.variable)
	var mouse := InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT
	mouse.pressed=true
	game._input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.relative=Vector2(40,0)
	var old_level: float = game.snapshot.level
	game._input(motion)
	mouse.pressed=false
	game._input(mouse)
	await wait(.1)
	check(game.snapshot.level>old_level,"physical knob drag changes source setting")
	game.player.position=Vector3(0,0,-1)
	await request({"op":"drawer"})
	await wait(.4)
	# Actual movement input against the workstation collision body.
	game.player.position = Vector3(0,0,-1.7)
	game.player.rotation.y = 0
	game.player.yaw_target = 0
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await wait(1.3)
	key.pressed = false
	Input.parse_input_event(key)
	await wait(.2)
	check(game.player.position.z > -2.8,"workstation blocks walking through equipment")
	check(game.player.position.z < -1.8,"WASD moves player")
	key = InputEventKey.new()
	key.physical_keycode = KEY_CTRL
	key.pressed = true
	Input.parse_input_event(key)
	await wait(.2)
	check(game.player.crouched and game.camera.position.y<1.1,"crouch changes eye height and capsule")
	key.pressed = false
	Input.parse_input_event(key)
	game.player.position = Vector3(0,0,1.75)
	game.player.enabled = false
	game.camera.rotation.x = 0
	game.player.pitch_target = 0
	game.camera.fov = 72
	game.ui.log_message("Rendered verification: unwired laboratory / equipment interaction tested.")
	await wait(.5)
	if OS.get_cmdline_user_args().has("--visual"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/laboratory_preview.png")
	print("GAMEPLAY: %d assertions, %d failures"%[assertions,failures])
	quit(1 if failures else 0)
