extends SceneTree
func accept_dialog(desktop: Control, text := "") -> void:
	for child in desktop.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			var controls:=child.find_children("*","LineEdit",true,false)
			if not controls.is_empty():controls[0].text=text
			child.confirmed.emit()
			return

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
	var power_point: Vector3=station.to_global(Vector3(.58,.98,.025))
	var ray:=PhysicsRayQueryParameters3D.create(power_point+Vector3(0,0,.65),power_point,5)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not is_instance_valid(hit.get("collider")) or hit.collider.get_meta("role","")!="public_computer_power":
		push_error("Physical power button cannot be targeted");quit(1);return
	if station.screen_material.albedo_texture!=null or station.led_material.albedo_color.r>.25:
		push_error("Powered-off monitor or LED lit");quit(1);return
	computers.request({"op":"power","station":id})
	if station.screen.material_override.albedo_texture!=game.computer_room_adapter.boot_render.get_texture() or station.power_led.material_override.albedo_color.g<.6:
		push_error("Powered monitor or LED did not update");quit(1);return
	if args.size()>1 and args[1]=="capture":
		var camera := Camera3D.new()
		station.add_child(camera)
		camera.position=Vector3(.12,1.17,.86)
		camera.look_at(station.screen.global_position)
		camera.make_current()
		await create_timer(.48).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/campus-os-boot.png")
		camera.queue_free()
		game.player.eyes.make_current()
	var preview: Control=game.computer_room_adapter.idle_render.get_child(0)
	if not preview.shortcuts_by_name.has("Settings") or game.computer_room_adapter.boot_desktop.texture!=game.computer_room_adapter.idle_render.get_texture():
		push_error("Boot did not transition to the current Campus OS shell");quit(1);return
	if not computers.stations[id].power.powered:push_error("Workstation did not power on");quit(1);return
	computers.request({"op":"enter","station":id})
	if computers.sessions.has(1):push_error("Boot accepted a premature login");quit(1);return
	await create_timer(1.7).timeout
	computers.request({"op":"enter","station":id})
	if not computers.sessions.has(1) or not computers.local_snapshot.get("public_device",false):
		push_error("Public desktop did not open");quit(1);return
	if game.player.seated!=null:
		push_error("Using a workstation forced the player into its chair");quit(1);return
	game._request_chair(int(computers.stations[id].chair))
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
	assert(root.disable_3d, "Campus OS should suspend rendering the covered world")
	if not desktop.windows.is_empty() or "Course work" in desktop.app_names:
		push_error("A fresh desktop opened an app or exposed Course work");quit(1);return
	assert(not desktop.task_buttons.Files.visible and not desktop.task_buttons.Browser.visible)
	if DisplayServer.get_name()!="headless":
		var pixels: Vector2i=game.computer_room_adapter.desktop_render.size
		var expected:=Vector2i((desktop.size*root.get_stretch_transform().get_scale()).round())
		if pixels!=expected:push_error("Desktop render target is below display resolution");quit(1);return
		print("DESKTOP_NATIVE_PIXELS ",pixels)
	if station.screen.material_override.albedo_texture!=game.computer_room_adapter.desktop_render.get_texture():
		push_error("Local monitor did not bind the active desktop");quit(1);return
	desktop._switch_app("Calculator")
	var calculator: Control=desktop.content.get_child(0)
	calculator.display.text="2+3"
	var calculator_window: Control=desktop.app_window
	if not desktop.workspace.get_global_rect().encloses(calculator_window.get_global_rect()):
		push_error("The calculator opened partly outside the desktop");quit(1);return
	desktop._switch_app("Files")
	if not calculator_window.visible:
		push_error("Opening Files hid the calculator");quit(1);return
	desktop._minimize_window("Calculator")
	desktop._switch_app("Calculator")
	if desktop.content.get_child(0)!=calculator or calculator.display.text!="2+3":
		push_error("Taskbar restore lost calculator state");quit(1);return
	var before_maximize: Rect2=calculator_window.get_rect()
	desktop._toggle_maximize("Calculator")
	if not desktop.windows.Calculator.maximized or not calculator_window.get_global_rect().is_equal_approx(desktop.workspace.get_global_rect()) or desktop.workspace.size.x!=desktop.size.x:
		push_error("Maximize failed");quit(1);return
	desktop._toggle_maximize("Calculator")
	if not calculator_window.get_rect().is_equal_approx(before_maximize):
		push_error("Restore did not recover the original window rectangle");quit(1);return
	for expected in ["Downloads/notes.txt","Downloads/notes_2.txt"]:
		computers.last_request.erase(1)
		desktop._browser_save_download("notes.txt","downloaded".to_utf8_buffer())
		if computers.local_snapshot.get("download_path")!=expected or computers.local_snapshot.files.get(expected,{}).get("text")!="downloaded":
			push_error("Virtual download did not create "+expected);quit(1);return
	computers.last_request.erase(1)
	var pdf: PackedByteArray="%PDF-1.7\nfixture".to_ascii_buffer()
	desktop._browser_save_download("manual.pdf",pdf)
	if computers.local_snapshot.binary_files.get("Downloads/manual.pdf")!=pdf.size() or computers.stations[id].power.drive.entries["Downloads/manual.pdf"].data!=pdf:
		push_error("Binary download did not reach the virtual drive");quit(1);return
	if not await verify_sampler(desktop,computers):quit(1);return
	var fixture_url:=OS.get_environment("LABVOLT_BROWSER_FIXTURE_URL")
	if not fixture_url.is_empty() and not await verify_website_download(desktop,computers,id,fixture_url):
		quit(1)
		return
	computers.last_request.erase(1)
	desktop._switch_app("Files")
	desktop._navigate_folder("")
	if not desktop.folder_button.visible or not desktop.delete_button.visible:
		push_error("Public file controls missing");quit(1);return
	desktop.folder_button.pressed.emit()
	accept_dialog(desktop,"Labs")
	if "Labs" not in computers.local_snapshot.get("folders",[]):push_error("Folder creation failed");quit(1);return
	computers.last_request.erase(1)
	assert(select_file(desktop.file_list, "Labs"))
	desktop._open_selected()
	find_button(desktop,"New file").pressed.emit()
	accept_dialog(desktop,"note.txt")
	await process_frame
	await process_frame
	desktop.editor.text="temporary"
	desktop.editor.text_changed.emit()
	await create_timer(.75).timeout
	if not computers.local_snapshot.files.has("Labs/note.txt"):push_error("Autosave failed");quit(1);return
	desktop._switch_app("Files")
	computers.last_request.erase(1)
	desktop._folder_up()
	assert(select_file(desktop.file_list, "Labs"))
	find_button(desktop,"Rename").pressed.emit()
	accept_dialog(desktop,"Work")
	if not computers.local_snapshot.files.has("Work/note.txt") or "Work" not in computers.local_snapshot.folders:
		push_error("Folder rename lost its contents");quit(1);return
	desktop._switch_app("Calculator")
	desktop.app_window.position=Vector2(585,110)
	desktop.app_window.size=Vector2(360,480)
	desktop.windows.Calculator.rect=Rect2(desktop.app_window.position,desktop.app_window.size)
	var saved_rect: Rect2=desktop.windows.Calculator.rect
	if args.size()>1 and args[1]=="capture":
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/campus-os-windows.png")
	desktop._switch_app("Text editor")
	desktop._new_file()
	desktop.editor.text="Unsaved draft"
	desktop.editor.text_changed.emit()
	var computer_chair: Node3D=game.player.seated
	desktop._request_exit()
	assert(not root.disable_3d, "Leaving Campus OS should restore the world view")
	if not is_instance_valid(computer_chair) or game.player.seated!=computer_chair or computer_chair.occupant!=1:
		push_error("Exiting Campus OS released the chair");quit(1);return
	if computers.sessions.has(1):push_error("Exit did not release the session");quit(1);return
	computers.request({"op":"enter","station":id})
	if desktop.windows.Calculator.rect!=saved_rect or desktop.windows.Calculator.shell!=calculator_window:
		push_error("Re-entry failed to restore application windows");quit(1);return
	if desktop.active_app!="Text editor" or desktop.editor.text!="Unsaved draft":
		push_error("A parked desktop lost its unnamed draft");quit(1);return
	desktop._switch_app("Files")
	computers.last_request.erase(1)
	desktop._move_entry({"campus_virtual_path":"Downloads/manual.pdf"},"Work")
	if computers.local_snapshot.binary_files.has("Downloads/manual.pdf") or computers.local_snapshot.binary_files.get("Work/manual.pdf")!=pdf.size():
		push_error("A binary drag move did not preserve its contents");quit(1);return
	if not computers.local_snapshot.get("files",{}).has("Work/note.txt"):
		push_error("Powered computer lost files after leaving");quit(1);return
	computers.last_request.erase(1)
	assert(select_file(desktop.file_list, "Work"))
	desktop.delete_button.pressed.emit()
	accept_dialog(desktop)
	if computers.local_snapshot.files.has("Work/note.txt") or "Work" in computers.local_snapshot.folders:
		push_error("Folder deletion left contents behind");quit(1);return
	var recycled: Array=computers.local_snapshot.get("recycle",[])
	assert(recycled.size()==1)
	computers.last_request.erase(1)
	desktop._send({"op":"untrash","item":recycled[0].id})
	assert(computers.local_snapshot.files["Work/note.txt"].text=="temporary")
	desktop._switch_app("Terminal")
	var terminal: Control=desktop.content.get_child(0)
	terminal._run("cat Work/note.txt")
	assert(terminal.transcript.get_parsed_text().contains("temporary"))
	assert("Circuit Lab" not in desktop.app_names and "Course work" not in desktop.app_names)
	desktop._switch_app("Circuit Lab")
	assert(not desktop.windows.has("Circuit Lab"))
	desktop._switch_app("Code editor")
	assert(desktop.windows.has("Text editor") and desktop.windows.has("Code editor"))
	computers.last_request.erase(1)
	computers.request({"op":"save","lease":computers.local_snapshot.lease,"revision":computers.local_snapshot.revision,"path":"discard.txt","text":"temporary","version":0})
	if not computers.local_snapshot.files.has("discard.txt"):push_error("Pre-shutdown save failed");quit(1);return
	computers.request({"op":"power","station":id})
	if computers.stations[id].power.powered or computers.sessions.has(1) or computers.public_workspaces.has(id):
		push_error("Power off failed to clear session");quit(1);return
	computers.request({"op":"power","station":id})
	var ready_at: int=computers.stations[id].ready_at
	while Time.get_ticks_msec()<ready_at:await process_frame
	game.player.global_position=point
	game.session.poses[1]={"position":point}
	computers.request({"op":"enter","station":id})
	if not computers.sessions.has(1):push_error("Restart did not reopen the workstation");quit(1);return
	if not computers.local_snapshot.files.is_empty() or not computers.local_snapshot.binary_files.is_empty() or not computers.local_snapshot.recycle.is_empty():
		push_error("Restart retained temporary workspace or Recycle Bin files");quit(1);return
	computers.stations[id].power.last_activity_ms=Time.get_ticks_msec()-computers.stations[id].power.IDLE_TIMEOUT_MS
	computers._prune()
	if computers.stations[id].power.powered or computers.sessions.has(1):
		push_error("Idle shutdown did not close the workstation");quit(1);return
	print("PUBLIC_WORKSTATION PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()


func verify_sampler(desktop: Control, computers: Node) -> bool:
	const Sample = "res://tests/campus/computers/campus-file-sampler.zip"
	var send:=func(action: Dictionary):
		computers.last_request.erase(1)
		desktop._send(action)
	var archive:=FileAccess.get_file_as_bytes(Sample)
	send.call({"op":"download","name":"campus-file-sampler.zip","bytes":archive})
	send.call({"op":"extract","path":"Downloads/campus-file-sampler.zip","new_path":"Downloads/Sampler"})
	var workspace: Dictionary=computers.local_snapshot
	if not "Downloads/Sampler/audio" in workspace.folders or not workspace.binary_files.has("Downloads/Sampler/models/tetrahedron.glb"):
		push_error("The file sampler did not extract to the workstation.")
		return false
	send.call({"op":"copy","path":"Downloads/Sampler","new_path":"Sample copy"})
	send.call({"op":"zip","path":"Sample copy","new_path":"Sample copy.zip"})
	if not computers.local_snapshot.binary_files.has("Sample copy.zip"):
		push_error("Folder copy or ZIP creation failed.")
		return false
	computers.last_request.erase(1)
	desktop._open_workspace_file("Downloads/Sampler/code/hello.py","Code editor")
	await process_frame
	await process_frame
	if desktop.active_app!="Code editor" or not desktop.editor.text.contains("def greet"):
		push_error("Extracted Python file did not open in Code editor.")
		return false
	if desktop.windows["Code editor"].saved_location.text!="Workspace/Downloads/Sampler/code/hello.py":
		push_error("Code editor did not show where the file is saved.")
		return false
	if OS.get_environment("LABVOLT_TEST_MONACO")=="1":
		var monaco: Variant=desktop.windows["Code editor"].get("monaco")
		if not is_instance_valid(monaco):push_error("Monaco was not created.");return false
		var limit:=Time.get_ticks_msec()+12000
		while not monaco.initialized and Time.get_ticks_msec()<limit:await process_frame
		if not monaco.initialized:push_error("Bundled Monaco did not initialize: "+str(monaco.browser.get_title()));return false
		monaco.browser.execute_javascript("monaco.editor.getModels().find(model=>model.uri.path.endsWith('/hello.py')).setValue('print(42)')")
		for attempt in 30:
			if desktop.editor.text=="print(42)":break
			await create_timer(.05).timeout
		if desktop.editor.text!="print(42)":push_error("Monaco edits did not reach the Campus workspace.");return false
	desktop._reveal_current_file()
	if desktop.folder_path!="Downloads/Sampler/code" or desktop._selected_entry().get("path")!="Downloads/Sampler/code/hello.py":
		push_error("Show in Files did not locate the source file.")
		return false
	var downloads:=find_button(desktop.breadcrumbs,"Downloads")
	if downloads==null:
		push_error("The parent folder was missing from the path bar.")
		return false
	downloads.pressed.emit()
	if desktop.folder_path!="Downloads" or desktop._file_icon("sample.zip")==desktop._file_icon("picture.jpg"):
		push_error("File breadcrumbs or archive icon did not work.")
		return false
	if OS.get_environment("LABVOLT_TEST_PDF")=="1":
		computers.last_request.erase(1)
		desktop._open_workspace_file("Downloads/Sampler/notes/preview.pdf")
		var viewer: Control=desktop.file_viewer
		if not is_instance_valid(viewer) or not is_instance_valid(viewer.browser):
			push_error("The PDF did not open in its document viewer.")
			return false
		var pdf_view: TextureRect=viewer.body.find_children("*","TextureRect",true,false)[0]
		var rendered:=false
		for attempt in 24:
			await create_timer(.25).timeout
			if pdf_view.texture==null:continue
			var frame:=pdf_view.texture.get_image()
			if frame==null or frame.is_empty():continue
			var pixel:=frame.get_pixel(frame.get_width()/2,frame.get_height()/2)
			if pixel.r>.85 and pixel.g>.85 and pixel.b>.85:
				rendered=true
				break
		if not rendered:
			push_error("The PDF viewer did not render the document page.")
			return false
		desktop._close_window("viewer:Downloads/Sampler/notes/preview.pdf")
		await process_frame
	computers.last_request.erase(1)
	desktop._open_workspace_file("Downloads/Sampler/audio/tone.wav")
	if not is_instance_valid(desktop.file_viewer) or desktop.file_viewer.audio==null:
		push_error("WAV file did not open in the audio viewer.")
		return false
	computers.last_request.erase(1)
	desktop._open_workspace_file("Downloads/Sampler/models/tetrahedron.glb")
	if not is_instance_valid(desktop.file_viewer) or desktop.file_viewer.model_camera==null:
		push_error("GLB file did not open in the model viewer.")
		return false
	computers.last_request.erase(1)
	desktop._open_workspace_file("Downloads/Sampler/models/tetrahedron.gltf")
	if not is_instance_valid(desktop.file_viewer) or desktop.file_viewer.model_camera==null:
		push_error("Text-encoded glTF did not open in the model viewer.")
		return false
	if not desktop.windows.has("viewer:Downloads/Sampler/audio/tone.wav"):push_error("Opening a second viewer closed the audio window.");return false
	desktop._close_window("viewer:Downloads/Sampler/models/tetrahedron.glb")
	desktop._close_window("viewer:Downloads/Sampler/models/tetrahedron.gltf")
	desktop._close_window("viewer:Downloads/Sampler/audio/tone.wav")
	await process_frame
	computers.last_request.erase(1)
	send.call({"op":"save","path":"Sample.json","text":"{\"hello\":\"world\"}","version":0})
	computers.last_request.erase(1)
	desktop._run_workspace_script("Sample.json")
	await process_frame
	await process_frame
	var terminal: Variant=desktop.windows.get("Terminal",{}).get("terminal")
	if not is_instance_valid(terminal) or terminal.lines.back()!="Valid JSON":
		push_error("Terminal did not route JSON through the execution manager.")
		return false
	return true

func verify_website_download(desktop: Control,computers: Node,id: String,url: String) -> bool:
	desktop._switch_app("Browser")
	var browser_surface: Control=desktop.browser_surface
	if not browser_surface.renderer_available() or not browser_surface.tabs[0].native_download:
		push_error("Native Chromium downloads are unavailable in the workstation")
		return false
	var browser: Variant=browser_surface.tabs[0].browser
	browser_surface.address.text=url+"/website-download"
	browser_surface._navigate()
	var deadline:=Time.get_ticks_msec()+15000
	while str(browser.get_title())!="WEBSITE_DOWNLOAD" and Time.get_ticks_msec()<deadline:
		await process_frame
	if str(browser.get_title())!="WEBSITE_DOWNLOAD":
		push_error("The website's download form did not load")
		return false
	var render: SubViewport=desktop.game.computer_room_adapter.desktop_render
	var initial_pixels: Vector2=browser_surface.tabs[0].surface.get_meta("cef_pixels",Vector2.ZERO)
	desktop._request_exit()
	await process_frame
	render.set_meta("parked_preview",true)
	render.size=Vector2i(384,216)
	browser_surface._resize_tabs()
	if browser_surface.tabs[0].surface.get_meta("cef_pixels",Vector2.ZERO)!=initial_pixels:
		push_error("Parked preview resized the active browser")
		return false
	computers.request({"op":"enter","station":id})
	await process_frame
	if not is_same(desktop.browser_surface,browser_surface) or not is_same(browser_surface.tabs[0].browser,browser) or browser.get_title()!="WEBSITE_DOWNLOAD":
		push_error("Reopening the workstation restarted its browser")
		return false
	await create_timer(.3).timeout
	var photo_digest:="1c3b8a632083272ce5a3de701dda84f2615243fef8cadc818c6626c0780b7978"
	for sample in [
		[40,"website-report.pdf","be9d993e8ebf1a158774e6581d3aea58a270daed0a5aed878993612c79b8a82e"],
		[95,"website-photo.png",photo_digest],
	]:
		click_web_button(browser_surface,browser,Vector2(65,sample[0]))
		deadline=Time.get_ticks_msec()+12000
		while not is_instance_valid(browser_surface.download_dialog) and Time.get_ticks_msec()<deadline:
			await process_frame
		var path: String="Downloads/"+sample[1]
		if not is_instance_valid(browser_surface.download_dialog) or computers.local_snapshot.binary_files.has(path):
			push_error("No save confirmation for %s: %s"%[path,browser_surface.status.text])
			return false
		computers.last_request.erase(1)
		browser_surface.download_dialog.confirmed.emit()
		if not check_download(computers.stations[id].power.drive,path,sample[2]):return false
		await process_frame
	click_web_button(browser_surface,browser,Vector2(65,150))
	deadline=Time.get_ticks_msec()+12000
	while not browser_surface.status.text.contains("exceeds") and Time.get_ticks_msec()<deadline:
		await process_frame
	if not browser_surface.status.text.contains("exceeds") or is_instance_valid(browser_surface.download_dialog):
		push_error("Native Chromium accepted a file above its limit")
		return false
	computers.last_request.erase(1)
	browser_surface.address.text=url+"/direct-photo.png"
	browser_surface._download_address()
	deadline=Time.get_ticks_msec()+12000
	while not is_instance_valid(browser_surface.download_dialog) and Time.get_ticks_msec()<deadline:
		await process_frame
	if not is_instance_valid(browser_surface.download_dialog):
		push_error("Direct download did not show a save confirmation: "+browser_surface.status.text)
		return false
	browser_surface.download_dialog.confirmed.emit()
	if not check_download(computers.stations[id].power.drive,"Downloads/direct-photo.png",photo_digest):return false
	desktop._close_window("Browser")
	print("WORKSTATION_NATIVE_DOWNLOAD PASS")
	return true

func check_download(drive: RefCounted,path: String,expected_digest: String) -> bool:
	var data: PackedByteArray=drive.entries.get(path,{}).get("data",PackedByteArray())
	if data.is_empty():
		push_error("The virtual drive has no data for "+path)
		return false
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	if data.size()>1024*1024 and hash.finish().hex_encode()==expected_digest:return true
	push_error("The virtual drive did not receive the expected large file: "+path)
	return false

func click_web_button(browser_surface: Control,browser: Variant,position: Vector2) -> void:
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new()
		click.position=position/browser_surface._desktop_pixel_scale()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=pressed
		browser_surface._forward(browser,browser_surface.tabs[0].surface,click)

func select_file(list: Tree, path: String) -> bool:
	for row in list.get_root().get_children():
		var data: Variant = row.get_metadata(0)
		if data is Dictionary and data.path == path:
			row.select(0)
			return true
	return false
