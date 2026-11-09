extends RefCounted
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
const PATH := "user://campus_profile_visibility.cfg"
var values := {"appearance":true,"kit":false,"parts":false,"money":false,"course":false,"gym":false,"emotes":true}
func load_settings(path := PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path)!=OK: return
	for key in values: values[key]=bool(cfg.get_value("public",key,values[key]))
func save_settings(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	for key in values: cfg.set_value("public",key,bool(values[key]))
	return cfg.save(path)
func build_controls(parent: VBoxContainer) -> void:
	var body := Layout.section(parent, "Public player card", "Choose what other players may see. Grades and notes outside the public projection stay private.", "lock")
	var feedback := UI.text("Changes save immediately.", "MutedLabel")
	body.add_child(feedback)
	for key in values:
		var toggle := CheckBox.new(); toggle.text="Share "+key.capitalize(); toggle.button_pressed=values[key]; toggle.custom_minimum_size.y=44; body.add_child(toggle)
		toggle.toggled.connect(func(enabled):
			values[key]=enabled
			var error := save_settings()
			feedback.text="Visibility saved" if error==OK else "Could not save visibility: "+error_string(error)
			feedback.theme_type_variation="MutedLabel" if error==OK else "ErrorLabel")
