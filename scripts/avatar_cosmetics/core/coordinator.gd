extends RefCounted
## Additive coordinator: caller supplies authenticated persistence and explicit commit.
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Catalog = preload("res://scripts/avatar_cosmetics/core/catalog.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const Persistence = preload("res://scripts/avatar_cosmetics/persistence/profile_adapter.gd")
var catalog: Dictionary={}
var errors: Array=[]
var draft: Dictionary={}
var owned: Array=[]

func load_catalog() -> bool:
	var definitions: Array=[]
	for category in ["footwear","clothing","accessories","faces_hair"]:
		var path: String="res://assets/cosmetics/"+str(category)+"/catalog.json"
		if not FileAccess.file_exists(path):continue
		var value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or not value.get("items") is Array:errors=["Invalid catalog: "+category];return false
		definitions.append_array(value.items)
	var result := Catalog.collect(definitions)
	catalog=result.items;errors=result.errors
	return errors.is_empty()

func begin_preview(profile: Dictionary,legacy: Dictionary={}) -> Dictionary:
	var adapter := authoritative_adapter(func():return true)
	var preview_profile: Dictionary = adapter.migrate(profile,legacy)
	owned=adapter.owned_ids(preview_profile)
	var resolved := Core.resolve(catalog,adapter.equipment(preview_profile),owned)
	draft=resolved.state
	draft.legacy_character=legacy.duplicate(true)
	resolved.state=draft
	return resolved

func preview_item(id: String,parameters: Dictionary={}) -> Dictionary:
	if not catalog.has(id):return {"state":draft,"errors":["Unknown item"]}
	var next := draft.duplicate(true)
	Core.equip(next,catalog[id],parameters)
	var result := Core.resolve(catalog,next,owned)
	if result.errors.is_empty():draft=result.state
	return result

func render_preview() -> Node3D:
	return Renderer.render_avatar(draft,catalog)

func authoritative_adapter(authority: Callable) -> RefCounted:
	var adapter := Persistence.new(catalog,Core.resolve,Core.sanitize_body)
	adapter.is_authority=authority
	adapter.seed_equipment=Core.seed_equipment
	return adapter
