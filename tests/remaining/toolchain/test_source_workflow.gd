extends SceneTree
const Request=preload("res://scripts/firmware_toolchain/source_request.gd")
const Diagnostics=preload("res://scripts/firmware_toolchain/diagnostics.gd")
const Artifact=preload("res://scripts/firmware_toolchain/artifact.gd")
const Document=preload("res://scripts/firmware_backends/program_document.gd")
const Source=preload("res://scripts/firmware_backends/source_project.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("TOOLCHAIN FAIL: "+label)
	else:print("TOOLCHAIN PASS: "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var files := {"sketch.ino":"void setup() {}\nvoid loop() {}\n","pins.h":"#define LED 13\n"}
	var request := {"schema":1,"board":"uno","language":"arduino_cpp","entry":"sketch.ino","files":files}
	check(Request.validate(request).ok,"Bounded Arduino source project accepted")
	for name in ["../escape.cpp","C:/secret.cpp","\\host\\share.cpp","CON.cpp","NUL.h","a..cpp",".hidden.cpp"]:
		check(not Request.name_ok(name),"Reject unsafe Windows filename "+name)
	var case_request := request.duplicate(true);case_request.files["SKETCH.INO"]=""
	check(not Request.validate(case_request).ok,"Case-insensitive duplicate files rejected")
	var hostile := request.duplicate(true);hostile.executable="cmd.exe"
	check(not Request.validate(hostile).ok,"No guest executable option accepted")
	hostile=request.duplicate(true);hostile.arguments=["-fplugin=bad.dll"]
	check(not Request.validate(hostile).ok,"No guest compiler flags accepted")
	hostile=request.duplicate(true);hostile.files["large.cpp"]="x".repeat(65537)
	check(not Request.validate(hostile).ok,"Per-file UTF8 byte bound enforced")
	check(Request.source_hash(files)==Request.source_hash({"pins.h":files["pins.h"],"sketch.ino":files["sketch.ino"]}),"Source revision hash independent of map insertion order")
	check(not Source.native_request("uno",files,"absent.cpp").ok,"Missing entry rejected")
	check(Source.build({"main.lvs":"mode D0 out\nwrite D0 1\nhalt"}).ok,"Existing LVScript source API preserved")
	var diagnostic := Diagnostics.parse("C:\\jobs\\src\\sketch.ino:3:9: error: expected ';'\nC:/private/path/sdk.h:7: warning: core warning",files)
	check(diagnostic.size()==2 and diagnostic[0].file=="sketch.ino" and int(diagnostic[0].line)==3 and int(diagnostic[0].column)==9,"GCC diagnostics preserve source location")
	check(diagnostic[1].file=="<toolchain>","Host dependency paths redacted from source diagnostics")
	var firmware := {"schema":1,"board":"uno","format":"intel_hex","image":":020000000000FE\n:00000001FF"}
	var map := [{"file":"sketch.ino","line":2,"pc":12},{"file":"sketch.ino","line":2,"pc":14}]
	var result := {"ok":true,"firmware":firmware,"source_map":map,"artifact":{"source_sha256":Request.source_hash(files)}}
	check(Artifact.validate(result,"uno",files).ok,"Compiler artifact uses existing machine image validation")
	check(not Artifact.validate(result,"pico",files).ok,"Board-mismatched compiler artifact rejected")
	check(not Artifact.validate(result,"uno",{"sketch.ino":"changed"}).ok,"Stale source/image revision rejected")
	var invalid_map := result.duplicate(true);invalid_map.source_map[0].pc={"bad":true}
	check(not Artifact.validate(invalid_map,"uno",files).ok,"Malformed source map fails without converting arbitrary types")
	invalid_map=result.duplicate(true);invalid_map.source_map[0].pc=32768
	check(not Artifact.validate(invalid_map,"uno",files).ok,"Source PC outside actual Uno flash rejected")
	check(Diagnostics.addresses(map,"sketch.ino",2)==[12,14],"Source line maps to actual byte-PC breakpoint addresses")
	Document.save_compiler_map("uno",firmware,files,map)
	check(Document.load_compiler_map("uno",firmware,files)==map,"Source map persists for exact source/image revision")
	check(Document.load_compiler_map("uno",firmware,{"sketch.ino":"changed"}).is_empty(),"Changed source cannot reuse old line map")
	var design := {"programs":{"board/a":{"run":false,"custom_metadata":"keep"}}}
	Document.store(design,"board/a",firmware,files)
	check(design.programs["board/a"].run==false and design.programs["board/a"].custom_metadata=="keep","Existing program persistence preserves run/metadata")
	var ide := preload("res://scripts/firmware_backends/native_ide.gd").new();root.add_child(ide);ide.build("uno",firmware,files)
	check(ide.editors.size()==2 and ide.compile_button.text=="Compile source","Native editor exposes actual compile workflow")
	check(ide.program()==firmware and ide.source_files()==files,"Existing saved image/source round trip unchanged")
	ide.compile_finished({"ok":false,"status":"sandbox_unavailable","error":"CreateAppContainerProfile 0x80070005","diagnostics":diagnostic})
	check(ide.image.text==firmware.image and "sandbox_unavailable" in ide.status.text,"Blocked compiler preserves prior validated image")
	ide.select_diagnostic(0)
	check(ide.active_editor()==ide.editors["sketch.ino"],"Selecting source diagnostic navigates correct file")
	var commands: Array=[];ide.control_requested.connect(func(command):commands.append(command))
	ide.editors["sketch.ino"].set_caret_line(1);ide.breakpoint_at_source()
	check(commands.size()==1 and commands[0].breakpoints==[12,14],"Source breakpoint emits existing byte-PC control API")
	ide.image.text=":020000000100FD\n:00000001FF";ide.breakpoint_at_source()
	check(commands.size()==1,"Imported different image cannot reuse prior source addresses")
	var saved: Array=[];ide.draft_requested.connect(func(draft):saved.append(draft))
	ide.autosave_left=.1;ide._process(.2)
	check(saved.size()==1 and saved[0]==files,"Native source autosave uses preserved draft persistence signal")
	ide.free()
	var micropython := {"schema":1,"board":"pico","language":"micropython","entry":"main.py","files":{"main.py":"print(1)"}}
	check(Request.validate(micropython).status=="runtime_unavailable","MicroPython execution never masquerades as supported machine firmware")
	print("TOOLCHAIN_RESULT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
