extends RefCounted
## Integrator calls after existing paper-owner and session policy checks.
const Workspace = preload("res://scripts/math_ui/workspace.gd")
const Codec = preload("res://scripts/math_ui/answer_codec.gd")

static func mount(parent: Node, public_problem: Dictionary, saved_state: Dictionary, writable: bool, host_policy: Dictionary, parse_callable: Callable, save_callback: Callable) -> Control:
	var widget: Control
	var owner_view: Control
	if public_problem.get("course","")=="MTH255" and ResourceLoader.exists("res://scripts/mth255/worksheet_adapter.gd"):
		owner_view=load("res://scripts/mth255/worksheet_adapter.gd").new()
		parent.add_child(owner_view);owner_view.configure(public_problem,writable,host_policy,parse_callable)
		widget=owner_view.workspace
	else:
		widget=Workspace.new();owner_view=widget
		parent.add_child(widget);widget.configure(public_problem,writable,host_policy,parse_callable)
	if not saved_state.is_empty():owner_view.restore(saved_state)
	widget.changed.connect(func(_state):
		if not writable or not save_callback.is_valid():return
		var state: Dictionary=owner_view.snapshot()
		var envelope:=Codec.encode(state)
		if envelope.ok:save_callback.call(str(public_problem.get("id","")),state.answer,envelope.text)
		else:widget.save_error(str(envelope.get("error","Unknown save failure")))
	)
	return widget

static func whiteboard(parent: Node, public_step: Dictionary, parse_callable: Callable=Callable()) -> Control:
	# A progressive teacher step must already have been released by the host.
	var widget:=Workspace.new()
	parent.add_child(widget)
	widget.configure(public_step,false,{"demonstration":true,"formula_allowed":false},parse_callable)
	return widget
