extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
# Read-only: receives a sanitized host projection, never a save/profile object.
func show_profile(public_profile: Dictionary) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	theme=HudTheme.create()
	add_theme_stylebox_override("panel", HudTheme.card_style())
	custom_minimum_size=Vector2(300,240)
	size=Vector2(minf(560,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); scroll.add_child(box)
	var safe := preload("res://scripts/campus/social/public_profiles.gd")
	var visibility := {}
	for key in safe.FIELDS: visibility[key]=public_profile.has(key)
	var projected: Dictionary=safe.project(str(public_profile.get("id","")),str(public_profile.get("name","Student")),public_profile,visibility)
	box.add_child(UI.header(projected.name, "Public player card • shared by this player", hide))
	var shared_sections := 0
	for section in safe.FIELDS:
		if not projected.has(section): continue
		shared_sections += 1
		var section_body := Layout.section(box, section.capitalize(), "Shared information", {"appearance":"palette","kit":"inventory","parts":"component","money":"cart","course":"course","gym":"play","emotes":"play"}.get(section,"info"))
		for field in projected[section]:
			var value: Variant=projected[section][field]
			var lines: Array[String]=[]
			if value is Array:
				for item in value:
					lines.append((str(item.get("name","Part"))+" × "+str(item.get("count",0))) if item is Dictionary else str(item))
			else: lines.append(str(value))
			var detail := Label.new(); detail.text=field.replace("_"," ").capitalize()+": "+", ".join(lines); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; section_body.add_child(detail)
	if shared_sections == 0:
		var private_card := UI.card("Private profile", "This player has not shared additional fields.", "lock")
		private_card.get_node("Content/Copy/Rarity").hide()
		box.add_child(private_card)
	box.add_child(UI.action("Close player card", "close", hide))
	show()
