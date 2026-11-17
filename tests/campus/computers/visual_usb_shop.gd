extends SceneTree
func _initialize() -> void:call_deferred("run")
func find_button(root_node: Node,title: String) -> Button:
	for item in root_node.find_children("*","Button",true,false):
		if item.text==title and item.is_visible_in_tree():return item
	return null
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var single:=find_button(game.front.body,"Singleplayer")
	if single==null:push_error("Singleplayer missing");quit(1);return
	single.pressed.emit();await process_frame
	var play:=find_button(game.front.body,"Play")
	if play==null:push_error("Play missing");quit(1);return
	play.pressed.emit();await process_frame
	game.electronics.profile.data.dollars=1000
	game.electronics.shop_section=2;game.electronics.open("shop")
	await process_frame
	var card: Node
	for label in game.electronics.screen.find_children("*","Label",true,false):
		if label.text=="8 MB USB drive":card=label.get_parent();break
	if card==null:push_error("USB shop card missing");quit(1);return
	var details:=find_button(card,"Details")
	if details==null:push_error("USB details missing");quit(1);return
	details.pressed.emit();await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/usb-shop-visual.png"))!=OK:quit(1);return
	var buy:=find_button(game.electronics.screen,"Buy for $20")
	if buy==null:push_error("USB buy button missing");quit(1);return
	buy.pressed.emit();buy.pressed.emit()
	var drives: Dictionary=game.electronics.profile.data.dorm.get("usb_drives",{})
	if drives.size()!=1:push_error("Repeated click bought multiple USB drives");quit(1);return
	var id: String=drives.keys()[0]
	game.electronics.open("inventory");await process_frame
	var rename:=find_button(game.electronics.screen,"Rename")
	if rename==null:push_error("USB rename control missing");quit(1);return
	rename.pressed.emit();await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/usb-rename-visual.png"))!=OK:quit(1);return
	var dialog: ConfirmationDialog
	for node in game.electronics.screen.find_children("*","ConfirmationDialog",true,false):
		if node.title=="Rename USB drive":dialog=node;break
	if dialog==null:push_error("Rename dialog missing");quit(1);return
	var field: LineEdit=dialog.find_children("*","LineEdit",true,false)[0]
	field.text="   ";field.text_changed.emit(field.text)
	if not dialog.get_ok_button().disabled:push_error("Blank name was accepted");quit(1);return
	dialog.confirmed.emit()
	if drives[id].name!="USB drive":push_error("Invalid name changed the drive");quit(1);return
	field.text="Unwanted";field.text_changed.emit(field.text);dialog.canceled.emit();await process_frame
	if drives[id].name!="USB drive":push_error("Cancelled rename changed the drive");quit(1);return
	game.hotbar._rename_usb_dialog(id);await process_frame
	for node in game.electronics.screen.find_children("*","ConfirmationDialog",true,false):
		if node.title=="Rename USB drive":dialog=node;break
	field=dialog.find_children("*","LineEdit",true,false)[0]
	field.text="Lab files";field.text_changed.emit(field.text)
	var revision: int=game.electronics.profile.data.dorm.revision
	dialog.confirmed.emit();dialog.confirmed.emit()
	if game.electronics.profile.data.dorm.usb_drives[id].name!="Lab files" or int(game.electronics.profile.data.dorm.revision)!=revision+1:push_error("Rename repeat handling failed");quit(1);return
	print("USB_SHOP_UI PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()
