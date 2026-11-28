extends SceneTree
## Native full-game companion to test_menu_routes.gd. Uses real pointer events
## on the actual menu controls, and captures both entered gameplay sessions.
var failures: Array[String]=[]
var evidence: Array[Dictionary]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error("STARTUP_RENDER: "+message)

func button(parent: Node,label: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==label and node.is_visible_in_tree():return node
	return null

func click(control: Button) -> void:
	check(is_instance_valid(control),"Expected menu button exists")
	if not is_instance_valid(control):return
	check(not control.disabled,"Clicked menu control is enabled")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var point:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		Input.parse_input_event(event)
		await process_frame

func capture(name: String) -> void:
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var output:=OS.get_environment("LABVOLT_STARTUP_CAPTURE")
	check(not output.is_empty(),"Capture destination provided")
	if output.is_empty():return
	var image:=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"Native renderer supplied a real framebuffer")
	if image!=null and not image.is_empty():check(image.save_png(output.path_join(name+".png"))==OK,"Captured "+name)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("STARTUP_RENDER requires an actual display; headless images are not accepted")
		quit(2);return
	create_timer(90.).timeout.connect(func():push_error("STARTUP_RENDER deadline");quit(3))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 5:await process_frame
	await capture("startup-menu")
	for offline: bool in [true,false]:
		var label:="Singleplayer" if offline else "Host Game"
		await click(button(game.front.body,label))
		check(game.front.page==("singleplayer" if offline else "host"),label+" pointer input opens options")
		await click(button(game.front.body,"Play"))
		var deadline:=Time.get_ticks_msec()+15000
		while not game.front.in_game and Time.get_ticks_msec()<deadline:await process_frame
		check(game.front.in_game and game.player.enabled and not game.front.screen.visible,label+" pointer input enters playable world")
		check(game.session.online==not offline,label+" starts the correct session type")
		if not offline:check(game.session.room_code().length()==10,"Production relay issues a host room code")
		check(is_instance_valid(game.faculty) and is_instance_valid(game.lecture_classes.classroom_students),"Actual faculty and student systems are mounted")
		evidence.append({"mode":label,"in_game":game.front.in_game,"player_enabled":game.player.enabled,"online":game.session.online,"room_code_received":game.session.room_code().length()==10,"faculty_mounted":is_instance_valid(game.faculty)})
		await capture("singleplayer-gameplay" if offline else "host-gameplay")
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.physical_keycode=KEY_ESCAPE;escape.pressed=true;Input.parse_input_event(escape)
		await process_frame
		await click(button(game.front.body,"Leave to Main Menu"))
		check(not game.front.in_game and game.front.page=="home",label+" exits through the menu control")
	var output:=OS.get_environment("LABVOLT_STARTUP_CAPTURE")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("native-gameplay.json"),FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"routes":evidence,"failures":failures},"  "));file.close()
	game.queue_free();await process_frame
	print("MENU_STARTUP_RENDER ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
