extends Control
## Opt-in mount point. Existing menus remain unchanged until the safe integration window.
signal apply_requested(state: Dictionary)
signal transaction_requested(operation: String,args: Array)
signal closed
const Coordinator = preload("res://scripts/avatar_cosmetics/core/coordinator.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const CustomizerScene = preload("res://scenes/avatar_cosmetics/customizer_panel.tscn")
const Cache = preload("res://scripts/avatar_cosmetics/ui/thumbnail_cache.gd")
var coordinator := Coordinator.new()
var panel: Control

func open_profile(profile: Dictionary,legacy: Dictionary={}) -> Dictionary:
	if not is_inside_tree():return {"ok":false,"error":"Mount editor before opening"}
	if not coordinator.load_catalog():return {"ok":false,"errors":coordinator.errors}
	var resolved := coordinator.begin_preview(profile,legacy)
	if not resolved.errors.is_empty():return {"ok":false,"errors":resolved.errors}
	if is_instance_valid(panel):panel.free()
	panel=CustomizerScene.instantiate();add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cache := Cache.new()
	panel.add_child(cache)
	var legacy_base := legacy.duplicate(true)
	var fit_cache := {}
	var render_draft := func(state: Dictionary,catalog: Dictionary):
		var render_state := state.duplicate(true)
		render_state.legacy_character=legacy_base
		return Renderer.render_avatar(render_state,catalog,true,fit_cache)
	panel.configure(coordinator.catalog,coordinator.owned,coordinator.draft,cache,render_draft,Core.resolve)
	panel.draft_changed.connect(func(state: Dictionary):coordinator.draft=state.duplicate(true))
	panel.apply_requested.connect(func(intent: Dictionary):transaction_requested.emit("avatar_cosmetic",[intent]))
	panel.close_requested.connect(func():closed.emit())
	return {"ok":true}

func request_apply() -> Dictionary:
	var resolved := Core.resolve(coordinator.catalog,coordinator.draft,coordinator.owned)
	if resolved.errors.is_empty():
		if panel.is_dirty():transaction_requested.emit("avatar_cosmetic",[panel.atomic_edit_intent()])
		apply_requested.emit(resolved.state.duplicate(true))
	return resolved

func acknowledge_apply(success: bool,message: String="",saved_draft: Dictionary = {}) -> void:
	if is_instance_valid(panel):panel.acknowledge_apply(success,message,saved_draft)
