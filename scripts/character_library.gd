extends Node
signal changed
var profiles: Array = []
var selected := ""
var editing := ""
# Optional in-memory fixture seams. Empty callables retain production storage.
var selection_profile_factory: Callable
var selection_legacy_loader: Callable
var selection_config_writer: Callable
var last_selection_result := {}
const ROOT := "user://characters"
const COSMETIC_MESH_REVISION := 3

func _profile_path(id: String) -> String:
	return "user://electronics_%s.json" % id.sha256_text().left(24)

func _appearance_key(appearance: Dictionary) -> String:
	return JSON.stringify(appearance).sha256_text()

func notify_appearance_saved(profile: RefCounted) -> void:
	if not selected.is_empty() and profile.path == _profile_path(selected):
		changed.emit()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var cfg := ConfigFile.new()
	cfg.load("user://character_selection.cfg")
	selected=str(cfg.get_value("character","selected",""))
	refresh()
func refresh() -> void:
	profiles.clear()
	for folder in DirAccess.get_directories_at(ROOT):
		var path := ROOT.path_join(folder)
		if not FileAccess.file_exists(path.path_join("character.json")) or not FileAccess.file_exists(path.path_join("avatar.glb")):
			continue
		var data=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("character.json")))
		if data is Dictionary:
			profiles.append({"id":folder,"name":str(data.get("name","Character")),"path":path})
	if not profiles.any(func(p): return p.id==selected):
		selected=""
	changed.emit()
func select_profile(id: String) -> void:
	last_selection_result={"ok":false,"selected":selected,"target_profile_saved":false}
	if not preload("res://scripts/avatar_cosmetics/persistence/character_reconciliation.gd")._valid_id(id):return
	var game := get_parent()
	if is_instance_valid(game) and is_instance_valid(game.get("front")) and game.front.in_game:return
	var target = selection_profile_factory.call() if selection_profile_factory.is_valid() else preload("res://scripts/electronics_profile.gd").new()
	if target==null or not target.has_method("open") or not target.has_method("save"):return
	target.open(id)
	var cosmetics = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not cosmetics.load_catalog():return
	var adapter = cosmetics.authoritative_adapter(func():return true)
	var reconcile = preload("res://scripts/avatar_cosmetics/persistence/character_reconciliation.gd").new(adapter)
	reconcile.is_authority=func():return true
	var legacy = selection_legacy_loader.call(id) if selection_legacy_loader.is_valid() else JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join(id).path_join("character.json")))
	var hydrated: Dictionary=reconcile.hydrate(id,target.data,legacy if legacy is Dictionary else {})
	if not hydrated.get("ok",false):return
	target.data=hydrated.profile
	if target.save()!=OK:return
	last_selection_result.target_profile_saved=true
	var cfg := ConfigFile.new()
	cfg.load("user://character_selection.cfg")
	cfg.set_value("character","selected",id)
	var selection_error: int=int(selection_config_writer.call(id)) if selection_config_writer.is_valid() else cfg.save("user://character_selection.cfg")
	if selection_error!=OK:
		last_selection_result.error="Selection save failed; previous character remains selected. Target profile preparation was saved."
		return
	selected=id
	last_selection_result={"ok":true,"selected":selected,"target_profile_saved":true}
	changed.emit()
func avatar_bytes() -> PackedByteArray:
	var path := ROOT.path_join(selected).path_join("avatar.glb") if selected!="" else "res://assets/default_avatar.glb"
	if not selected.is_empty():
		_refresh_cosmetic_mesh(selected)
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _refresh_cosmetic_mesh(id: String) -> void:
	var settings := ROOT.path_join(id).path_join("character.json")
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings))
	if not legacy is Dictionary:
		return
	var profile_path := _profile_path(id)
	if not FileAccess.file_exists(profile_path):
		return
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if not profile is Dictionary or not profile.has("avatar_cosmetics"):
		return
	var cosmetics := preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not cosmetics.load_catalog():
		return
	var config: Dictionary = legacy.duplicate(true)
	config.erase("cosmetic_mesh_revision")
	config.erase("cosmetic_mesh_appearance")
	var look := cosmetics.begin_preview(profile, config)
	if look.errors.is_empty():
		if int(legacy.get("cosmetic_mesh_revision", 0)) == COSMETIC_MESH_REVISION and legacy.get("cosmetic_mesh_appearance", "") == _appearance_key(look.state):
			return
		var error := save_character(id, config, look.state, cosmetics.catalog)
		if not error.is_empty():
			push_warning("Character appearance saved, but the avatar model could not be refreshed: " + error)
var editor_layer: CanvasLayer
var editor_studio: Control
var editor_from_game := false
func is_editing() -> bool:
	return is_instance_valid(editor_layer)
