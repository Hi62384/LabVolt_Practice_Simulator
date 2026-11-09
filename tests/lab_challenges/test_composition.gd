extends SceneTree
var assertions := 0
var failures := 0
const Catalog = preload("res://scripts/lab_challenges/scenario_catalog.gd")
func _initialize() -> void:call_deferred("run")
func check(ok: bool,msg: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(msg)
func station() -> RefCounted:
	var original: RefCounted=preload("res://scripts/lab_state.gd").new()
	if original.get_property_list().any(func(property):return property.name=="protective_earth_profile"):return original
	var script := GDScript.new()
	script.source_code="extends \"res://scripts/lab_state.gd\"\nvar protective_earth_profile: Dictionary={}\nvar external_connections := 0\nfunc protective_earth_recovery() -> Dictionary:return protective_earth_profile.duplicate(true)\n"
	if script.reload()!=OK:return null
	return script.new()
func run() -> void:
	var state := station();check(state!=null,"PE composition API available without editing shared source")
	state.initialize(preload("res://tests/fixture.gd").ids(),preload("res://tests/fixture.gd").locations())
	var profile := preload("res://scripts/electronics_profile.gd").new();profile.open("pe-challenge-composition-fixture")
	profile.data.erase("dorm") # Let enrollment create a separate room for each fixture identity.
	var ledger := preload("res://scripts/inventory_authority/ledger.gd").new();check(ledger.open("user://composition_"+Crypto.new().generate_random_bytes(5).hex_encode())==OK,"composition ledger")
	var owner: Dictionary=ledger.bind(1,"1".repeat(48),"3".repeat(64),profile.data)
	var guest: Dictionary=ledger.bind(2,"2".repeat(48),"4".repeat(64),profile.data)
	if not owner.ok or not guest.ok:
		push_error("Composition fixture could not enroll both players.")
		quit(1)
		return
	var host := preload("res://scripts/lab_challenges/host.gd").new();host.store.ledger=ledger;host.labs=[state]
	host.store.authority=func():return true
	host.allowed=func(_peer,_bench,_command):return true
	var generation: int=ledger.store.generation;var before: Dictionary=state.snapshot()
	state.protective_earth_profile={"enabled":false}
	var result: Dictionary=host.act(1,0,{"command":"start","kind":"open_phase","seed":1})
	check(not result.ok and result.error.contains("protective-earth"),"start requires EMPTY PE demo profile, even when disabled")
	check(ledger.store.generation==generation and state.snapshot()==before and not state.protective_earth_profile.is_empty(),"rejected start changes neither journal nor demonstration/circuit")
	check(not host.act(1,0,{"command":"start","kind":"open_phase","seed":1,"protective_earth_profile":{}}).ok,"client cannot send an arbitrary PE profile or clear instruction")
	state.protective_earth_profile={};state.external_connections=1
	check(not host.act(1,0,{"command":"start","kind":"open_phase","seed":1}).ok,"external bench dependencies cannot silently change isolated scenario baseline")
	state.external_connections=0
	var started: Dictionary=host.act(1,0,{"command":"start","kind":"open_phase","seed":1})
	check(started.ok,"empty PE/isolated baseline allows genuine challenge")
	host.recover_journal();var active: Dictionary=host.store.root();generation=ledger.store.generation
	state.protective_earth_profile={"enabled":true}
	check(not host.act(1,0,{"command":"resume","attempt_id":started.attempt_id}).ok,"resume also rejects nonempty PE demo profile")
	check(ledger.store.generation==generation and host.store.root()==active and state.protective_earth_profile.enabled,"rejected resume preserves attempt/proofs and PE demo")
	var objective := preload("res://scripts/lab_challenges/objectives.gd").evaluate(state,Catalog.generate("open_phase",1))
	check(not objective.ok and objective.measurements.is_empty(),"completion refuses changed PE baseline rather than inventing replacement readings")
	state.protective_earth_profile={};state.powered=true
	check(not host.act(1,0,{"command":"resume","attempt_id":started.attempt_id}).ok,"host must deenergize before restoring any scenario")
	state.powered=false
	check(host.act(1,0,{"command":"resume","attempt_id":started.attempt_id}).ok,"trusted cleared/deenergized baseline can resume same attempt")
	var school: Node=load("res://scripts/school_session.gd").new()
	var bridge: Node=load("res://scripts/lab_challenges/bridge.gd").new()
	var game_script := GDScript.new();game_script.source_code="extends Node\nvar school: Node\n";check(game_script.reload()==OK,"minimal immutable-school consumer fixture")
	var game: Node=game_script.new();game.school=school;bridge.game=game
	school.mode="Class";school.class_students={"enrolled":{"done":false}};school.activity={}
	for phase in ["travel","lesson","assignment"]:
		school.phase=phase;check(school.formal_active() and bridge._formal_class(),"actual School.formal_active authority respected for legacy "+phase)
	school.phase="complete";check(not bridge._formal_class(),"actual completed class releases formal guard")
	bridge.free();game.free();school.free()
	print("BASE_COMPOSITION_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
