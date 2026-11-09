extends SceneTree
var dashboard: Control
var adapter: RefCounted
var failures := 0
func artifact_path(name: String) -> String:
	var directory := OS.get_environment("LABVOLT_UI_ARTIFACTS")
	if directory.is_empty(): directory=OS.get_user_data_dir().path_join("ui-test-artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join(name)
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new(); move.position=point; root.push_input(move,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)
	await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new(); event.keycode=code; event.pressed=pressed; root.push_input(event,true)
	await process_frame
func choose(control: OptionButton,index: int) -> void:
	control.grab_focus()
	await key(KEY_SPACE)
	var distance := index-control.selected
	for i in absi(distance): await key(KEY_DOWN if distance>0 else KEY_UP)
	await key(KEY_ENTER)
	await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	adapter=load("res://tests/campus/ui/ui_fixture_adapter.gd").new()
	dashboard=load("res://scripts/campus/ui/campus_dashboard.gd").new(); root.add_child(dashboard); dashboard.build(adapter)
	await process_frame; await process_frame
	var options := dashboard.find_children("*","OptionButton",true,false)
	check(options.size()>=6,"selectors built")
	await choose(options[1],1)
	check(dashboard.course_id=="ETY155","actual course selector click")
	options=dashboard.find_children("*","OptionButton",true,false)
	await choose(options[2],1)
	check(dashboard.kind=="lab","actual lab selector click")
	options=dashboard.find_children("*","OptionButton",true,false)
	await choose(options[3],11)
	check(dashboard.week==12,"actual week selector click")
	await choose(options[4],4)
	check(dashboard.difficulty==4,"actual difficulty selector click")
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact_path("dashboard-courses.png"))
	for button in dashboard.find_children("*","Button",true,false):
		if button.text=="Start selected activity":
			dashboard.tabs.get_child(0).ensure_control_visible(button); await process_frame; await process_frame
			await click(button); break
	check(adapter.requested.get("course_id")=="ETY155" and adapter.requested.get("week")==12 and adapter.requested.get("difficulty")==4,"start sends selected config")
	dashboard.tabs.current_tab=1
	await process_frame; await process_frame
	var search: LineEdit=dashboard.find_children("*","LineEdit",true,false)[0]
	search.grab_focus()
	for unicode_value in [77,49,48,50]:
		var event := InputEventKey.new(); event.unicode=unicode_value; event.pressed=true; root.push_input(event,true)
		await process_frame
	check(search.text=="M102","directory search actual keyboard input")
	for button in dashboard.find_children("*","Button",true,false):
		if button.text.begins_with("M102"): await click(button); break
	check(adapter.target=="shop","directory selects real central room ID")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact_path("dashboard-directory.png"))
	print("UI_DASHBOARD_INTERACTION_RESULT failures=",failures," renderer=",DisplayServer.get_name())
	dashboard.queue_free(); await process_frame
	quit(1 if failures else 0)