func edit(create_new: bool, from_game := false) -> String:
	if is_editing():return "Character editor is open."
	if selected.is_empty() and not create_new:return "Select a saved character to edit."
	editing = Crypto.new().generate_random_bytes(16).hex_encode() if create_new else selected
	if create_new and DirAccess.dir_exists_absolute(ROOT.path_join(editing)):return "Could not allocate a new character ID."
	var config: Dictionary=preload("res://scripts/toon_character.gd").preset(0)
	if not create_new and selected!="":
		var saved=JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join(selected).path_join("character.json")))
		if saved is Dictionary:config=preload("res://scripts/toon_character.gd").sanitize(saved)
	editor_layer=CanvasLayer.new();editor_layer.layer=100;add_child(editor_layer)
	var game := get_parent()
	if not is_instance_valid(game.electronics):editor_layer.free();editor_layer=null;return "Character profile is unavailable."
	editor_studio=preload("res://scripts/avatar_cosmetics/core/editor_host.gd").new()
	editor_layer.add_child(editor_studio)
	editor_studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var opened: Dictionary=editor_studio.open_profile({} if create_new else game.electronics.profile.data,config)
	if not opened.get("ok",false):editor_layer.free();editor_layer=null;editor_studio=null;return "Cosmetic editor could not open."
	editor_from_game=from_game
	if editor_from_game:game.release_mouse()
	else:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if create_new:editor_studio.panel.enable_creation()
	editor_studio.closed.connect(func():_editor_closed(false))
	var pending_apply := {"id": "", "draft": {}}
	var target_id := editing
	editor_studio.transaction_requested.connect(func(op: String,args: Array):
		if create_new:
			_create_from_studio(args[0], config)
			return
		var profile = game.electronics.profile
		if selected != target_id or profile.path != _profile_path(target_id):
			editor_studio.acknowledge_apply(false,"The selected character changed. Reopen the wardrobe.")
			return
		if game.session.online:
			if not str(pending_apply.id).is_empty():
				return
			var network = game.electronics_trade.authority
			if not profile.authority_submit.is_valid() or network.pending.size() >= 64:
				editor_studio.acknowledge_apply(false,"Inventory is busy. Try Apply again.")
				return
			pending_apply.id = Crypto.new().generate_random_bytes(16).hex_encode()
			pending_apply.draft = editor_studio.panel.draft.duplicate(true)
			network.submit(op,args,pending_apply.id)
		else:
			var adapter = editor_studio.coordinator.authoritative_adapter(func():return true)
			var result: Dictionary=adapter.commit_local(profile,args[0],config)
			if result.get("ok",false):
				notify_appearance_saved(profile)
			editor_studio.acknowledge_apply(result.get("ok",false),str(result.get("error","Appearance saved"))))
	var authority = game.electronics_trade.authority
	if is_instance_valid(authority):
		var callback := func(op: String,result: Dictionary):
			if op=="avatar_cosmetic" and not str(pending_apply.id).is_empty() and result.get("request_id","")==pending_apply.id and is_instance_valid(editor_studio):
				pending_apply.id=""
				editor_studio.acknowledge_apply(result.get("ok",false),str(result.get("error","Appearance saved")),pending_apply.draft)
		authority.operation_result.connect(callback)
		editor_studio.tree_exiting.connect(func():
			if is_instance_valid(authority) and authority.operation_result.is_connected(callback):authority.operation_result.disconnect(callback))
	return ""
func _create_from_studio(intent: Dictionary, config: Dictionary) -> void:
	var profile := preload("res://scripts/electronics_profile.gd").new()
	profile.open(editing)
	var studio = editor_studio
	var adapter = studio.coordinator.authoritative_adapter(func():return true)
	var result: Dictionary
	if intent.changes.is_empty():
		profile.data = adapter.migrate(profile.data, config)
		result = {"ok": profile.save() == OK, "error": "Could not save the new profile."}
	else:
		result = adapter.commit_local(profile, intent, config)
	if not result.ok:
		studio.acknowledge_apply(false, result.error)
		return
	var appearance: Dictionary = adapter.equipment(profile.data)
	appearance.legacy_character = config
	var error := save_character(editing, config, appearance, studio.coordinator.catalog)
	if not error.is_empty():
		studio.acknowledge_apply(false, error)
		return
	_editor_closed(true)

func _editor_closed(saved: bool) -> void:
	editor_layer.queue_free();editor_layer=null;editor_studio=null
	refresh()
	if saved:select_profile(editing)
	if editor_from_game:
		editor_from_game=false
		get_parent().capture()
