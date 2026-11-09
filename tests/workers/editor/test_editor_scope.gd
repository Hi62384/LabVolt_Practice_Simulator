extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")
const Capture=preload("res://scripts/analyzer/capture.gd")
var failures := 0
var checks := 0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func source() -> Dictionary:
	var board := Board.empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}];return board
func package() -> Dictionary:
	var board := source();var bp := Board.blueprint(board,"Probe package")
	bp.package="PCB";bp.layout={"rows":board.rows,"parts":board.parts.duplicate(true),"wires":[]}
	bp.footprint={"width":8,"height":6,"color":"24775b","body_height_mm":3.0,"thickness_mm":1.6}
	bp.pins=[{"id":"power","name":"IN","node":"L1","position":{"x":0,"y":0},"role":"power","connector":"terminal_block"},{"id":"return","name":"GND","node":"R1","position":{"x":2,"y":5},"role":"ground","connector":"test_point"}]
	return bp
func run() -> void:
	var bp := package();var defs := {"ic:probe":bp}
	check(Custom.validate("ic:probe",defs)=="","extended package valid")
	var board := Board.empty();board.definitions=defs
	var holes := Geometry.holes_at(bp,"A1",30)
	check(holes==["A1","F3"],"saved physical pin pitch used")
	board.parts=[{"id":"p","type":"ic:probe","a":holes[0],"b":holes[-1],"pins":holes}]
	check(Board.validate(board,{},true)=="","physical package mounts")
	var canvas=load("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas);canvas.board=board;canvas.selected=["p"]
	canvas.transform_selected(8,0);canvas.transform_selected(0,0,true)
	check(Board.validate(canvas.board,{},true)=="" and canvas.board.parts[0].pins==["A9","C4"],"rotated footprint and positions valid")
	var mismatch := board.duplicate(true);mismatch.parts[0].pins[1]="F2"
	check(Board.validate(mismatch,{},true).contains("physical"),"misaligned pitch rejected")
	var overlap := board.duplicate(true);overlap.parts.append({"id":"r2","type":"r1000","a":"B2","b":"G2"})
	check(Board.validate(overlap,{},true).contains("overlap"),"body occupancy enforced")
	var bad := bp.duplicate(true);bad.pins[1].position={"x":0,"y":0}
	check(Custom.validate("ic:bad",{"ic:bad":bad}).contains("overlap"),"duplicate physical pins rejected")
	bad=bp.duplicate(true);bad.pins[1].position.x=.5
	check(Custom.validate("ic:bad",{"ic:bad":bad}).contains("grid"),"fractional pin spacing rejected")
	bad=bp.duplicate(true);bad.footprint.thickness_mm=NAN
	check(Custom.validate("ic:bad",{"ic:bad":bad})!="","NaN thickness rejected")
	bad=bp.duplicate(true);bad.pins[1].id="power"
	check(Custom.validate("ic:bad",{"ic:bad":bad}).contains("IDs"),"duplicate stable IDs rejected")
	bad=bp.duplicate(true);bad.pins[0]=null
	check(Custom.validate("ic:bad",{"ic:bad":bad})!="","malformed pins rejected without indexing failure")
	bad=bp.duplicate(true);bad.io_controls={"r":"invalid"}
	check(Custom.validate("ic:bad",{"ic:bad":bad})!="","malformed optional packaged I/O state rejected")
	var large := bp.duplicate(true);large.footprint.width=80;large.footprint.height=80;large.pins=[]
	for i in 64:large.pins.append({"id":"p%d"%i,"name":"Pin%d"%i,"node":"L1" if i%2==0 else "R1","position":{"x":i,"y":0}})
	check(Custom.validate("ic:large",{"ic:large":large})=="","64-pin oversized package definition accepted")
	var standalone := Board.standalone("ic:large",{"ic:large":large})
	check(Board.validate(standalone,{},true)=="","64-pin standalone has unique legal board nodes")
	check(Board.expand(standalone).wires.has(["X64","board/R24"]),"64th external pin maps to actual circuit node")
	var legacy := bp.duplicate(true)
	for pin in legacy.pins:pin.erase("position");pin.erase("id");pin.erase("role");pin.erase("connector")
	legacy.footprint.erase("body_height_mm");legacy.footprint.erase("thickness_mm")
	check(Custom.validate("ic:old",{"ic:old":legacy})=="","legacy package schema remains valid")
	var station=load("res://scripts/dc_station.gd").new()
	var circuit := source();circuit.parts.append({"id":"battery","type":"battery","a":"B1","b":"G1"})
	check(station.apply({"op":"board","design":circuit})=="","actual solved board accepted")
	station.step()
	var measured := Capture.differential(station.result,"board/L1","board/R1")
	check(measured.ok and absf(float(measured.value)-5.0*1000/1001)<1e-6,"differential measurement agrees with independent resistor/source solution")
	check(not Capture.differential(station.result,"board/L1","B2").ok,"floating reference never produces voltage")
	check(not Capture.differential({"ok":false,"error":"singular"},"a","b").ok,"failed solver never produces voltage")
	var pwm_board := Board.empty()
	pwm_board.parts=[{"id":"battery","type":"battery","a":"B1","b":"G1"},{"id":"m","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","F1","A2","A3","F2","F3"],"firmware":"mode PWM out\npwm PWM 0.25\nwait 1000\ngoto 3"},{"id":"load","type":"r1000","a":"A4","b":"H1"}];pwm_board.wires=[["A4","G3"]]
	var pwm_station=load("res://scripts/dc_station.gd").new()
	check(pwm_station.apply({"op":"board","design":pwm_board})=="","firmware-driven PWM circuit accepted")
	var actual_capture := Capture.new();actual_capture.probes("board/R3","board/R1")
	for i in 501:pwm_station.step();actual_capture.ingest(pwm_station.result)
	var actual_stats := actual_capture.statistics()
	check(actual_stats.timing and absf(float(actual_stats.frequency)-50)<.2 and absf(float(actual_stats.duty)-.25)<.03,"analyzer resolves actual backend 50 Hz PWM driving a solved 1k load")
	var capture := Capture.new();capture.probes("a","b")
	for i in range(0,401):
		var t := i*.001
		capture.ingest({"ok":true,"time":t,"v":{"a":5.0 if i%100<25 else 0.0,"b":0.0},"islands":{"a":1,"b":1}})
	var stats := capture.statistics()
	check(stats.timing and absf(float(stats.frequency)-10)<.01 and absf(float(stats.duty)-.25)<.01,"sampled 10 Hz PWM frequency and 25 percent duty")
	check(absf(float(stats.mean)-1.25)<1e-8 and absf(float(stats.rms)-2.5)<1e-8,"time-weighted sampled mean and RMS")
	capture.ingest({"ok":true,"time":.4,"v":{"a":0,"b":0},"islands":{"a":1,"b":1}})
	check(capture.samples.size()==401,"duplicate solver timestamps ignored")
	capture.held=true;capture.ingest({"ok":true,"time":.5,"v":{"a":5,"b":0},"islands":{"a":1,"b":1}})
	check(capture.samples.size()==401,"capture hold preserves data")
	capture.held=false;capture.ingest({"ok":true,"time":.6,"v":{"a":0,"b":0},"islands":{"a":1,"b":2}})
	check(not capture.statistics().has("min"),"floating sample gap invalidates graph and timing")
	capture.ingest({"ok":true,"time":.001,"v":{"a":0,"b":0},"islands":{"a":1,"b":1}})
	check(capture.samples.size()==1,"solver clock reset clears old capture")
	capture.probes("c","b");check(capture.samples.is_empty(),"probe changes clear history")
	capture.probes("a","b")
	for i in 40:capture.ingest({"ok":true,"time":i*.01,"v":{"a":5 if i%2==0 else 0,"b":0},"islands":{"a":1,"b":1}})
	check(not capture.statistics().timing,"undersampled transitions do not claim timing resolution")
	capture.capacity=40
	capture.ingest({"ok":true,"time":.41,"v":{"a":0,"b":0},"islands":{"a":1,"b":1}})
	check(capture.samples.size()==40,"capture memory stays bounded")
	var shorted := source();shorted.wires=[["B1","G1"]]
	check(str(Capture.diagnostics(shorted,station.result,{},["r"])).contains("shorted"),"real jumper bypass diagnostic")
	check(str(Capture.diagnostics(source(),{"ok":true,"i":{"board/r":.02},"drop":{"board/r":20}}, {},["r"])).contains("rating"),"resistor dissipation overload from actual I times V")
	check(str(Capture.diagnostics(source(),{"ok":true,"i":{"board/r":0},"drop":{"board/r":5}}, {},["r"])).contains("open/off"),"voltage without conduction diagnostic")
	check(str(Capture.diagnostics(source(),{"ok":true,"mode":{"s0":"CC"}}, {},[])).contains("current limiting"),"authoritative current-limit state diagnostic")
	await persistence(bp)
	canvas.queue_free()
	print("EDITOR SCOPE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func persistence(bp: Dictionary) -> void:
	var profile=load("res://scripts/electronics_profile.gd").new();profile.open("worker-editor-"+str(Time.get_ticks_usec()))
	profile.data.kits[profile.data.equipped].board=source()
	var before: Dictionary=profile.data.duplicate(true)
	var options := bp.duplicate(true);options.erase("parts");options.erase("wires");options.erase("pins");options.erase("layout")
	var pins: Array=bp.pins.duplicate(true);pins[0].hole="A1";pins[1].hole="F1"
	var message := preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pins)
	check(message.begins_with("Blueprint saved:"),"extended save succeeds")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	var saved: Dictionary=parsed.blueprints.values()[0]
	check(saved.pins[0].id=="power" and saved.pins[0].connector=="terminal_block" and saved.footprint.thickness_mm==1.6,"metadata roundtrip through profile JSON")
	check(profile.data.dollars==before.dollars and profile.data.inventory==before.inventory,"package editing does not consume inventory or currency")
	var form=load("res://scripts/package_editor/package_form.gd").new();root.add_child(form);form.build(profile,saved)
	check(form.rows.size()==64 and form.rows[0].id=="power","saved pin metadata available for editing")
	form.swap(0,1,2);check(form.rows[0].id=="return" and form.rows[0].name.text=="GND","pin reorder retains stable identity and mapping")
	form.queue_free()
	var known: Dictionary=profile.data.duplicate(true);profile.path="user://missing-directory/cannot-save.json"
	options.name="Failing save"
	check(preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pins).contains("Save failed"),"failed persistence is reported")
	check(profile.data==known,"failed package save rolls back in-memory profile")

