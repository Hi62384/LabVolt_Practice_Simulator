extends SceneTree

const Apps=preload("res://scripts/campus/computers/application_registry.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const FIXTURES:="res://CampusOS-Test-Files/applications/"
const GAME:="Campus Hardware Game.exe"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(120).timeout.connect(func():quit(1))
	for extension in ["msi","msix"]:
		var package:=FileAccess.get_file_as_bytes(FIXTURES+"Campus Click Package."+extension)
		var extracted:=Apps.windows_image(extension,package)
		assert(not extracted.has("error"),extension+": "+str(extracted.get("error","")))
		assert(extracted.file_count>=3 and extracted.entry=="Click.exe")
		var drive:=Drive.new(8*1024*1024)
		var source:="fixture."+str(extension)
		assert(drive.write_file(source,package))
		var installation:=Apps.apply(drive,{"op":"install_app","path":source,"sha256":Apps.sha256(package)})
		assert(installation.is_empty(),installation)
		assert(drive.remove(source))
		var app_id: String=Apps.installed(drive).keys()[0]
		assert(Apps.apply(drive,{"op":"uninstall_app","app_id":app_id}).is_empty())
		var path:="bad."+str(extension)
		var invalid:=package.slice(0,64)
		assert(drive.write_file(path,invalid))
		assert(not Apps.apply(drive,{"op":"install_app","path":path,"sha256":Apps.sha256(invalid)}).is_empty())
		assert(not drive.entries.has(Apps.ROOT+"/bad") and Apps.installed(drive).is_empty())

	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	_press(game.front.body,"Singleplayer")
	await process_frame
	_press(game.front.body,"Play")
	await process_frame
	var computers: Node=game.computers
	computers.operation_failed.connect(func(message: String):print("Computer operation failed: "+message))
	var id:="m203_r3_c4"
	var position: Vector3=computers.stations[id].anchor
	game.player.global_position=position
	game.session.poses[1]={"position":position}
	await physics_frame
	computers.request({"op":"power","station":id})
	await create_timer(1.7).timeout
	computers.request({"op":"enter","station":id})
	await process_frame
	var desktop: Control=game.computer_room_adapter.desktop
	assert(desktop.visible and desktop._native_allowed())

	for extension in ["msi","msix"]:
		var filename:="Campus Click Package."+str(extension)
		var bytes:=FileAccess.get_file_as_bytes(FIXTURES+filename)
		assert(await _open_file(desktop,filename,bytes,"Install into Campus OS…"))
		var installed: Dictionary=desktop.snapshot.get("installed_apps",{})
		var app: Dictionary=installed.get("windows."+Apps.sha256(bytes).left(32),{})
		assert(not app.is_empty(),"%s: %s. Installed %s. Drive %s"%[extension,desktop.status_label.text,installed.keys(),computers.stations[id].power.drive.entries.keys()])
		assert(app.archive.ends_with("/"+Apps.NATIVE_BUNDLE) and app.desktop_shortcut)
		assert(Apps.sha256(computers.stations[id].power.drive.entries[app.archive].data)==app.sha256)
		await _request_gap(desktop)
		desktop._preview_path(app.archive)
		await create_timer(.12).timeout
		_confirm(desktop)
		assert(await _check_window(desktop))
		print("CAMPUS_NATIVE_"+extension.to_upper()+" PASS")

	assert(await _open_file(desktop,GAME,FileAccess.get_file_as_bytes(FIXTURES+GAME),"Run…"))
	assert(await _check_window(desktop,true))
	print("CAMPUS_NATIVE_HARDWARE_GAME PASS")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		assert(await _check_mines(desktop,FileAccess.get_file_as_bytes(args[0])))
		print("CAMPUS_UPSTREAM_MINES PASS")
	game.queue_free()
	await process_frame
	quit()

func _open_file(desktop: Control, filename: String, bytes: PackedByteArray, action: String, executable := "") -> bool:
	var path:="Downloads/"+filename
	await _request_gap(desktop)
	desktop._browser_save_download(filename,bytes)
	await _request_gap(desktop)
	desktop._open_workspace_file(path)
	await process_frame
	assert(desktop.windows.has("viewer:"+path))
	_press(desktop.windows["viewer:"+path].viewer,action)
	await _request_gap(desktop)
	_confirm(desktop,executable)
	await _request_gap(desktop)
	await process_frame
	return true

func _request_gap(desktop: Control) -> void:
	var last: Dictionary=desktop.game.computers.last_request
	while Time.get_ticks_msec()-int(last.get(1,0))<100:
		await process_frame

func _check_window(desktop: Control,verify_mouse := false) -> bool:
	assert(desktop.windows.has("native:windows"))
	var window: Control=desktop.windows["native:windows"].native_surface
	assert(await _wait_color(window,Color8(19,134,217)),window.client.Status())
	window.client.Forward(2,120,0,0)
	assert(await _wait_color(window,Color8(208,81,38)),"Keyboard input did not update the game.")
	if verify_mouse:
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		click.position=window.picture.size*.5
		window._guest_input(click)
		assert(await _wait_color(window,Color8(19,134,217)),"Mouse input did not update the game.")
	var client: RefCounted=window.client
	desktop._close_window("native:windows")
	for tick in 50:
		if not client.Running():return true
		await create_timer(.05).timeout
	return false

func _check_mines(desktop: Control, package: PackedByteArray) -> bool:
	var parsed:=Apps.windows_image("msi",package)
	assert(not parsed.has("error"),str(parsed.get("error","")))
	assert(parsed.file_count>20)
	var entry:=""
	for path: String in parsed.entries:
		if path.get_file()=="mines.exe":entry=path
	assert(not entry.is_empty())
	assert(await _open_file(desktop,"puzzles-installer.msi",package,"Install into Campus OS…",entry))
	var app: Dictionary=desktop.snapshot.get("installed_apps",{}).get("windows."+Apps.sha256(package).left(32),{})
	assert(app.get("entry")==entry,str(desktop.status_label.text))
	await _request_gap(desktop)
	desktop._preview_path(app.archive)
	await create_timer(.12).timeout
	_confirm(desktop)
	assert(desktop.windows.has("native:windows"))
	var window: Control=desktop.windows["native:windows"].native_surface
	for frame in 250:
		if window.native_texture!=null:break
		if not window.client.Running():break
		await create_timer(.05).timeout
	assert(window.native_texture!=null,window.client.Status())
	var before: Image=window.native_texture.get_image()
	var region:=Rect2i(before.get_size()/4,before.get_size()/2)
	var board:=before.get_region(region).get_data()
	var nonuniform:=false
	var first:=before.get_pixelv(region.position)
	for x in range(region.position.x,region.end.x):
		if before.get_pixel(x,region.position.y)!=first:nonuniform=true;break
	assert(nonuniform,"Mines did not render its board.")
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.position=window.picture.size*.5
	window._guest_input(click)
	click.pressed=false
	window._guest_input(click)
	for frame in 100:
		await create_timer(.05).timeout
		var after: Image=window.native_texture.get_image()
		if after.get_size()!=before.get_size() or after.get_region(region).get_data()==board:continue
		var capture:=OS.get_environment("LABVOLT_MINES_CAPTURE")
		if not capture.is_empty():assert(after.save_png(capture)==OK)
		desktop._close_window("native:windows")
		return true
	return false

func _wait_color(window: Control, expected: Color) -> bool:
	for tick in 200:
		if window.native_texture!=null:
			var image: Image=window.native_texture.get_image()
			if image.get_pixel(16,16).is_equal_approx(expected):return true
		if not window.client.Running():return false
		await create_timer(.05).timeout
	return false

func _press(node: Node, label: String) -> void:
	for child in node.find_children("*","Button",true,false):
		if child.text==label and child.is_visible_in_tree():
			child.pressed.emit()
			return
	assert(false,"Missing button "+label)

func _confirm(desktop: Control, executable := "") -> void:
	for child in desktop.get_children():
		if child is ConfirmationDialog and child.visible and not child.is_queued_for_deletion():
			if not executable.is_empty():
				var selector: OptionButton=child.find_children("*","OptionButton",true,false)[0]
				for index in selector.item_count:
					if selector.get_item_text(index)==executable:selector.select(index);break
				assert(selector.get_item_text(selector.selected)==executable)
			child.get_ok_button().pressed.emit()
			return
	assert(false,"Missing Windows consent dialog")
