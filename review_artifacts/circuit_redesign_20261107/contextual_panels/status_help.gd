extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var label: Button
var explanation: Label
const KNOWN := {"no_power":"No power source","running":"Circuit running","short":"Short circuit detected","probe_missing":"Probe not measured","paused":"Simulation paused","invalid":"Invalid connection","saved":"Design saved"}

func _ready() -> void:
	var column := VBoxContainer.new();add_child(column)
	label=UI.action("Ready","info",func():explanation.visible=not explanation.visible)
	column.add_child(label)
	explanation=UI.text("","MutedLabel");explanation.hide();column.add_child(explanation)

func set_status(code: String, detail: String) -> void:
	label.text=str(KNOWN.get(code,"Status"))
	label.icon=UI.icon("warning" if code in ["short","invalid","no_power","probe_missing"] else "check" if code in ["running","saved"] else "info")
	explanation.text=detail
	explanation.visible=false
	label.disabled=detail.is_empty()
