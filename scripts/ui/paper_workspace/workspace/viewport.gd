extends Control
## Paper-space camera. Content is never reparented during a gesture.
signal view_changed(zoom: float, offset: Vector2)

const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.4
const EDGE_GUARD := 56.0
var paper: Control
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_pointer := Vector2.ZERO
var target_zoom := 1.0
var zoom_anchor := Vector2.ZERO
var fitted := false

static func bounded_offset(view_size: Vector2, page_size: Vector2, scale_value: float, wanted: Vector2) -> Vector2:
	var scaled := page_size * scale_value
	var result := wanted
	for axis in 2:
		var extent: float = scaled[axis]
		var room: float = view_size[axis]
		if extent <= room:
			result[axis] = (room - extent) * 0.5
		else:
			result[axis] = clampf(result[axis], room - extent - EDGE_GUARD, EDGE_GUARD)
	return result

func mount(value: Control) -> void:
	if is_instance_valid(paper) and paper.get_parent() == self: remove_child(paper)
	paper = value
	if paper.get_parent() != null: paper.get_parent().remove_child(paper)
	add_child(paper)
	fitted = false
	fit()

func fit() -> void:
	if not is_instance_valid(paper) or size.x < 1 or size.y < 1: return
	fitted = true
	zoom = clampf(minf((size.x - 72.0) / paper.size.x, (size.y - 28.0) / paper.size.y), MIN_ZOOM, 1.0)
	target_zoom = zoom
	offset = bounded_offset(size, paper.size, zoom, Vector2.ZERO)
	_apply()

func restore(value_zoom: float, value_offset: Vector2) -> void:
	if not is_instance_valid(paper): return
	zoom = clampf(value_zoom, MIN_ZOOM, MAX_ZOOM)
	fitted = true
	target_zoom = zoom
	offset = bounded_offset(size, paper.size, zoom, value_offset)
	_apply()

func paper_point(view_point: Vector2) -> Vector2:
	return (view_point - offset) / zoom

func zoom_at(pointer: Vector2, factor: float) -> void:
	if not is_instance_valid(paper): return
	zoom_anchor = pointer
	target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	set_process(true)

func move_by(delta: Vector2) -> void:
	if not is_instance_valid(paper): return
	offset = bounded_offset(size, paper.size, zoom, offset + delta)
	_apply()

func _process(delta: float) -> void:
	if not is_instance_valid(paper): return
	if absf(target_zoom - zoom) < 0.0005:
		zoom = target_zoom
		set_process(false)
		return
	var new_zoom := lerpf(zoom, target_zoom, 1.0 - exp(-16.0 * delta))
	var point := paper_point(zoom_anchor)
	zoom = new_zoom
	offset = bounded_offset(size, paper.size, zoom, zoom_anchor - point * zoom)
	_apply()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(paper):
		if not fitted:
			fit()
			return
		offset = bounded_offset(size, paper.size, zoom, offset)
		_apply()

func _apply() -> void:
	paper.scale = Vector2.ONE * zoom
	paper.position = offset
	view_changed.emit(zoom, offset)
