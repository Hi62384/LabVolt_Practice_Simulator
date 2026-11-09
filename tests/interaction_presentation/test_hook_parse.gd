extends SceneTree
const GameScript=preload("res://scripts/game.gd")
const SessionScript=preload("res://scripts/session.gd")
const SettingsScript=preload("res://scripts/campus/ui/graphics_settings.gd")
const CampusScript=preload("res://scripts/campus_integration.gd")
func _initialize() -> void:
	print("HANDS_HOOK_PARSE_OK")
	quit(0)
