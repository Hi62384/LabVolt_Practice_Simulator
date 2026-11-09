extends SceneTree
## Run only in the disposable work/io-fixture with hash-verified IO dependencies.
const Board=preload("res://scripts/breadboard_model.gd")
class MemoryProfile extends RefCounted:
	var data: Dictionary
	func save() -> Error:return OK
class CopyUI extends "res://scripts/electronics_ui.gd":
	func open(_page := "shop",_index := -1) -> void:pass
var checks := 0
var failures := 0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://scripts/io_devices/surface.gd"):
		print("SKIP: optional I/O dependency is absent; use the documented fixture");quit();return
	var canvas=load("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas)
	canvas.board=Board.empty();canvas.board.parts=[{"id":"s","type":"io_slider","a":"A4","b":"F4","pins":["A4","B4","F4"]}]
	canvas.selected_type="interact"
	for i in 2:await process_frame
	check(canvas.io_adapter.views.has("board/s"),"eligible surface mounted by globally stable ID")
	var view: Control=canvas.io_adapter.views["board/s"]
	check(view.interact and view.mouse_filter==Control.MOUSE_FILTER_STOP,"interact mode owns pointer capture")
	var ui=CopyUI.new();var profile=MemoryProfile.new()
	profile.data={"equipped":"s","kits":{"s":{"board":canvas.board.duplicate(true)}},"blueprints":{}}
	ui.profile=profile;ui.canvas=canvas;ui.status=Label.new()
	ui.design_preview.board=canvas.board.duplicate(true);ui.design_preview.solver.time=7.;ui.design_preview.firmware_states={"sentinel":{"pc":9}}
	var edits := [0];canvas.design_changed.connect(func(_board):edits[0]+=1)
	canvas.io_command_requested.connect(func(id,command):ui.apply_preview_io(canvas,"s",id,command))
	view.submit({"op":"move","x":.8})
	check(canvas.board.io_controls["board/s"].x==.8 and canvas.board.io_controls["board/s"].revision==1,"designer command applied by one authoritative reducer")
	check(ui.design_preview.board.io_controls["board/s"].x==.8 and ui.design_preview.solver.time==7. and ui.design_preview.firmware_states.sentinel.pc==9,"input updates retain preview solver/runtime")
	check(edits[0]==0 and view.awaiting_revision==-1,"input acknowledgement does not emit board redeployment")
	canvas.selected_type="select";canvas.refresh_io_surfaces()
	check(not view.interact and view.mouse_filter==Control.MOUSE_FILTER_IGNORE,"edit/select mode retains existing canvas controls")
	canvas.board.parts[0].surface_rotation=PI/2;canvas.refresh_io_surfaces()
	check(absf(view.rotation-PI/2)<1e-6,"saved surface orientation applied")
	var bp := Board.blueprint(canvas.board,"IO copy");bp.layout={"rows":30,"parts":canvas.board.parts.duplicate(true),"wires":[]}
	check(bp.io_controls.s.x==.8 and bp.parts[0].surface_rotation==PI/2,"packaging preserves relative I/O defaults and orientation")
	profile.data.blueprints={"ic:copy":bp};ui.edit_package("ic:copy")
	check(profile.data.kits[profile.data.equipped].board.io_controls["board/s"].x==.8,"editable package copy restores full-path input defaults")
	var nested := Board.empty();nested.definitions={"ic:copy":bp};nested.parts=[{"id":"one","type":"ic:copy","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}]
	check(Board.io_inputs(nested)["board/one/s"].x==.8,"nested defaults expand to unique instance paths")
	nested.io_controls={"board/one/s":{"revision":2,"x":.2}}
	check(Board.io_inputs(nested)["board/one/s"].x==.2,"instance override wins over blueprint defaults")
	var hidden_canvas=load("res://scripts/breadboard_canvas.gd").new();root.add_child(hidden_canvas)
	bp.package="IC";bp.exposed=[];bp.footprint={"width":8,"height":6,"color":"303b40"}
	hidden_canvas.board=nested;hidden_canvas.refresh_io_surfaces()
	check(hidden_canvas.io_adapter.views.is_empty(),"hidden IC has no I/O surface or pointer target")
	bp.exposed=["s"];hidden_canvas.refresh_io_surfaces()
	check(hidden_canvas.io_adapter.views.has("board/one/s"),"individually exposed nested I/O surface becomes eligible")
	hidden_canvas.queue_free();canvas.queue_free();ui.status.free();ui.free()
	await queued_release()
	print("EDITOR IO HOOK: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func queued_release() -> void:
	var ui=CopyUI.new();root.add_child(ui)
	var canvas=load("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas)
	canvas.set_meta("io_bench",-1);canvas.set_meta("io_kit","s")
	canvas.board=Board.empty();canvas.board.parts=[{"id":"k","type":"io_keypad","a":"A1","b":"F1","pins":["A1","A2","A3","A4","F1","F2","F3"]}]
	canvas.selected_type="interact"
	for i in 2:await process_frame
	var commands: Array=[];canvas.io_command_requested.connect(func(_id,command):commands.append(command.duplicate(true)))
	var view: Control=canvas.io_adapter.views["board/k"]
	view.held_key=2;view.submit({"op":"key","key":2,"pressed":true})
	check(commands.size()==1 and view.awaiting_revision==0,"press waits for authoritative revision")
	ui.canvas=canvas;ui.retire_io_canvas()
	check(ui.retired_io_canvases.size()==1 and not view.pending.is_empty() and not view.pending[-1].pressed,"closing retains queued release behind outstanding press")
	ui.acknowledge_io_input(-1,"board/k",{"revision":1,"keys":4})
	check(commands.size()==2 and not commands[-1].pressed and commands[-1].revision==1,"press acknowledgement forwards retained release with current revision")
	ui.acknowledge_io_input(-1,"board/k",{"revision":1,"keys":4})
	check(not canvas.has_pending_io(),"same-revision explicit rejection acknowledgement unblocks queue")
	ui.refresh_retired_io()
	check(ui.retired_io_canvases.is_empty(),"retired view freed after release response")
	ui.queue_free()
