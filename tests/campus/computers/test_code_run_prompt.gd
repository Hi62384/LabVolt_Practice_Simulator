extends SceneTree
const Desktop=preload("res://scripts/campus/computers/desktop_ui.gd")
class Runner extends "res://scripts/campus/computers/ide_execution.gd":
	var submitted:=false
	func configure_from_host() -> void:endpoint="fixture"
	func supported_runtimes() -> Dictionary:
		await get_tree().process_frame
		return {"runtimes":[{"name":"Python","id":71}]}
	func execute(path: String,source: String,stdin: String="",runtime_id: int=0) -> String:
		submitted=path=="untitled.py" and source=="print(42)" and stdin=="" and runtime_id==0
		return "42"

func _initialize() -> void:call_deferred("run")

func run() -> void:
	create_timer(12.).timeout.connect(func():quit(1))
	var desktop:=Desktop.new()
	desktop.snapshot={"lease":8}
	root.add_child(desktop)
	desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var runner:=Runner.new()
	desktop.add_child(runner)
	desktop.execution=runner
	var response:={"text":""}
	desktop._run_source("untitled.py","print(42)",func(value: String):response.text=value)
	await process_frame
	await process_frame
	var card:=desktop.find_child("RunCard",true,false) as PanelContainer
	assert(card!=null and card.is_visible_in_tree())
	assert(root.get_visible_rect().encloses(card.get_global_rect()))
	var button: Button
	for child in card.find_children("*","Button",true,false):
		if child.text=="Run":button=child
	assert(button!=null and card.get_global_rect().encloses(button.get_global_rect()))
	button.pressed.emit()
	await process_frame
	assert(runner.submitted and response.text=="42")
	print("CAMPUS_RUN_DIALOG PASS")
	desktop.queue_free()
	await process_frame
	quit()
