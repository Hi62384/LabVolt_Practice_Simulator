extends HBoxContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
const Signage = preload("res://scripts/campus/presentation/signage/campus_signage.gd")
# Caller supplies already-authoritative activity and locally resolved registry room.
var location: Label
var activity: Label
var timer: Label
var guidance: Label
var last_text := ""
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	# front_menu assigns a lower legacy offset before add_child; pin this HUD to the viewport corner.
	position=Vector2(12,12)
	theme=HudTheme.create()
	# Flow inside the existing HBox root preserves front_menu's typed reference.
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x=minf(1000,get_viewport_rect().size.x-56)
	flow.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(flow)
	for field in ["location","activity","timer","guidance"]:
		var card := PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var skin := HudTheme.card_style()
		skin.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel",skin)
		var badge := UI.badge("", {"location":"home","activity":"course","timer":"info","guidance":"play"}[field])
		card.add_child(badge);flow.add_child(card)
		var label := badge.get_child(1) as Label
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x=minf(float({"location":180,"activity":140,"timer":60,"guidance":140}[field]),get_viewport_rect().size.x-160)
		label.tooltip_text=""
		set(field,label)
	get_viewport().size_changed.connect(func():flow.custom_minimum_size.x=minf(1000,get_viewport_rect().size.x-56))
func update_state(room: Dictionary, state: Dictionary, remaining_seconds: float, destination: Dictionary={}) -> void:
	location.text=Signage.room_hud_identity(room)
	var mode := str(state.get("mode","Freeplay"))
	activity.text="Play" if mode=="Freeplay" else mode+" · "+str(state.get("course_id",""))
	timer.text="%02d:%02d"%[int(maxf(remaining_seconds,0))/60,int(maxf(remaining_seconds,0))%60] if remaining_seconds>=0 else ""
	guidance.text=""
	if destination.get("enabled",not destination.is_empty()):
		guidance.text=("Arrived · " if destination.get("arrived",false) else "→ ")+str(destination.get("number",""))
		if destination.has("distance") and not destination.get("arrived",false):
			guidance.text+=" · "+str(destination.get("direction","Next"))+" %.0f m"%float(destination.distance)

	for label in [location,activity,timer,guidance]:
		label.get_parent().get_parent().visible=not label.text.is_empty()
		label.tooltip_text=label.text
