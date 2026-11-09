extends SceneTree
var game: Node
var failures := 0
var checks := 0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL MENU: "+text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await create_timer(.3).timeout
	check(game.front.page=="home" and not game.front.in_game,"opens on title screen")
	check(not game.ui.menu.visible,"old lobby hidden")
	game.front.escape()
	check(not game.player.enabled,"escape cannot bypass title screen")
	game.front.network_page(false)
	check(game.front.page=="host","host screen")
	game.front.network_page(true)
	check(game.front.page=="join","join screen")
	game.capture()
	check(game.front.in_game and not game.front.screen.visible,"enter game hides title")
	game.front.escape()
	check(game.front.page=="pause" and not game.player.enabled,"escape opens pause menu")
	game.front.settings_page()
	check(game.front.settings_host.visible,"settings available in game")
	game.front.leave_game()
	check(not game.front.in_game and game.front.page=="home","leave returns to title")
	game.front.joining=true
	game.session.roster_changed.emit()
	check(not game.front.in_game,"failed join does not enter offline game")
	game.front.home()
	check(not game.front.joining,"back cancels pending join")
	var directory := "user://characters/integration_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var config := FileAccess.open(directory.path_join("character.json"),FileAccess.WRITE)
	config.store_string(JSON.stringify({"name":"Saved tester","skin":{"color":"#ba8f75"}}))
	config.close()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/default_avatar.glb"),ProjectSettings.globalize_path(directory.path_join("avatar.glb")))
	game.characters.refresh()
	game.characters.select_profile("integration_test")
	check(game.characters.selected=="integration_test","profile selected")
	game.characters.duplicate_selected()
	check(game.characters.profiles.size()==2,"second profile created by duplication")
	var selected: String=game.characters.selected
	var second=preload("res://scripts/character_library.gd").new()
	root.add_child(second)
	check(second.selected==selected and second.profiles.size()==2,"selection and profiles persist across library reload")
	second.queue_free()
	game.front.characters_page()
	await create_timer(.3).timeout
	check(game.front.preview_model!=null,"selected profile renders in menu")
	var bytes: PackedByteArray=game.characters.avatar_bytes()
	check(preload("res://scripts/avatar_model.gd").valid(bytes),"exported avatar accepted")
	check(not preload("res://scripts/avatar_model.gd").valid(PackedByteArray([1,2,3])),"malformed avatar rejected")
	game._receive_pose(42,{"position":Vector3(0,0,0),"yaw":0,"pitch":0,"crouch":false})
	check(game.avatars[42].has_node("CharacterModel"),"remote uses humanoid model")
	print("MENUS / PROFILES: %d checks, %d failures"%[checks,failures])
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
