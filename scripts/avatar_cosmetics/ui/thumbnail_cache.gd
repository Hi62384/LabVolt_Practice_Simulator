class_name CosmeticThumbnailCache
extends Node

signal thumbnail_ready(key: String, texture: Texture2D)

@export var max_entries := 160
var _memory: Dictionary = {}
var _ages: Dictionary = {}
var _tick := 0
var _queue: Array[Dictionary] = []
var _working := false
var _render_callable: Callable
var _prefer_rendered := false
var _references: Dictionary = {}

func configure(renderer: Callable, prefer_rendered := false) -> void:
	_render_callable = renderer
	_prefer_rendered = prefer_rendered

static func cache_key(item_id: String, parameters: Dictionary, body: Dictionary) -> String:
	var normalized := {"body": _ordered(body), "id": item_id, "parameters": _ordered(parameters), "v": 1}
	return (JSON.stringify(normalized) as String).sha256_text()

static func _ordered(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key in keys:
			result[str(key)] = _ordered(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_ordered(item))
		return result
	return value

func request_thumbnail(item_id: String, parameters: Dictionary, body: Dictionary, static_path := "") -> String:
	var key := cache_key(item_id, parameters, body)
	_references[key] = int(_references.get(key, 0)) + 1
	_touch(key)
	if _memory.has(key):
		thumbnail_ready.emit(key, _memory[key])
		return key
	if not _prefer_rendered and not static_path.is_empty() and ResourceLoader.exists(static_path):
		var texture := load(static_path) as Texture2D
		if texture != null:
			_store(key, texture)
			thumbnail_ready.emit(key, texture)
			return key
	if not _queue.any(func(job: Dictionary) -> bool: return job.key == key):
		_queue.append({"key": key, "item_id": item_id, "parameters": parameters.duplicate(true), "body": body.duplicate(true)})
		call_deferred("_pump")
	return key

func release(key: String) -> void:
	var remaining := int(_references.get(key, 0)) - 1
	if remaining > 0:
		_references[key] = remaining
		return
	_references.erase(key)
	if not _memory.has(key):
		_ages.erase(key)
	for index in range(_queue.size() - 1, -1, -1):
		if str(_queue[index].get("key", "")) == key:
			_queue.remove_at(index)

func get_cached(key: String) -> Texture2D:
	_touch(key)
	return _memory.get(key)

func _pump() -> void:
	# Exactly one shared job is active. The injected renderer may await a frame or
	# use one reusable SubViewport; cards themselves never own a 3D viewport.
	if _working or _queue.is_empty() or not _render_callable.is_valid():
		return
	_working = true
	var job: Dictionary = _queue.pop_front()
	var result: Variant = await _render_callable.call(job.item_id, job.parameters, job.body)
	if result is Texture2D and int(_references.get(job.key, 0)) > 0:
		_store(job.key, result)
		thumbnail_ready.emit(job.key, result)
	_working = false
	if not _queue.is_empty():
		call_deferred("_pump")

func _touch(key: String) -> void:
	_tick += 1
	_ages[key] = _tick

func _store(key: String, texture: Texture2D) -> void:
	_memory[key] = texture
	_touch(key)
	while _memory.size() > maxi(max_entries, 8):
		var oldest := ""
		var age := INF
		for candidate in _memory:
			if float(_ages.get(candidate, 0)) < age:
				oldest = candidate
				age = float(_ages[candidate])
		_memory.erase(oldest)
		_ages.erase(oldest)
