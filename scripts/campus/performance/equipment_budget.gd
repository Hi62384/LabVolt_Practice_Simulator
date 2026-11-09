extends RefCounted
## Presentation work only. Authoritative simulation must never use this queue.
var _items: Dictionary = {}
var _order: Array[String] = []
var _cursor := 0
var _clock := 0.0
var refreshed := 0
var last_cost_usec := 0

func register_display(id: String, callback: Callable, refresh_hz := 10.0) -> void:
	if not _items.has(id):
		_order.append(id)
	_items[id] = {"callback": callback, "interval": 1.0 / clampf(refresh_hz, 0.1, 60.0), "due": _clock, "dirty": true, "relevant": true}

func unregister_display(id: String) -> void:
	_items.erase(id)
	_order.erase(id)
	_cursor = 0

func mark_dirty(id: String) -> void:
	if _items.has(id):
		_items[id].dirty = true

func set_relevant(id: String, relevant: bool) -> void:
	if _items.has(id):
		_items[id].relevant = relevant

func tick(delta: float, budget_usec := 500) -> int:
	_clock += maxf(delta, 0.0)
	var start := Time.get_ticks_usec()
	var count := 0
	# Snapshot IDs so callbacks may safely unregister/register displays.
	var order := _order.duplicate()
	var first := _cursor
	if order.is_empty() or budget_usec <= 0:
		return 0
	for offset in order.size():
		var index := (first + offset) % order.size()
		var id: String = order[index]
		if not _items.has(id):
			continue
		var item: Dictionary = _items[id]
		if item.dirty and item.relevant and _clock >= item.due:
			if not item.callback.is_valid():
				unregister_display(id)
				continue
			# Clear first: a callback that dirties itself requests a subsequent refresh.
			item.dirty = false
			item.due = _clock + item.interval
			item.callback.call()
			count += 1
		_cursor = (index + 1) % order.size()
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	last_cost_usec = Time.get_ticks_usec() - start
	refreshed += count
	return count
