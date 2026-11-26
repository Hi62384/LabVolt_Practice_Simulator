extends SceneTree

const Apps=preload("res://scripts/campus/computers/application_registry.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const FIXTURES:="res://CampusOS-Test-Files/applications/"
const CLICK:="Campus Click Test.exe"
const GAME:="Campus Hardware Game.exe"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(120).timeout.connect(func():quit(1))
	var image:=FileAccess.get_file_as_bytes(FIXTURES+CLICK)
	for extension in ["msi","msix"]:
		var package:=FileAccess.get_file_as_bytes(FIXTURES+"Campus Click Package."+extension)
		var extracted:=Apps.windows_image(extension,package)
		assert(not extracted.has("error"),extension+": "+str(extracted.get("error","")))
		assert(extracted.image==image)
		var drive:=Drive.new(8*1024*1024)
		var path:="bad."+str(extension)
		var invalid:=package.slice(0,64)
		assert(drive.write_file(path,invalid))
		assert(not Apps.apply(drive,{"op":"install_app","path":path,"sha256":Apps.sha256(invalid)}).is_empty())
		assert(drive.entries.size()==1 and Apps.installed(drive).is_empty())

	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	_press(game.front.body,"Singleplayer")
	await process_frame
	_press(game.front.body,"Play")
	await process_frame
	var computers: Node=game.computers
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
		assert(not app.is_empty(),str(desktop.status_label.text))
		assert(app.sha256==Apps.sha256(image) and app.desktop_shortcut)
		assert(computers.stations[id].power.drive.entries[app.archive].data==image)
		desktop._preview_path(app.archive)
		await create_timer(.12).timeout
		_confirm(desktop)
		assert(await _check_window(desktop))
		print("CAMPUS_NATIVE_"+extension.to_upper()+" PASS")

	assert(await _open_file(desktop,GAME,FileAccess.get_file_as_bytes(FIXTURES+GAME),"Run…"))
	assert(await _check_window(desktop,true))
	print("CAMPUS_NATIVE_HARDWARE_GAME PASS")
	game.queue_free()
	await process_frame
	quit()

func _open_file(desktop: Control, filename: String, bytes: PackedByteArray, action: String) -> bool:
	var path:="Downloads/"+filename
	desktop._browser_save_download(filename,bytes)
	await create_timer(.15).timeout
	desktop._open_workspace_file(path)
	await process_frame
	assert(desktop.windows.has("viewer:"+path))
	_press(desktop.windows["viewer:"+path].viewer,action)
	await create_timer(.12).timeout
	_confirm(desktop)
	await create_timer(.15).timeout
	return true

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

func _confirm(desktop: Control) -> void:
	for child in desktop.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			child.confirmed.emit()
			return
	assert(false,"Missing Windows consent dialog")
