extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var ports: Array=[]
var rows := 10
var validate := Callable()
var apply := Callable()
var content: VBoxContainer
var notice: Label

func _ready() -> void:
	custom_minimum_size.x=260
	content=VBoxContainer.new();add_child(content)
	hide()

func configure(current_ports: Array, board_rows: int, validator: Callable, apply_mapping: Callable) -> void:
	ports=current_ports.duplicate();rows=board_rows;validate=validator;apply=apply_mapping
	if is_node_ready():_render()

func open_panel() -> void:
	_render();show()

func close_panel() -> void:hide()

func _render() -> void:
	for child in content.get_children():content.remove_child(child);child.queue_free()
	content.add_child(UI.header("Bench connections","B1–B4 connect to real DC bench posts.",close_panel))
	for index in mini(ports.size(),4):
		var field := UI.field("B%d → board hole"%(index+1),"P1 / N1 / A1", "Enter a real board hole")
		field.get_node("Input").text=str(ports[index]);content.add_child(field)
		field.get_node("Input").text_submitted.connect(func(raw: String):_commit(index,raw,field))
	notice=UI.text("Use the DC instrument Leads view or physical posts to connect external cables.","MutedLabel")
	content.add_child(notice)

func _commit(index: int, raw: String, field: VBoxContainer) -> void:
	if not validate.is_valid() or not apply.is_valid():UI.field_error(field,"Bench mapping unavailable.");return
	var checked: Dictionary=validate.call(index,raw,rows)
	if not checked.get("ok",false):UI.field_error(field,str(checked.get("error","Unknown hole")));return
	var normalized := str(checked.get("value",""))
	if normalized.is_empty():UI.field_error(field,"Unknown hole");return
	var result: Dictionary=apply.call(index,normalized)
	if not result.get("ok",false):UI.field_error(field,str(result.get("error","Could not save mapping")));return
	ports[index]=normalized;field.get_node("Input").text=normalized;UI.field_error(field,"")
	notice.text="B%d now maps to %s"%[index+1,normalized]
