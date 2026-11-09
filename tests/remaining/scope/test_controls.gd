extends SceneTree
class GameFixture:
	extends Node
	func capture() -> void: pass
	func release_mouse() -> void: pass
class SystemFixture:
	extends Node
	var game: Node
	var bench: RefCounted
	var ui: CanvasLayer
	var states: Array=[]
	var actions: Array=[]
	var errors: Array=[]
	func request(_index: int, action: Dictionary) -> void:
		actions.append(action.duplicate(true))
		var error: String=bench.apply(action)
		if error!="":errors.append(error)
		states[0]=bench.snapshot();ui.refresh()
var failures := 0
var assertions := 0
func check(ok: bool, message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func artifact(name: String) -> String:
	var folder := OS.get_environment("LABVOLT_SCOPE_ARTIFACTS")
	if folder.is_empty():folder=OS.get_user_data_dir().path_join("scope-tests")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder.path_join(name)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var system := SystemFixture.new();root.add_child(system);system.game=GameFixture.new();system.add_child(system.game)
	system.bench=preload("res://tests/remaining/scope/core_fixture.gd").station("require-integrated" in OS.get_cmdline_user_args())
	if system.bench==null:quit(1);return
	system.bench.master=true;system.bench.channels[0].enabled=true;system.bench.channels[0].voltage=5.0
	system.bench.generator.enabled=true;system.bench.generator.frequency=20.0;system.bench.generator.amplitude=1.0;system.bench.generator.offset=-1.0
	system.bench.wires=[["CH1+","S1"],["CH1-","GND"],["GEN","S2"],["REF","GND"]]
	for i in 1000:system.bench.step(0.0005)
	system.states=[system.bench.snapshot()]
	system.ui=load("res://scripts/dc_ui.gd").new();system.add_child(system.ui);system.ui.build(system);system.ui.open(0)
	await process_frame;await process_frame
	var panel: Control=system.ui.scope_panel
	var tabs: TabContainer=system.ui.screen.find_children("*","TabContainer",true,false)[0];tabs.current_tab=4
	await process_frame
	var original: Array=system.bench.samples.duplicate(true)
	var controls: Dictionary=panel.controls
	controls["1:scale"].value=0.25
	controls["1:position"].value=-1.5
	check(system.bench.scope.channels[1].scale==.25 and system.bench.scope.channels[1].position==-1.5,"CH2 scale/position controls reach host")
	check(system.bench.scope.channels[0].scale==2 and system.bench.scope.channels[0].position==0,"CH1 unaffected by CH2 widgets")
	controls["1:coupling"].select(1);controls["1:coupling"].item_selected.emit(1)
	controls["0:attenuation"].select(1);controls["0:attenuation"].item_selected.emit(1)
	check(system.bench.scope.channels[1].coupling=="AC" and system.bench.scope.channels[0].coupling=="DC","per-channel coupling widget")
	check(system.bench.scope.channels[0].attenuation==10 and system.bench.scope.channels[1].attenuation==1,"independent probe widget")
	check(system.bench.samples==original,"widgets retain live raw circuit record")
	controls["0:enabled"].button_pressed=false
	check(not system.bench.scope.channels[0].enabled and panel.trace.channel_segments(0).is_empty(),"enable widget changes actual trace")
	panel.run_button.pressed.emit()
	check(not system.bench.scope.running and panel.run_button.text=="Run","Run/Stop state reconciles")
	var count: int=system.actions.size()
	panel.find_child("Autoset",true,false).pressed.emit()
	check(system.actions.size()==count+1 and system.actions[-1].key=="autoset","autoset is one authoritative atomic request")
	check(system.bench.scope.running,"autoset resumes capture")
	controls["-1:source"].select(1);controls["-1:source"].item_selected.emit(1)
	controls["-1:trigger_mode"].select(1);controls["-1:trigger_mode"].item_selected.emit(1)
	check(system.bench.scope.source==1 and system.bench.scope.trigger_mode=="Normal","source and acquisition mode widgets")
	# Return to a readable two-channel scene with different real signals and scales.
	controls["0:enabled"].button_pressed=true
	controls["0:attenuation"].select(0);controls["0:attenuation"].item_selected.emit(0)
	controls["0:scale"].value=2.0;controls["0:position"].value=-2.0
	controls["1:scale"].value=0.5;controls["1:position"].value=1.5
	for i in 300:system.bench.step(.0005)
	system.states[0]=system.bench.snapshot();system.ui.refresh()
	await process_frame;await process_frame
	check(panel.metrics.text.contains("CH1") and panel.metrics.text.contains("CH2"),"readouts show both real channels")
	check(panel.trace.channel_segments(0)!=panel.trace.channel_segments(1),"channel geometry uses independent samples/settings")
	check(system.errors.is_empty(),"all widget commands valid")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact("independent-scope.png"))
		print("SCOPE_RENDERED_CAPTURE ",artifact("independent-scope.png"))
	check(system.ui.channels_text.size()==3 and system.ui.readout!=null and system.ui.wiring!=null,"legacy supply/meter/leads UI retained")
	system.ui.close();system.queue_free();await process_frame
	print("SCOPE_CONTROLS_RESULT assertions=",assertions," failures=",failures," display=",DisplayServer.get_name())
	quit(1 if failures else 0)
