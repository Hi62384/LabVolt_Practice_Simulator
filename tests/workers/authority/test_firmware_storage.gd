extends SceneTree
const Schema=preload("res://scripts/inventory_authority/firmware_schema.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var checks := 0
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:push_error("FAIL "+label);quit(1);assert(false,label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var uno := {"schema":1,"board":"uno","format":"intel_hex","image":":00000001FF"}
	check(Schema.record(uno),"UNO HEX envelope")
	for extra in ["node_executable","backend_directory","pid","process_handle","native_runtime"]:
		var injected := uno.duplicate(true);injected[extra]="untrusted"
		check(not Schema.record(injected),"host capabilities rejected")
	for image in [":00000001FE",":0100000000FE\n:00000001FF",":00000001FF\n:00000001FF","not hex","0".repeat(131073)]:
		var bad := uno.duplicate(true);bad.image=image;check(not Schema.record(bad),"bad checksum/EOF/format/quota")
	var bytes := PackedByteArray();bytes.resize(264);bytes.encode_u32(256,0x20041000);bytes.encode_u32(260,0x10000001)
	var pico := {"schema":1,"board":"pico","format":"bin_base64","image":Marshalls.raw_to_base64(bytes),"vector_offset":256}
	check(Schema.record(pico),"Pico flash/vector envelope")
	pico.vector_offset=257;check(not Schema.record(pico),"Pico vector bounds");pico.vector_offset=256
	bytes.encode_u32(260,0x10000000);pico.image=Marshalls.raw_to_base64(bytes);check(not Schema.record(pico),"Pico Thumb vector required")
	check(Schema.files({"main.lvs":"mode D0 out\nwrite D0 1","library.lvs":"halt"},true),"LV source tabs")
	check(not Schema.files({"../escape.lvs":"halt"},true),"LV paths rejected")
	check(not Schema.files({"main.lvs":"x".repeat(8193)},true),"LV source total quota")
	check(Schema.files({"sketch.ino":"void setup() {}","library.h":"// source"},false),"native source tabs")
	check(not Schema.files({"sketch.ino":"x".repeat(65537)},false),"native per-file quota")
	check(not Schema.part({"native_firmware":uno,"node_executable":"untrusted"}),"part cannot configure host Node")
	var p=Profile.new();p.open("native-storage-"+Crypto.new().generate_random_bytes(5).hex_encode())
	# Save-layer fixture only; does not register a native board in the shared catalog.
	p.data.kits.starter.board.parts=[{"id":"carrier","type":"r1000","a":"A1","b":"F1","native_firmware":uno,"native_sources":{"sketch.ino":"void setup() {}"},"code_files":{"main.lvs":"halt"}}]
	check(p.save_blueprint("Native storage fixture").begins_with("Blueprint saved:"),"packaging optional firmware/source fields")
	var id: String=p.data.blueprints.keys()[0]
	check(p.data.blueprints[id].parts[0].native_firmware==uno and p.data.blueprints[id].parts[0].code_files["main.lvs"]=="halt","electrical package metadata preserved")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(p.path))
	check(Profile.valid(parsed) and Profile.same(parsed.blueprints[id].parts[0].native_firmware,uno),"JSON reload native firmware schema")
	var pins := [{"name":"signal","hole":"A1","id":"signal-id","role":"input","connector":"test_point","position":{"x":0,"y":0}},{"name":"ground","hole":"F1","id":"ground-id","role":"ground","connector":"female_header","position":{"x":0,"y":1}}]
	check(p.save_blueprint("Package contract",pins,"","IC",8,6,"24775b",[],{"body_height_mm":2.5,"marking":"Unit","orientation_marker":"notch"}).begins_with("Blueprint saved:"),"editor optional metadata save interface")
	var packaged: Dictionary=p.data.blueprints.values().filter(func(bp):return bp.name=="Package contract")[0]
	check(packaged.pins[0].id=="signal-id" and packaged.pins[1].id=="ground-id" and packaged.pins[0].position.y==0 and packaged.footprint.body_height_mm==2.5,"pin array order and physical metadata preserved")
	var shape=load("res://scripts/inventory_authority/validation.gd")
	var bad_package := packaged.duplicate(true);bad_package.pins[1].id="signal-id"
	check(not shape.package_metadata(bad_package),"duplicate pin ID rejected")
	bad_package=packaged.duplicate(true);bad_package.pins[1].erase("position")
	check(not shape.package_metadata(bad_package),"partial pin position map rejected")
	bad_package=packaged.duplicate(true);bad_package.footprint.body_height_mm=NAN
	check(not shape.package_metadata(bad_package),"nonfinite physical metadata rejected")
	var ledger=load("res://scripts/inventory_authority/ledger.gd").new()
	check(ledger.open(p.path+"-ledger")==OK,"native transfer ledger")
	p.data.inventory[id]=1
	var receiver=Profile.new();receiver.open("native-recipient-"+Crypto.new().generate_random_bytes(5).hex_encode())
	check(ledger.bind(1,"a".repeat(48),"1".repeat(64),p.data).ok and ledger.bind(2,"b".repeat(48),"2".repeat(64),receiver.data).ok,"native storage profiles")
	check(ledger.exchange("native-transfer",[1,2],{1:{id:1},2:{}},p.data.blueprints).ok,"native firmware/source blueprint trade")
	check(Profile.same(ledger.account(2).profile.blueprints[id].parts[0].native_firmware,uno) and ledger.account(2).profile.blueprints[id].parts[0].native_sources["sketch.ino"]=="void setup() {}","native image/source bytes transferred")
	print("PASS optional firmware storage: %d checks"%checks);quit()
