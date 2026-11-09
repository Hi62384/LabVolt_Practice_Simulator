extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
## Attach only on developer request. Hidden overlays do no string formatting.
var probe: Node
var _label: Label
var _clock := 0.0

func _ready() -> void:
	_label = Label.new()
	_label.theme = HudTheme.create()
	_label.add_theme_stylebox_override("normal", HudTheme.card_style())
	_label.add_theme_font_size_override("font_size", 14)
	_label.position = Vector2(16, 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(probe):
		return
	_clock += delta
	if _clock < 0.5:
		return
	_clock = 0.0
	var report: Dictionary = probe.report()
	_label.text = "FPS %.1f | 1%% low %.1f | p99 %.1f ms\nGPU timing unavailable | samples %d" % [report.get("average_fps", 0.0), report.get("one_percent_low_fps", 0.0), report.get("p99_ms", 0.0), report.sample_count]
