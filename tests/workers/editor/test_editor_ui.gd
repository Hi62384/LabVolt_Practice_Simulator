extends SceneTree
var count := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	count+=1
	if not value:push_error(message);quit(1)
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	var ui=game.electronics
	ui.profile.open("editor-ui-"+str(Time.get_ticks_usec()))
	ui.open("board")
	check(not ui.canvas.analyzer_enabled,"ordinary board does not grant analyzer")
	ui.canvas.selected_type="probe+"
	var click := InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=ui.canvas.at("A1")
	ui.canvas._gui_input(click);ui.canvas._gui_input(click)
	check(ui.canvas.board.parts.is_empty() and ui.canvas.first=="","locked probe tool cannot place invalid components")
	ui.profile.data.kits.starter.board.parts=[{"id":"battery","type":"battery","a":"A1","b":"F1"},{"id":"load","type":"r1000","a":"B1","b":"G1"}]
	ui.open("design")
	check(ui.canvas.analyzer_enabled and not ui.profile.data.analyzer,"designer analyzer free without changing ownership")
	ui.canvas.selected_type="probe+";click.position=ui.canvas.at("A1");ui.canvas._gui_input(click)
	ui.canvas.selected_type="probe-";click.position=ui.canvas.at("F1");ui.canvas._gui_input(click)
	for i in 10:await process_frame
	check(ui.canvas.capture.positive=="board/L1" and ui.canvas.capture.negative=="board/R1","click probes map physical holes to electrical strips")
	check(ui.canvas.capture.samples.size()>2,"preview captures actual solver steps")
	ui.canvas.selected=["load"]
	check(ui.canvas.inspection_text().contains("1000") and ui.canvas.inspection_text().contains("instantaneous"),"component inspector exposes model and measured pin values")
	ui.canvas.timing_visible=true
	check(ui.canvas.custom_minimum_size.y==590,"trace reserves space below physical board")
	ui.canvas.board.parts.append({"id":"m","type":"lv_mcu","a":"A5","b":"F7","pins":["A5","A6","A7","F5","F6","F7"]})
	ui.canvas.selected=["m"];ui.canvas.device_states["board/m"]={"powered":true,"modes":{"D0":"out"},"outputs":{"D0":.5},"time":1.0,"status":"Waiting","line":4}
	check(ui.canvas.inspection_text().contains("high impedance") and ui.canvas.inspection_text().contains("0.500"),"known LV drive mode and PWM command reported from backend state")
	ui.open("ics")
	check(not ui.profile.data.analyzer,"package editor leaves permanent analyzer purchase unchanged")
	print("EDITOR UI: %d checks passed"%count);quit()
