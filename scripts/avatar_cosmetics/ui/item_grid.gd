class_name CosmeticItemGrid
extends ScrollContainer
const Card = preload("res://scripts/avatar_cosmetics/ui/item_card.gd")
const CatalogAdapter = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const ThumbnailCache = preload("res://scripts/avatar_cosmetics/ui/thumbnail_cache.gd")

signal item_requested(definition: Dictionary)

var _grid: GridContainer
var _thumbnail_cache: ThumbnailCache
var _cards_by_key: Dictionary = {}
var _placeholder: Texture2D
var _requested_keys: Array[String] = []
var _generation := 0
var _equipped := {}
var _selected_id := ""

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	add_child(_grid)
	resized.connect(_fit_columns)
	_fit_columns()

func _fit_columns() -> void:
	_grid.columns = clampi(int((size.x - 12) / (Card.WIDTH + 8)), 1, 4)

func configure(thumbnail_cache: ThumbnailCache, placeholder: Texture2D = null) -> void:
	if _thumbnail_cache != null:
		for key in _requested_keys:
			_thumbnail_cache.release(key)
	_requested_keys.clear()
	if _thumbnail_cache != null and _thumbnail_cache.thumbnail_ready.is_connected(_on_thumbnail_ready):
		_thumbnail_cache.thumbnail_ready.disconnect(_on_thumbnail_ready)
	_thumbnail_cache = thumbnail_cache
	_placeholder = placeholder
	if _thumbnail_cache != null:
		_thumbnail_cache.thumbnail_ready.connect(_on_thumbnail_ready)

func show_items(items: Array, state: Dictionary, selected_id := "") -> void:
	_generation += 1
	if _thumbnail_cache != null:
		for key in _requested_keys:
			_thumbnail_cache.release(key)
	_requested_keys.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards_by_key.clear()
	_update_selection_state(state, selected_id)
	_append_batch(items, state.duplicate(true), _generation, 0)

func update_selection(state: Dictionary, selected_id: String) -> void:
	_update_selection_state(state, selected_id)
	for card in _grid.get_children():
		var id: String = card.definition.id
		card.update_selection(_equipped.has(id), id == _selected_id)

func _update_selection_state(state: Dictionary, selected_id: String) -> void:
	_selected_id = selected_id
	_equipped.clear()
	for entry in state.get("equipped", {}).values():
		_equipped[str(entry.get("id", ""))] = true

func _append_batch(items: Array, state: Dictionary, generation: int, start: int) -> void:
	if generation != _generation:
		return
	var body: Dictionary = state.get("body", {})
	var finish := mini(start + 24, items.size())
	for index in range(start, finish):
		var definition: Variant = items[index]
		if definition is not Dictionary:
			continue
		var card := Card.new()
		_grid.add_child(card)
		var item_id := str(definition.get("id", ""))
		var slot := CatalogAdapter.equipped_slot_for(state, item_id)
		var parameters: Dictionary = state.get("equipped", {}).get(slot, {}).get("parameters", {})
		card.bind(definition, _equipped.has(item_id), item_id == _selected_id, _placeholder)
		card.item_requested.connect(func(value: Dictionary): item_requested.emit(value))
		if _thumbnail_cache != null:
			card.cache_key = _thumbnail_cache.request_thumbnail(item_id, parameters, body, str(definition.get("thumbnail", "")))
			_requested_keys.append(card.cache_key)
			_cards_by_key.get_or_add(card.cache_key, []).append(card)
			var cached := _thumbnail_cache.get_cached(card.cache_key)
			if cached != null:
				card.accept_thumbnail(card.cache_key, cached)
	if finish < items.size():
		call_deferred("_append_batch", items, state, generation, finish)

func _exit_tree() -> void:
	_generation += 1
	if _thumbnail_cache != null:
		for key in _requested_keys:
			_thumbnail_cache.release(key)
	_requested_keys.clear()

func _on_thumbnail_ready(key: String, texture: Texture2D) -> void:
	for card in _cards_by_key.get(key, []):
		if is_instance_valid(card):
			card.accept_thumbnail(key, texture)

