extends SceneTree
const Persistent=preload("res://scripts/inventory_authority/component_persistence.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const IO=preload("res://scripts/inventory_authority/io_control_schema.gd")
var checks := 0
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:push_error("FAIL "+label);quit(1);assert(false,label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var memory := {}
	for address in 32768:memory[str(address)]=address%256
	var runtime := {"board/socket/memory":{"schema":1,"model":"eeprom25","memory":memory,"status":140}}
	check(Persistent.valid(runtime),"full 32 KiB EEPROM fits bounded envelope")
	check(Persistent.valid(JSON.parse_string(JSON.stringify(runtime))),"JSON numeric round trip")
	check(Persistent.valid({}),"old saves empty default")
	for bad in [{"-1":0},{"32768":0},{"01":0},{"0":256},{"0":-1},{"0":"255"}]:
		check(not Persistent.valid({"device":{"schema":1,"model":"eeprom25","memory":bad,"status":0}}),"invalid EEPROM memory rejected")
	var restored := Persistent.restore(runtime)
	check(restored["board/socket/memory"].memory["32767"]==255,"restore bytes")
	check(restored["board/socket/memory"].status==140 and not restored["board/socket/memory"].has("powered"),"restore excludes volatile protocol state")
	var root_path := "user://memory_unit_"+Crypto.new().generate_random_bytes(6).hex_encode()
	var p=Profile.new();p.open(root_path)
	var ledger=Ledger.new();check(ledger.open(root_path)==OK,"ledger")
	check(ledger.bind(1,"a".repeat(48),"1".repeat(64),p.data).ok,"source")
	check(ledger.bind(2,"b".repeat(48),"2".repeat(64),p.data).ok,"destination")
	# This is a serializer/ownership fixture on an existing stock type. EEPROM
	# electrical behavior belongs to the separately tested models worker.
	var board := Board.empty();board.parts=[{"id":"socket","type":"r1000","a":"A1","b":"F1"}]
	check(ledger.deploy(1,0,board)=="","reserve physical carrier")
	memory["17"]=123;memory["32767"]=42
	var states := {"board/socket/memory":{"memory":memory,"status":140,"powered":true,"command":3,"bits":8,"serial":1}}
	check(ledger.capture_components(1,board,states)=="","host snapshot retains physical state")
	check(ledger.account(1).profile.component_instances.size()==1,"one physical identity")
	var identity: String=ledger.account(1).profile.component_instances.keys()[0]
	check(identity in ledger.account(1).deployment.instance_ids,"deployed record reserved")
	check(ledger.exchange("generic-stock",[1,2],{1:{"r1000":1},2:{}},{}).ok,"undeployed generic unit trade")
	check(ledger.account(1).profile.component_instances.has(identity) and ledger.account(2).profile.component_instances.is_empty(),"deployed memory cannot transfer with generic stock")
	check(ledger.recall(1),"recall stateful unit")
	var selections := {1:{identity:ledger.instance_hash(ledger.account(1).profile.component_instances[identity])},2:{}}
	check(not ledger.exchange("changed-review",[1,2],{1:{"r1000":1},2:{}},{},{1:{identity:"changed"},2:{}}).ok,"changed reviewed physical state rejected")
	check(ledger.exchange("memory-transfer",[1,2],{1:{"r1000":1},2:{}},{},selections).ok,"reviewed physical memory transfer")
	check(not ledger.account(1).profile.component_instances.has(identity) and ledger.account(2).profile.component_instances.has(identity),"exactly one owner")
	check(ledger.account(2).profile.component_instances[identity].component_runtime["board/socket/memory"].memory["17"]==123,"byte transfer")
	check(ledger.exchange("memory-transfer",[1,2],{1:{"r1000":1},2:{}},{}).ok and ledger.account(2).profile.component_instances.size()==1,"idempotent instance transfer")
	var other := Board.empty();other.parts=[{"id":"new_root","type":"r1000","a":"A1","b":"F1"}]
	var deployed: Dictionary=ledger.materialize(2,other)
	check(deployed.component_runtime["board/new_root/memory"].memory["32767"]==42,"recursive stable ID rebase")
	check(ledger.materialize(1,board).component_runtime.is_empty(),"stale donor template cannot clone transferred memory")
	p.data=ledger.account(2).profile.duplicate(true);check(p.save()==OK,"local persistent profile write")
	var reloaded=Profile.new();reloaded.open(root_path)
	check(Profile.same(reloaded.data.component_instances[identity].component_runtime,p.data.component_instances[identity].component_runtime),"profile reload exact bytes")
	var restarted=Ledger.new();check(restarted.open(root_path)==OK,"host restart")
	check(restarted.bind(3,"b".repeat(48),"2".repeat(64),p.data).ok and restarted.account(3).profile.component_instances.has(identity),"reconnect persistent identity")
	var inputs := [{"id":"e","type":"io_encoder"},{"id":"k","type":"io_keypad"},{"id":"s","type":"io_slider"},{"id":"j","type":"io_joystick"},{"id":"p","type":"io_selector"}]
	var controls := {"board/e":{"revision":1,"detent":-5},"board/k":{"revision":2,"keys":4095},"board/s":{"revision":0,"x":.25},"board/j":{"revision":0,"x":.1,"y":.9,"pressed":true},"board/p":{"revision":0,"position":2}}
	check(IO.valid(controls,inputs,{}),"IO worker v1 input envelope")
	check(IO.valid(JSON.parse_string(JSON.stringify(controls)),inputs,{}),"IO JSON profile numbers")
	for entry in [{"revision":-1},{"keys":4096},{"keys":1.5},{"runtime":{}},{"framebuffer":[]},{"keys":NAN}]:
		check(not IO.valid({"board/k":entry},inputs,{}),"IO invalid field/range/runtime rejected")
	check(not IO.valid({"board/missing":{"x":.5}},inputs,{}),"IO unknown identity rejected")
	var definitions := {"ic:io":{"parts":inputs}}
	check(IO.valid({"module/s":{"revision":0,"x":.5}},[{"id":"module","type":"ic:io"}],definitions,""),"package relative ID contract")
	print("PASS component/IO persistence: %d checks"%checks);quit()
