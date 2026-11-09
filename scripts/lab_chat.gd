extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
var game: Node
var panel: PanelContainer
var log_view: RichTextLabel
var lines: Array[String]=[]
var expires := 0.0
func build(owner_game: Node) -> void:
	game=owner_game;layer=12
	panel=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position=Vector2(24,-215);panel.size=Vector2(430,155);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
	panel.theme=HudTheme.create()
	panel.add_theme_stylebox_override("panel",HudTheme.card_style())
	var box := VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(box)
	var channel := UI.badge("Team channel · T to chat", "network");channel.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(channel)
	log_view=RichTextLabel.new();log_view.bbcode_enabled=false;log_view.scroll_following=true;log_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	log_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size",15);box.add_child(log_view)
	game.ui.chat_input.theme=panel.theme
	game.ui.chat_input.tooltip_text="Team chat • Enter sends • Escape closes"
	game.ui.chat_input.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	game.ui.chat_input.position=Vector2(24,-52);game.ui.chat_input.size=Vector2(430,36)
	game.session.chat_received.connect(receive)
	get_viewport().size_changed.connect(_fit_chat)
	_fit_chat()

func _fit_chat() -> void:
	var area := get_viewport().get_visible_rect().size
	panel.position=Vector2(24,area.y-245);panel.size=Vector2(minf(430,area.x-48),175)
	game.ui.chat_input.position=Vector2(24,area.y-60);game.ui.chat_input.size=Vector2(minf(430,area.x-48),44)
func receive(peer: int,sender: String,message: String) -> void:
	lines.append(sender+": "+message)
	if lines.size()>40:lines.pop_front()
	log_view.text="\n".join(lines);expires=Time.get_ticks_msec()/1000.0+12
func _process(_delta: float) -> void:
	if not is_instance_valid(game):return
	var now := Time.get_ticks_msec()/1000.0
	panel.visible=game.session.online and game.front.in_game and (game.player.enabled or game.ui.chat_input.visible)
	if panel.visible and now>expires and not game.ui.chat_input.visible:log_view.text="T  ·  Team chat"
	elif panel.visible:log_view.text="\n".join(lines) if not lines.is_empty() else "T  ·  Team chat"
