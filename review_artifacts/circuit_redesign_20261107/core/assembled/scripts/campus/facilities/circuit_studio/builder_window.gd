extends Window
## Local workstation UI. Domain forms retain their existing validation/save callbacks.
const Form=preload("res://scripts/package_editor/package_form.gd")
const Editor=preload("res://scripts/pcb_design/editor.gd")
var game: Node
var kind: String
var content: VBoxContainer
var notice: Label

func open_station(owner_game: Node,package_kind: String) -> void:
	game=owner_game;kind=package_kind
	title="IC Builder · packaging & pins" if kind=="IC" else "PCB Builder · outline & copper"
	size=Vector2i(1100,760);min_size=Vector2i(760,500)
	close_requested.connect(_close)
	game.release_mouse()
	_rebuild()
	popup_centered()

func _rebuild(message: String="") -> void:
	for child in get_children():remove_child(child);child.queue_free()
	content=VBoxContainer.new();content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(content)
	var tools:=HFlowContainer.new();content.add_child(tools)
	_button(tools,"Close workstation",_close)
	notice=Label.new();notice.text=message;content.add_child(notice)
	if not game.electronics.profile.data.get("pending_trade",{}).is_empty():notice.text="Finish the pending trade before editing circuit packages.";return
	var profile=game.electronics.profile
	var draft: Dictionary=profile.data.kits[profile.data.equipped].get("package_draft",{}).duplicate(true)
	if str(draft.get("package",kind))!=kind:draft={}
	draft.package=kind
	var editor: Control=preload("res://scripts/electronics/circuit_workspace/package_mount.gd").mount(game.electronics,content,kind,draft,func():hide();queue_free())
	editor.saved.connect(func(result):notice.text=result)

func _edit_board(blueprint: Dictionary) -> void:
	for child in content.get_children():content.remove_child(child);child.queue_free()
	_button(content,"Back to PCB packages",_rebuild)
	var editor=Editor.new();content.add_child(editor);editor.build(game.electronics.profile,blueprint)
	editor.saved.connect(func(message: String):title=message)

func _inspect(blueprint: Dictionary) -> void:
	var dialog:=AcceptDialog.new();dialog.title=str(blueprint.get("name","Package"));add_child(dialog)
	var lines:=PackedStringArray([str(blueprint.get("description","")),"Footprint: "+str(blueprint.get("footprint",{})),"Marking: "+str(blueprint.get("marking",""))])
	for pin in blueprint.get("pins",[]):lines.append(str(pin.get("name","Pin"))+" → "+str(pin.get("node",""))+" · "+str(pin.get("role","")))
	dialog.dialog_text="\n".join(lines);dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=40;button.focus_mode=Control.FOCUS_ALL;parent.add_child(button);button.pressed.connect(callback);return button

func _close() -> void:
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()
