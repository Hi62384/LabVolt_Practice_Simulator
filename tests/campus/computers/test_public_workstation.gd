extends SceneTree
func _initialize() -> void:call_deferred("run")
func find_button(node: Node, title: String) -> Button:
	for item in node.find_children("*","Button",true,false):
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
	var computers: Node=game.computers
	var args:=OS.get_cmdline_user_args()
	var id:=str(args[0]) if not args.is_empty() else "m203_r3_c4"
	if not computers.stations.has(id) or not computers.stations[id].has("power"):
		push_error("Public workstation missing");quit(1);return
	var point: Vector3=computers.stations[id].anchor
	game.player.global_position=point
	game.session.poses[1]={"position":point}
	await physics_frame
	var station: Node3D=game.campus_services.get_node("ComputerCommons").stations[id] if id.begins_with("commons_") else game.computer_room_adapter.room.stations[id]
	var power_point: Vector3=station.to_global(Vector3(.69,.56,.025))
	var ray:=PhysicsRayQueryParameters3D.create(power_point+Vector3(0,0,.65),power_point,5)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not is_instance_valid(hit.get("collider")) or hit.collider.get_meta("role","")!="public_computer_power":
		push_error("Physical power button cannot be targeted");quit(1);return
	computers.request({"op":"power","station":id})
	if not computers.stations[id].power.powered:push_error("Workstation did not power on");quit(1);return
	computers.request({"op":"enter","station":id})
	if not computers.sessions.has(1) or not computers.local_snapshot.get("public_device",false):
		push_error("Public desktop did not open");quit(1);return
	if not game.computer_room_adapter.desktop.power_button.visible:
		push_error("Desktop power control missing");quit(1);return
	await process_frame
	if is_instance_valid(game.front.campus_hud) and game.front.campus_hud.visible:
		push_error("Room HUD overlays the desktop");quit(1);return
	if args.size()>1 and args[1]=="capture":
		await process_frame;await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/public-desktop.png"))!=OK:
			push_error("Desktop capture failed");quit(1);return
	var desktop: Control=game.computer_room_adapter.desktop
	if not desktop.folder_button.visible or not desktop.delete_button.visible:
		push_error("Public file controls missing");quit(1);return
	desktop.path_field.text="Labs";desktop.folder_button.pressed.emit()
	if "Labs" not in computers.local_snapshot.get("folders",[]):push_error("Folder creation failed");quit(1);return
	computers.last_request.erase(1)
	find_button(desktop,"New").pressed.emit()
	desktop.path_field.text="Labs/note.txt";desktop.editor.text="temporary"
	find_button(desktop,"Save  Ctrl+S").pressed.emit()
	if not computers.local_snapshot.files.has("Labs/note.txt"):push_error("Save failed");quit(1);return
	computers.last_request.erase(1)
	var folder_index:=-1
	for index in desktop.file_list.item_count:
		if desktop.file_list.get_item_metadata(index).get("path","")=="Labs":folder_index=index
	if folder_index<0:push_error("Folder missing from desktop");quit(1);return
	desktop.file_list.select(folder_index);desktop.path_field.text="Work"
	find_button(desktop,"Rename").pressed.emit()
	if not computers.local_snapshot.files.has("Work/note.txt") or "Work" not in computers.local_snapshot.folders:
		push_error("Folder rename lost its contents");quit(1);return
	computers._accept(1,{"op":"exit","lease":computers.local_snapshot.lease,"revision":computers.local_snapshot.revision})
	computers.request({"op":"enter","station":id})
	if not computers.local_snapshot.get("files",{}).has("Work/note.txt"):
		push_error("Powered computer lost files after leaving");quit(1);return
	computers.last_request.erase(1)
	folder_index=-1
	for index in desktop.file_list.item_count:
		if desktop.file_list.get_item_metadata(index).get("path","")=="Work":folder_index=index
	if folder_index<0:push_error("Renamed folder missing from desktop");quit(1);return
	desktop.file_list.select(folder_index);desktop.delete_button.pressed.emit()
	if not computers.local_snapshot.files.is_empty() or not computers.local_snapshot.folders.is_empty():
		push_error("Folder deletion left contents behind");quit(1);return
	computers.last_request.erase(1)
	computers.request({"op":"save","lease":computers.local_snapshot.lease,"revision":computers.local_snapshot.revision,"path":"discard.txt","text":"temporary","version":0})
	if not computers.local_snapshot.files.has("discard.txt"):push_error("Pre-shutdown save failed");quit(1);return
	computers.request({"op":"power","station":id})
	if computers.stations[id].power.powered or computers.sessions.has(1) or computers.public_workspaces.has(id):
		push_error("Power off failed to clear session");quit(1);return
	computers.request({"op":"power","station":id})
	computers.request({"op":"enter","station":id})
	if not computers.sessions.has(1) or not computers.local_snapshot.files.is_empty():
		push_error("Restart retained temporary files");quit(1);return
	computers.stations[id].power.last_activity_ms=Time.get_ticks_msec()-computers.stations[id].power.IDLE_TIMEOUT_MS
	computers._prune()
	if computers.stations[id].power.powered or computers.sessions.has(1):
		push_error("Idle shutdown did not close the workstation");quit(1);return
	print("PUBLIC_WORKSTATION PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()
