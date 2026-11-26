extends SceneTree
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
func _initialize() -> void:call_deferred("run")
func button(node: Node,title: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if (b.text==title or b.accessibility_name==title) and b.is_visible_in_tree():return b
	return null
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null:fail("Singleplayer missing");return
	single.pressed.emit();await process_frame
	var play:=button(game.front.body,"Play")
	if play==null:fail("Play missing");return
	play.pressed.emit()
	for i in 10:await process_frame
	var profile=game.electronics.profile;profile.data.dollars=10000
	profile.buy_smartphone("premium")
	if not profile.operation_succeeded:fail("Phone purchase failed");return
	var id: String=profile.data.dorm.smartphones.keys()[0]
	game.hotbar._sync_dorm_items()
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	game.capture();await process_frame
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true;game._input(click)
	if not game.smartphones.is_ui_open() or game.smartphones.phone_shell.visible:fail("Phone should open with its display off");return
	game.smartphones.side_power.pressed.emit()
	if not game.smartphones.is_powered(id):fail("The side power button did not start the phone");return
	game.smartphones.close()
	var shutter:=InputEventMouseButton.new();shutter.button_index=MOUSE_BUTTON_LEFT;shutter.pressed=true;game._input(shutter)
	await process_frame
	if not game.smartphones.held.visible:fail("Held phone disappeared during capture");return
	for i in 4:await process_frame
	var state: Dictionary=Photos.list(game.school.local_identity,id)
	if state.has("error") or state.photos.size()!=1:fail("In-game capture failed");return
	game._input(click)
	for i in 4:await process_frame
	if not game.smartphones.is_ui_open():fail("Phone screen did not open");return
	if button(game.smartphones.panel,"Camera")==null:fail("Camera launcher missing");return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/phone-home.png")
	button(game.smartphones.panel,"Camera").pressed.emit()
	for i in 4:await process_frame
	if not game.smartphones.camera_hint.visible or Photos.list(game.school.local_identity,id).photos.size()!=1:
		fail("Opening Camera took a photo or did not enter the viewfinder");return
	game._input(click)
	await process_frame
	var photos:=button(game.smartphones.panel,"Photos")
	if photos==null:fail("Photos launcher missing");return
	photos.pressed.emit()
	for i in 4:await process_frame
	if not root.get_visible_rect().encloses(game.smartphones.panel.get_global_rect()):fail("Photos extended outside the screen");return
	var thumbnails: Array=game.smartphones.content.find_children("*","TextureButton",true,false)
	if thumbnails.size()!=1:fail("Gallery missing photo thumbnail");return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/phone-gallery.png"))!=OK:fail("Screenshot failed");return
	thumbnails[0].pressed.emit();await process_frame
	var remove:=button(game.smartphones.panel,"Delete photo")
	if remove==null:fail("Photo detail missing delete action");return
	game.smartphones.close()
	var phone_slot: int=game.hotbar.active
	game.hotbar.active=-1
	await process_frame
	game.hotbar.active=phone_slot
	game.smartphones.open()
	if button(game.smartphones.panel,"Delete photo")!=remove:fail("Re-equipping lost the open photo");return
	remove.pressed.emit();await process_frame
	var dialog: ConfirmationDialog
	for node in game.smartphones.panel.find_children("*","ConfirmationDialog",true,false):dialog=node;break
	if dialog==null:fail("Delete confirmation missing");return
	dialog.canceled.emit();await process_frame
	if Photos.list(game.school.local_identity,id).photos.size()!=1:fail("Cancel deleted photo");return
	remove.pressed.emit();await process_frame
	for node in game.smartphones.panel.find_children("*","ConfirmationDialog",true,false):dialog=node;break
	dialog.confirmed.emit();await process_frame
	if not Photos.list(game.school.local_identity,id).photos.is_empty():fail("Photo delete failed");return
	button(game.smartphones.panel,"Home").pressed.emit();await process_frame
	var calc:=button(game.smartphones.panel,"Calculator")
	if calc==null:fail("Calculator tab missing");return
	calc.pressed.emit();await process_frame
	var two:=button(game.smartphones.panel,"2");var plus:=button(game.smartphones.panel,"+");var three:=button(game.smartphones.panel,"3");var equals:=button(game.smartphones.panel,"=")
	if two==null or plus==null or three==null or equals==null:fail("Calculator controls missing");return
	two.pressed.emit();plus.pressed.emit();three.pressed.emit();equals.pressed.emit()
	var calculator: Node=two.get_parent().get_parent().get_parent()
	if not is_equal_approx(float(calculator.result.text),5.0):fail("Calculator result incorrect");return
	for control in game.smartphones.panel.find_children("*","Button",true,false):
		if control.tooltip_text=="Phone volume":control.pressed.emit();break
	if not game.smartphones.volume_slider.is_visible_in_tree():fail("Phone volume is missing");return
	game.smartphones.volume_slider.value=70
	if game.smartphones._phone_volume(id)!=70:fail("Phone volume did not change");return
	button(game.smartphones.panel,"Home").pressed.emit();await process_frame
	var messages:=button(game.smartphones.panel,"Messages")
	if messages==null:fail("Messages tab missing");return
	messages.pressed.emit();await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/phone-messages.png"))!=OK:fail("Messages screenshot failed");return
	var test_browser: bool="--browser" in OS.get_cmdline_user_args()
	if test_browser:
		button(game.smartphones.panel,"Home").pressed.emit();await process_frame
		button(game.smartphones.panel,"Browser").pressed.emit();await process_frame
		var browser: Node=game.smartphones.browser_surface
		if not is_instance_valid(browser) or not browser.renderer_available():fail("Phone browser unavailable");return
		var until:=Time.get_ticks_msec()+10000
		while not str(browser._browser().get_url()).contains("google.com") and Time.get_ticks_msec()<until:await process_frame
		if not str(browser._browser().get_url()).contains("google.com"):fail("Browser did not open Google");return
		browser.phone_new_tab.pressed.emit()
		until=Time.get_ticks_msec()+10000
		while not str(browser._browser().get_url()).contains("google.com") and Time.get_ticks_msec()<until:await process_frame
		if browser.tabs.size()!=2 or not str(browser._browser().get_url()).contains("google.com"):fail("New tab did not open Google");return
		if browser.holder.size.y<game.smartphones.panel.size.y*.55:fail("Browser page too short");return
		var active_browser: Node=browser._browser()
		active_browser.load_data_uri("<script>let ticks=0;setInterval(()=>document.title='tick:'+ ++ticks,50)</script>","text/html")
		until=Time.get_ticks_msec()+3000
		while not str(active_browser.get_title()).begins_with("tick:") and Time.get_ticks_msec()<until:await process_frame
		if not str(active_browser.get_title()).begins_with("tick:"):fail("Browser timer fixture did not load");return
		game.smartphones.close()
		game.hotbar.active=-1
		for frame in 3:await process_frame
		if not active_browser.has_method("set_page_suspended") or not browser.phone_suspended:fail("Unequipping did not suspend the browser");return
		await create_timer(.35).timeout
		var suspended_title: String=active_browser.get_title()
		await create_timer(1.3).timeout
		if active_browser.get_title()!=suspended_title:fail("The page timer ran while the phone was stowed");return
		game.hotbar.active=phone_slot
		for frame in 3:await process_frame
		if browser.phone_suspended:fail("Re-equipping did not resume the browser");return
		until=Time.get_ticks_msec()+2500
		while active_browser.get_title()==suspended_title and Time.get_ticks_msec()<until:await process_frame
		if active_browser.get_title()==suspended_title:fail("The page timer did not resume");return
		game.smartphones.open()
		if not is_same(game.smartphones.browser_surface,browser) or not is_same(browser._browser(),active_browser):
			fail("Reopening the phone replaced its browser session");return
		await create_timer(.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/phone-browser.png")
	game.smartphones.close()
	await process_frame
	var texture: Texture2D=game.smartphones.phone_view.get_texture()
	if game.smartphones.held_screen.material_override.albedo_texture!=texture:fail("Held phone did not mirror its current app");return
	game.camera.rotation.x=-.77
	await physics_frame
	var place:=InputEventKey.new()
	place.physical_keycode=KEY_F
	place.pressed=true
	game._input(place)
	await physics_frame
	var world_phone: Node3D=game.smartphones._placed_model(id)
	if not is_instance_valid(world_phone) or not game.smartphones.selected().is_empty():fail("F did not place the phone");return
	if world_phone.get_meta("phone_screen").material_override.albedo_texture!=texture:fail("Placed phone did not mirror its current app");return
	if test_browser:
		var browser: Node=game.smartphones.browser_surface
		if not is_instance_valid(browser) or browser.speaker_position.distance_to(world_phone.global_position)>.05 or browser.speaker_volume!=70:
			fail("Phone audio did not follow the placed phone at the selected volume");return
	game.current_target=world_phone
	game._input(click)
	if not game.smartphones.is_ui_open():fail("Placed phone did not open");return
	game.smartphones.close()
	game.current_target=world_phone
	game._input(shutter)
	if is_instance_valid(game.smartphones._placed_model(id)):fail("Phone pickup failed");return
	print("PHONE_VISUAL PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()
