extends GridContainer
## Reflows on available width, without duplicating cards or touching caller data.
@export var minimum_card_width := 300.0
@export var maximum_columns := 4

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_reflow)
	_reflow()

func _reflow() -> void:
	var gap := float(get_theme_constant("h_separation"))
	columns = clampi(int((size.x + gap) / maxf(minimum_card_width + gap, 1.0)), 1, maxi(maximum_columns, 1))
