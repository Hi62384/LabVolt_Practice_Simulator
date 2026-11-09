extends Label
## A Label-compatible HUD affordance: game.gd keeps ownership of text/visibility.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var icon_key := "info"

func _draw() -> void:
	if text.is_empty() or icon_key.is_empty(): return
	var texture := UI.icon(icon_key)
	draw_texture_rect(texture, Rect2(Vector2(-28, 2), Vector2(20, 20)), false)