func save_character(id: String,config: Dictionary,appearance: Dictionary = {},catalog: Dictionary = {}) -> String:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):return "Invalid profile."
	var directory := ProjectSettings.globalize_path(ROOT.path_join(id))
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error!=OK:return "Could not open character folder: "+error_string(directory_error)
	var staging := "pending_"+Crypto.new().generate_random_bytes(8).hex_encode()
	var model_path := directory.path_join(staging+".glb")
	var error := preload("res://scripts/toon_character.gd").save_glb(config,model_path) if appearance.is_empty() else preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").save_glb(appearance,catalog,model_path)
	if error!=OK:return "Could not save model: "+error_string(error)
	var file := FileAccess.open(directory.path_join(staging+".json"),FileAccess.WRITE)
	if file==null:return "Could not save settings."
	var settings := config.duplicate(true)
	if not appearance.is_empty():
		settings["cosmetic_mesh_revision"] = COSMETIC_MESH_REVISION
		settings["cosmetic_mesh_appearance"] = _appearance_key(appearance)
	file.store_string(JSON.stringify(settings))
	var write_error := file.get_error()
	file.close()
	if write_error!=OK:return "Could not write character settings: "+error_string(write_error)
	# Stage both files, then preserve the previous pair until both replacements succeed.
	for name in ["avatar.glb","character.json"]:
		if FileAccess.file_exists(directory.path_join(name)):
			var backup_error := DirAccess.copy_absolute(directory.path_join(name),directory.path_join(name+".backup"))
			if backup_error!=OK:return "Could not back up the previous character."
	for pair in [[staging+".glb","avatar.glb"],[staging+".json","character.json"]]:
		error=DirAccess.rename_absolute(directory.path_join(pair[0]),directory.path_join(pair[1]))
		if error!=OK:
			for name in ["avatar.glb","character.json"]:
				if FileAccess.file_exists(directory.path_join(name+".backup")):DirAccess.copy_absolute(directory.path_join(name+".backup"),directory.path_join(name))
			return "Could not replace character; previous save retained."
	for name in ["avatar.glb.backup","character.json.backup"]:
		if FileAccess.file_exists(directory.path_join(name)):DirAccess.remove_absolute(directory.path_join(name))
	return ""
func duplicate_selected() -> void:
	if selected=="":
		return
	var id := str(Time.get_ticks_usec())+"_"+str(randi()%100000)
	var destination := ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	for file in ["character.json","avatar.glb"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(ROOT.path_join(selected).path_join(file)),ProjectSettings.globalize_path(destination.path_join(file)))
	var data=JSON.parse_string(FileAccess.get_file_as_string(destination.path_join("character.json")))
	data.name=str(data.name)+" copy"
	var out=FileAccess.open(destination.path_join("character.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(data))
	out.close()
	selected=id
	refresh()
	select_profile(id)

func delete_profile(id: String) -> String:
	if id.is_empty() or id != selected or not profiles.any(func(profile): return profile.id == id):
		return "Select a saved character to delete."
	var game := get_parent()
	if is_instance_valid(game) and is_instance_valid(game.get("front")) and game.front.in_game:
		return "Return to the main menu before deleting a character."
	var directory := ProjectSettings.globalize_path(ROOT.path_join(id))
	var cfg := ConfigFile.new()
	cfg.load("user://character_selection.cfg")
	cfg.set_value("character", "selected", "")
	if cfg.has_section_key("names", id):
		cfg.erase_section_key("names", id)
	var error := cfg.save("user://character_selection.cfg")
	if error != OK:
		return "Could not update character selection: " + error_string(error)
	selected = ""
	var folder := DirAccess.open(directory)
	if folder == null:
		refresh()
		return "Could not open the character folder."
	for file in folder.get_files():
		error = DirAccess.remove_absolute(directory.path_join(file))
		if error != OK:
			refresh()
			return "Could not delete every character file: " + error_string(error)
	error = DirAccess.remove_absolute(directory)
	refresh()
	if error != OK:
		return "Could not remove the character folder: " + error_string(error)
	var cosmetics := _profile_path(id)
	if FileAccess.file_exists(cosmetics):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cosmetics))
	return ""

func display_name() -> String:
	for profile in profiles:
		if profile.id == selected:
			return display_name_for(selected, profile.name)
	return display_name_for(selected, "Student")

func display_name_for(id: String, fallback: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://character_selection.cfg")
	return preload("res://scripts/campus/social/public_profiles.gd").clean_name(str(cfg.get_value("names",id,fallback)))
func rename_selected(value: String) -> Error:
	var cfg := ConfigFile.new()
	cfg.load("user://character_selection.cfg")
	cfg.set_value("names",selected,preload("res://scripts/campus/social/public_profiles.gd").clean_name(value))
	var error := cfg.save("user://character_selection.cfg")
	if error==OK: changed.emit()
	return error
