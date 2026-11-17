extends RefCounted

static func action(event: InputEvent, keys: Dictionary, captured: bool, in_game: bool, enabled: bool, inspecting: bool, blocked: bool) -> String:
	if blocked or not captured or not in_game or not enabled:return ""
	if not event is InputEventKey or not event.pressed or event.echo:return ""
	if event.physical_keycode==keys.get("inspect",KEY_I):return "inspect"
	if not inspecting and event.physical_keycode==keys.get("place_item",KEY_F):return "place"
	return ""
