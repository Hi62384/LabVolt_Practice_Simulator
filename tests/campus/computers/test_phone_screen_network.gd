extends SceneTree
## Run two graphical processes with separate APPDATA directories and the same local port.
const Configuration=preload("res://scripts/campus/items/equipment_configuration.gd")
var game: Node
var deadline: int
const POSITION := Vector3(13,0,-18)
const FIRST := Color("e93587")
const SECOND := Color("35db76")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"] or DisplayServer.get_name()=="headless":
		_fail("Run graphically with host or client followed by a local port.")
		return
	var host:=args[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	var profile: RefCounted=game.electronics.profile
	profile.open("handset-screen-"+args[0])
	game.school.local_identity=profile.data.dorm.owner
	profile.data.dollars=10000
	if host:
		if game.session.host_game("Viewer",int(args[1]))!=OK:
			_fail("Could not start the handset host.")
			return
		print("HANDSET_HOST_READY")
	elif game.session.join_game("127.0.0.1","Phone owner",int(args[1]))!=OK:
		_fail("Could not join the handset host.")
		return
	deadline=Time.get_ticks_msec()+75000
	if not await _until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"both players bind"):
		return
	print("HANDSET_BOUND ",args[0])
	game.front.screen.hide()
	game.front.in_game=true
	game.menu_campus.enter_game()
	game.session.campus_enabled=true
	game.player.enabled=false
	game.player.global_position=POSITION+Vector3(0,0,1 if host else 0)
	game.session.send_pose({"position":game.player.global_position})
	if host:
		await _observe()
	else:
		await _broadcast(profile)

func _broadcast(profile: RefCounted) -> void:
	var configuration:=Configuration.defaults(Configuration.PHONE)
	configuration.appearance.shell=2
	profile.buy_smartphone("basic",6,"",configuration)
	if not await _until(func():return not profile.data.dorm.get("smartphones",{}).is_empty(),"phone purchase"):return
	var id: String=profile.data.dorm.smartphones.keys()[0]
	print("HANDSET_SOURCE_READY")
	var phone: Node=game.smartphones
	phone.set_process(false)
	phone.powered_on[id]=true
	var live_view:=SubViewport.new()
	live_view.size=Vector2i(96,168)
	live_view.disable_3d=true
	live_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(live_view)
	var swatch:=ColorRect.new()
	swatch.size=Vector2(live_view.size)
	live_view.add_child(swatch)
	for color in [FIRST,SECOND]:
		swatch.color=color
		await RenderingServer.frame_post_draw
		var until:=Time.get_ticks_msec()+7000
		while Time.get_ticks_msec()<until:
			game.session.send_pose({"position":POSITION})
			phone._publish_handset(id,live_view.get_texture())
			await create_timer(.15).timeout
	phone.powered_on.erase(id)
	while Time.get_ticks_msec()<deadline and game.session.roster.size()==2:
		game.session.send_pose({"position":POSITION})
		phone._publish_handset(id,live_view.get_texture())
		await create_timer(.15).timeout
	if game.session.roster.size()!=1:
		_fail("Viewer did not complete the screen checks.")
		return
	print("HANDSET_CLIENT PASS")
	quit()

func _observe() -> void:
	var phone: Node=game.smartphones
	if not await _until(func():return not phone.remote_phone_models.is_empty(),"remote handset model"):return
	print("HANDSET_MODEL_READY")
	var peer: int=phone.remote_phone_models.keys()[0]
	var handset: Node3D=phone.remote_phone_models[peer].model
	if not handset.get_meta("phone_shell").material_override.albedo_color.is_equal_approx(Color("27745e")):
		_fail("The viewer did not receive the purchased case finish.")
		return
	var camera:=Camera3D.new()
	game.add_child(camera)
	# The gameplay camera controls the observer's frame and distance checks.
	game.camera=camera
	camera.make_current()
	for color in [FIRST,SECOND]:
		if not await _until(func():
			var live_screen: MeshInstance3D=phone.remote_phone_models.get(peer,{}).get("screen")
			if not is_instance_valid(live_screen):return false
			camera.global_position=live_screen.global_position+live_screen.global_basis.z.normalized()*.29+Vector3.RIGHT*.18
			camera.look_at(live_screen.global_position)
			return _received_color(live_screen).is_equal_approx(color)
		,"live screen color "+color.to_html()):return
		await RenderingServer.frame_post_draw
		var screen: MeshInstance3D=phone.remote_phone_models.get(peer,{}).get("screen")
		if not is_instance_valid(screen):_fail("Handset disappeared before rendering");return
		var frame:=root.get_texture().get_image()
		var relative:=camera.unproject_position(screen.global_position)/camera.get_viewport().get_visible_rect().size
		var point:=Vector2i(relative*Vector2(frame.get_size()))
		if not Rect2i(Vector2i.ZERO,frame.get_size()).has_point(point):
			_fail("The projected handset is outside the captured viewport.")
			return
		var pixel:=frame.get_pixelv(point)
		if (color==FIRST and (pixel.r<=pixel.g or pixel.b<=pixel.g)) or (color==SECOND and (pixel.g<=pixel.r or pixel.g<=pixel.b)):
			frame.save_png("user://phone-screen-failure.png")
			_fail("The received screen color did not appear in the game viewport. Pixel "+pixel.to_html())
			return
	if not await _until(func():
		var live_screen: MeshInstance3D=phone.remote_phone_models.get(peer,{}).get("screen")
		return is_instance_valid(live_screen) and (live_screen.material_override as StandardMaterial3D).albedo_texture==null
	,"remote power-off"):return
	print("HANDSET_HOST PASS")
	game.session.leave()
	await create_timer(.4).timeout
	quit()

func _received_color(screen: MeshInstance3D) -> Color:
	if not is_instance_valid(screen):return Color.BLACK
	var material:=screen.material_override as StandardMaterial3D
	var texture:=material.albedo_texture as ImageTexture
	return texture.get_image().get_pixel(24,42) if is_instance_valid(texture) else Color.BLACK

func _until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	_fail("Timed out waiting for "+label)
	return false

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
