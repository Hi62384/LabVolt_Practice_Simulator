extends SceneTree
const Document=preload("res://scripts/firmware_backends/program_document.gd")
const Metadata=preload("res://scripts/firmware_backends/pin_metadata.gd")
var fails := 0
func check(ok: bool,message: String) -> void:
 print("PASS " if ok else "FAIL ",message)
 if not ok:fails+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var image := {"schema":1,"board":"uno","format":"intel_hex","image":FileAccess.get_file_as_string("res://assets/workers/firmware/uno-toggle.hex")}
 check(Document.validate("uno",image,{"Blink.ino":"void loop() {}"}).ok,"valid Uno document")
 check(not Document.validate("pico",image,{}).ok,"cross-board image rejected")
 var corrupt := image.duplicate();corrupt.image=":0000000100"
 check(not Document.validate("uno",corrupt,{}).ok,"bad image checksum rejected before save")
 check(not Document.validate("uno",image,{"../host.h":"x"}).ok,"source traversal rejected")
 var design := {"programs":{"board/a":{"run":false,"firmware":"legacy"}}}
 Document.store(design,"board/a",image,{"main.cpp":"first"});Document.store(design,"board/nested/a",image,{"main.cpp":"second"})
 image.image="mutated"
 check(design.programs["board/a"].native_firmware.image!="mutated" and not design.programs["board/a"].run,"store copies program and preserves run/legacy fields")
 var restored: Dictionary=JSON.parse_string(JSON.stringify(design))
 check(restored.programs["board/nested/a"].native_sources["main.cpp"]=="second" and restored.programs["board/a"].native_sources["main.cpp"]=="first","nested per-device JSON isolation")
 var oversized := {}
 for i in 13:oversized["file%d.cpp"%i]="x".repeat(65536)
 var valid_image: Dictionary=design.programs["board/a"].native_firmware
 check(Document.validate("uno",valid_image,oversized).ok and not Document.validate("uno",valid_image,oversized,true).ok,"save limit differs truthfully from 768 KiB live limit")
 check(Metadata.pins("pico").size()==40 and Metadata.pins("pico")[34].label=="ADC_VREF","Pico physical header metadata")
 var report=preload("res://scripts/firmware_backends/native_host_config.gd").dependency_report()
 check(report.runtime_ready and not report.compiler_enabled,"trusted local runtime discovered without guest configuration")
 var report_file := FileAccess.open("user://native-dependency-report.json",FileAccess.WRITE);report_file.store_string(JSON.stringify(report,"  "));report_file.close()
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var kit: Dictionary=game.electronics.profile.data.kits.starter
 kit.board.rows=40
 var first_pins: Array=[];var second_pins: Array=[]
 for i in 32:first_pins.append("A"+str(i+1));second_pins.append("B"+str(i+1))
 kit.board.parts=[{"id":"uno","type":"native_uno","a":"A1","b":"A32","pins":first_pins},{"id":"second","type":"native_uno","a":"B1","b":"B32","pins":second_pins}]
 check(preload("res://scripts/electronics_profile.gd").valid(game.electronics.profile.data),"test fixture is a valid persistent board")
 game.electronics.open("code")
 for i in 3:await process_frame
 var legacy=game.electronics.body.get_child(0)
 var studio=legacy.get_child(0)
 check(studio.device=="board/uno" and studio.editor.board=="uno","normal Code page opens actual native board editor")
 studio.editor.image.text=valid_image.image
 check(studio.editor.validate_program(),"native editor validates actual image")
 studio.editor.save_requested.emit(studio.editor.program(),{"sketch.ino":"uno source"})
 studio.select({"id":"board/second","board":"uno"})
 studio.editor.draft_requested.emit({"main.cpp":"second draft"})
 kit=game.electronics.profile.data.kits.starter
 check(kit.board.programs["board/uno"].native_sources["sketch.ino"]=="uno source" and kit.board.programs["board/second"].native_sources["main.cpp"]=="second draft","selection callbacks persist the correct device")
 studio.select({"id":"board/uno","board":"uno"})
 check(studio.editor.editors["sketch.ino"].text=="uno source","reselect restores source and image")
 studio.editor.set_snapshot({"cycles":1,"serial":[{"port":0,"value":65}],"status":"Running"})
 studio.editor.set_snapshot({"cycles":1,"serial":[{"port":0,"value":65}],"status":"Running"})
 studio.editor.set_snapshot({"cycles":2,"serial":[{"port":0,"value":66}],"status":"Running"})
 check(studio.editor.serial_history.size()==2,"UART history survives deltas without duplicate snapshot bytes")
 game.electronics.close();game.queue_free();await process_frame
 print("NATIVE CAMPUS FAILURES: ",fails);quit(fails)
