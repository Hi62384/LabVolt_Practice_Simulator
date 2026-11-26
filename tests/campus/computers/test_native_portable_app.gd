extends SceneTree

const Runtime=preload("res://scripts/campus/computers/native_windows_surface.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const Apps=preload("res://scripts/campus/computers/application_registry.gd")
const EXE:="Downloads/Campus Click Test.exe"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(90).timeout.connect(func():quit(1))
	var args:=OS.get_cmdline_user_args()
	assert(args.size()==2)
	var bytes:=FileAccess.get_file_as_bytes(args[0])
	var drive:=Drive.new(8*1024*1024)
	assert(drive.make_folder("Downloads") and drive.write_file(EXE,bytes))
	var setup:={"op":"install_app","path":EXE,"sha256":Apps.sha256(bytes),"folder":"campus-click",
		"shortcut":true,"desktop_shortcut":true}
	assert(Apps.apply(drive,setup).is_empty())
	var app: Dictionary=Apps.installed(drive).values()[0]
	assert(app.runtime=="windows" and app.archive=="Program Files/campus-click/Application.exe")
	assert(drive.entries[app.archive].data==bytes)
	var window:=Runtime.new()
	root.add_child(window)
	window.size=Vector2(680,440)
	assert(window.start(drive.entries[app.archive].data))
	var read:=await _wait_color(window,Color8(19,134,217))
	assert(read,"No frame from private desktop. "+window.client.Status())
	window.client.Forward(2,120,0,0)
	assert(await _wait_color(window,Color8(208,81,38)),"Keyboard input did not reach the app.")
	window.client.Stop()
	for tick in 50:
		if not window.client.Running():break
		await create_timer(.05).timeout
	assert(not window.client.Running())
	assert(Apps.apply(drive,{"op":"uninstall_app","app_id":app.id}).is_empty())
	assert(Apps.installed(drive).is_empty() and drive.entries.has(EXE))
	window.queue_free()
	await process_frame
	assert(await _workstation(bytes,FileAccess.get_file_as_bytes(args[1])))
	print("CAMPUS_NATIVE_PORTABLE_APP PASS")
	quit()

func _wait_color(window: Control, expected: Color) -> bool:
	for tick in 200:
		if window.native_texture!=null:
			var image: Image=window.native_texture.get_image()
			if image.get_pixel(16,16).is_equal_approx(expected):return true
		if not window.client.Running():return false
		await create_timer(.05).timeout
	return false


func _workstation(bytes: PackedByteArray, setup: PackedByteArray) -> bool:
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
	assert(desktop.visible and desktop._native_allowed(),"Desktop visible %s, available %s, power %s"%[desktop.visible,desktop._native_allowed(),computers.stations[id].power.powered])
	desktop._browser_save_download("Campus Click Test.exe",bytes)
	await create_timer(.15).timeout
	desktop._open_workspace_file(EXE)
	await process_frame
	assert(desktop.windows.has("viewer:"+EXE))
	_press(desktop.windows["viewer:"+EXE].viewer,"Install portable copy…")
	await create_timer(.12).timeout
	_confirm(desktop)
	await create_timer(.15).timeout
	var installed: Dictionary=desktop.snapshot.get("installed_apps",{})
	assert(installed.size()==1,"Portable installation missing: "+str(desktop.status_label.text))
	var app: Dictionary=installed.values()[0]
	assert(app.runtime=="windows" and app.desktop_shortcut)
	_press(desktop.installed_shortcuts,app.name)
	await process_frame
	await create_timer(.12).timeout
	_confirm(desktop)
	assert(desktop.windows.has("native:windows"))
	var running: Control=desktop.windows["native:windows"].native_surface
	assert(await _wait_color(running,Color8(19,134,217)))
	var running_client: RefCounted=running.client
	desktop._close_window("native:windows")
	assert(not desktop.windows.has("native:windows"))
	for tick in 50:
		if not running_client.Running():break
		await create_timer(.05).timeout
	assert(not running_client.Running())
	desktop._browser_save_download("Campus Click Setup.exe",setup)
	await create_timer(.15).timeout
	const setup_path:="Downloads/Campus Click Setup.exe"
	desktop._open_workspace_file(setup_path)
	await process_frame
	_press(desktop.windows["viewer:"+setup_path].viewer,"Run setup…")
	await create_timer(.12).timeout
	_confirm(desktop)
	assert(desktop.windows.has("native:windows"))
	var installer: Control=desktop.windows["native:windows"].native_surface
	assert(await _wait_color(installer,Color8(75,113,61)))
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.position=installer.picture.size*.5
	installer._guest_input(click)
	for tick in 200:
		if not installer.client.Running():break
		await create_timer(.05).timeout
	assert(not installer.client.Running(), "Setup did not exit after its Install action")
	await process_frame
	_press(installer,"Import Installed Click.exe to Downloads")
	await create_timer(.15).timeout
	var device=computers.stations[id].power
	assert(device.drive.entries["Downloads/Installed Click.exe"].data==bytes)
	print("CAMPUS_NATIVE_INSTALLER_OUTPUT PASS")
	game.queue_free()
	await process_frame
	return true

func _press(node: Node, text: String) -> void:
	for child in node.find_children("*","Button",true,false):
		if child.text==text and child.is_visible_in_tree():
			child.pressed.emit()
			return
	assert(false,"Missing button "+text)

func _confirm(desktop: Control) -> void:
	for child in desktop.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			child.confirmed.emit()
			return
	assert(false,"Missing local Windows consent dialog")
