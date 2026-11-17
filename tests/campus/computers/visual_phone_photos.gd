extends SceneTree
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
func _initialize() -> void:call_deferred("run")
func button(node: Node,title: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if b.text==title and b.is_visible_in_tree():return b
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
	game.electronics.shop_section=2;game.electronics.open("shop");await process_frame
	var card: Node
	for label in game.electronics.screen.find_children("*","Label",true,false):
		if label.text=="Premium smartphone":card=label.get_parent();break
	if card==null:fail("Phone shop card missing");return
	var details:=button(card,"Details")
	if details==null:fail("Phone shop details missing");return
	details.pressed.emit();await process_frame
	var buy:=button(game.electronics.screen,"Buy for $1200")
	if buy==null:fail("Phone buy button missing");return
	buy.pressed.emit();await process_frame
	if not profile.operation_succeeded:fail("Phone purchase failed");return
	game.electronics.close();await process_frame
	var id: String=profile.data.dorm.smartphones.keys()[0]
	game.hotbar._sync_dorm_items()
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	game.capture();await process_frame
	var key:=InputEventKey.new();key.keycode=KEY_P;key.pressed=true;game._input(key)
	for i in 4:await process_frame
	var state: Dictionary=Photos.list(game.school.local_identity,id)
	if state.has("error") or state.photos.size()!=1:fail("In-game capture failed");return
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true;game._input(click)
	for i in 4:await process_frame
	if not game.smartphones.panel.visible:fail("Phone screen did not open");return
	var remove:=button(game.smartphones.panel,"Delete photo")
	if remove==null:fail("Gallery missing photo");return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/phone-gallery.png"))!=OK:fail("Screenshot failed");return
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
	var calc:=button(game.smartphones.panel,"Calculator")
	if calc==null:fail("Calculator tab missing");return
	calc.pressed.emit();await process_frame
	var two:=button(game.smartphones.panel,"2");var plus:=button(game.smartphones.panel,"+");var three:=button(game.smartphones.panel,"3");var equals:=button(game.smartphones.panel,"=")
	if two==null or plus==null or three==null or equals==null:fail("Calculator controls missing");return
	two.pressed.emit();plus.pressed.emit();three.pressed.emit();equals.pressed.emit()
	var calculator: Node=two.get_parent().get_parent().get_parent()
	if not is_equal_approx(float(calculator.result.text),5.0):fail("Calculator result incorrect");return
	var messages:=button(game.smartphones.panel,"Messages")
	if messages==null:fail("Messages tab missing");return
	messages.pressed.emit();await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/phone-messages.png"))!=OK:fail("Messages screenshot failed");return
	print("PHONE_VISUAL PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()
