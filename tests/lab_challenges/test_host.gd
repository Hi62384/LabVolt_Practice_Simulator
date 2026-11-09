extends SceneTree
const Host = preload("res://scripts/lab_challenges/host.gd")
const Ledger = preload("res://scripts/inventory_authority/ledger.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const State = preload("res://scripts/lab_state.gd")
const Fixture = preload("res://tests/fixture.gd")
const Catalog = preload("res://scripts/lab_challenges/scenario_catalog.gd")
const Economy = preload("res://scripts/economy/temporary_playtest/policy.gd")
class SchoolFixture:
	extends Node
	var activity := {}
	var phase := "freeplay"
	var mode := "Freeplay"
	var class_students := {}
	func formal_active() -> bool:return mode=="Class" and phase in ["travel","lesson","assignment"] and not class_students.is_empty()
class SessionFixture:
	extends Node
	var roster := {1:{"name":"Student"}}
	var labs: Array=[]
	var poses := {}
	var academic_equipment_guard := Callable()
class GameFixture:
	extends Node
	var school: Node
	var session: Node
	var player: Node3D
	func _station_x(_bench: int) -> float:return 0.0
var host: RefCounted
var ledger: RefCounted
var state: RefCounted
var failures := 0
var assertions := 0
var identity_a := "a".repeat(48)
var identity_b := "b".repeat(48)
var position := Vector3(-4.2,0,-1.4)
func _initialize() -> void:call_deferred("run")
func check(ok: bool,msg: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(msg)
func electrical(peer: int,action: Dictionary) -> void:
	var before: Dictionary=state.snapshot();var error: String=state.act(peer,action,position,peer==1)
	check(error=="","real electrical action "+str(action)+" "+error)
	if error=="":host.observe(peer,0,action,before)
func configure_host() -> void:
	host=Host.new()
	host.store.ledger=ledger
	host.store.authority=func():return true
	host.labs=[state]
	host.allowed=func(peer,_bench,_command):return peer in ledger.bindings
	host.names=func(_peer):return "Duplicate"
	host.clock=func():return 1000
func perform(seed_value: int) -> String:
	var start: Dictionary=host.act(1,0,{"command":"start","kind":"power_factor","seed":seed_value})
	check(start.ok,"host starts genuine challenge "+str(start))
	if not start.ok:return ""
	var id: String=start.attempt_id
	check(not host.act(2,0,{"command":"submit","attempt_id":id,"measurements":{"p":100}}).ok,"client cannot supply completion readings")
	check(not host.act(2,0,{"command":"diagnose","attempt_id":id,"diagnosis":"missing_capacitor"}).ok,"diagnosis requires actual fault instrument record")
	electrical(1,{"op":"check"});electrical(1,{"op":"power"});electrical(2,{"op":"record"})
	check(host.store.root().active["0"].evidence[identity_b].measure_fault,"fault evidence comes from host instruments")
	check(not host.act(2,0,{"command":"diagnose","attempt_id":id,"diagnosis":"invented"}).ok,"wrong diagnosis rejected")
	var diagnosed: Dictionary=host.act(2,0,{"command":"diagnose","attempt_id":id,"diagnosis":"missing_capacitor"})
	check(diagnosed.ok,"diagnosis accepted from measured fault")
	check(not host.act(2,0,{"command":"submit","attempt_id":id}).ok,"diagnosis alone cannot satisfy actual repair and role proof")
	electrical(1,{"op":"power"})
	var plan := Catalog.generate("power_factor",seed_value)
	electrical(1,{"op":"switch","kind":"C","index":plan.element,"expected":false})
	check(host.store.root().active["0"].evidence[identity_a].repair,"repair role requires actual fault correction")
	electrical(3 if ledger.bindings.has(3) else 1,{"op":"check"});electrical(1,{"op":"power"});electrical(2,{"op":"record"})
	for participant in ledger.bindings:
		if int(participant)>3:electrical(int(participant),{"op":"record"})
	check(host.store.root().active["0"].evidence[identity_b].measure_final,"measurement role requires real corrected circuit")
	var root_before_failure: Dictionary=host.store.root();var balance_before_failure: int=ledger.state.accounts[identity_a].profile.dollars
	ledger.store.healthy=false
	check(not host.act(2,0,{"command":"submit","attempt_id":id}).ok,"failed atomic team commit does not complete")
	check(host.store.root()==root_before_failure and ledger.state.accounts[identity_a].profile.dollars==balance_before_failure,"failed team commit preserves result and money together")
	ledger.store.healthy=true
	var complete: Dictionary=host.act(2,0,{"command":"submit","attempt_id":id})
	check(complete.ok,"host-derived physical completion "+str(complete))
	return id
func run() -> void:
	var profile := Profile.new();profile.open("base-challenge-fixture")
	# This fixture imports the same starter stock under several distinct identities.
	profile.data.erase("dorm")
	# Imported profile metadata cannot create authoritative decoration progress.
	profile.data["lab_challenges"]={"unlocks":["motor_honours"]}
	var location := "user://team_test_"+Crypto.new().generate_random_bytes(6).hex_encode()
	ledger=Ledger.new();check(ledger.open(location)==OK,"ledger opens")
	check(ledger.bind(1,identity_a,"1".repeat(64),profile.data).ok,"bind authenticated host")
	check(ledger.bind(2,identity_b,"2".repeat(64),profile.data).ok,"bind authenticated participant")
	state=State.new();var locations := Fixture.locations()
	for kind in ["R","L","C"]:
		for i in 9:locations["%s_%d"%[kind,i]]=position
	state.initialize(Fixture.ids(),locations);configure_host()
	check(host.view(1,0).unlocks.is_empty(),"imported unlock metadata ignored")
	check(not host.act(2,0,{"command":"start","kind":"open_phase","seed":1}).ok,"client cannot start/reset shared scenario")
	check(not host.act(99,0,{"command":"start","kind":"open_phase","seed":1}).ok,"unbound peer rejected")
	var id := perform(1)
	if host.store.root().history.is_empty():quit(1);return
	check(host.store.root().history.size()==1 and host.store.root().active.is_empty(),"durable team result exists")
	var balance: int=ledger.state.accounts[identity_a].profile.dollars
	var expected: Dictionary=Economy.earning_credit(profile.data.dollars,180,true)
	var rewards: Dictionary=host.store.root().history[0].rewards
	check(expected.ok and balance==expected.next_balance and ledger.state.accounts[identity_b].profile.dollars==balance and rewards[identity_a]==expected.credit and rewards[identity_b]==expected.credit,"atomic team reward follows the active economy policy")
	check(not host.act(2,0,{"command":"submit","attempt_id":id}).ok,"duplicate completion rejected")
	check(ledger.state.accounts[identity_a].profile.dollars==balance,"replay cannot mint reward")
	check("team_plaque" in host.view(1,0).unlocks,"earned decoration unlocked")
	check(not host.act(1,0,{"command":"decorate","anchor":"../../door","decoration":"team_plaque"}).ok,"arbitrary anchor rejected")
	check(not host.act(1,0,{"command":"decorate","anchor":"left_award","decoration":"res://bad.gd"}).ok,"arbitrary resource rejected")
	check(host.act(1,0,{"command":"decorate","anchor":"left_award","decoration":"team_plaque"}).ok,"safe fixed cosmetic selection")
	check(not host.act(2,0,{"command":"decorate","anchor":"left_award","decoration":"team_plaque"}).ok,"other player cannot overwrite anchor owner")
	var public_view: Dictionary=host.view(1,0)
	check(not JSON.stringify(public_view).contains(identity_a) and not JSON.stringify(public_view).contains("credential"),"public team records conceal internal IDs and credentials")
	check(public_view.history[0].participants[0].id!=public_view.history[0].participants[1].id,"duplicate names retain distinct stable public identities")
	state.powered=false
	perform(1)
	check(ledger.state.accounts[identity_a].profile.dollars==balance and host.store.root().progress[identity_a].count==1,"repeat kind+seed records no duplicate reward/mastery")
	var generation: int=ledger.store.generation
	var old_root: Dictionary=host.store.root()
	ledger.store.healthy=false
	check(not host.act(1,0,{"command":"decorate","anchor":"right_award","decoration":"team_plaque"}).ok,"disk failure rejects cosmetic mutation")
	check(host.store.root()==old_root and ledger.store.generation==generation,"failed commit leaves authoritative state unchanged")
	ledger.store.healthy=true
	var reopened := Ledger.new();check(reopened.open(location)==OK,"durable journal reopens")
	check(reopened.bind(1,identity_a,"1".repeat(64),profile.data).ok,"host credential reconnect")
	check(reopened.bind(2,identity_b,"2".repeat(64),profile.data).ok,"participant reconnect")
	ledger=reopened;configure_host()
	check(host.store.root().history.size()==2 and ledger.state.accounts[identity_a].profile.dollars==balance,"team history/reward survives reload without trusting local balance")
	state.powered=false
	var start: Dictionary=host.act(1,0,{"command":"start","kind":"open_phase","seed":8})
	check(start.ok,"start journaled incomplete attempt")
	var bridge: Node=load("res://scripts/lab_challenges/bridge.gd").new();var fixture_game := GameFixture.new()
	fixture_game.school=SchoolFixture.new();fixture_game.add_child(fixture_game.school);fixture_game.session=SessionFixture.new();fixture_game.add_child(fixture_game.session);fixture_game.session.labs=[state];fixture_game.player=Node3D.new();fixture_game.add_child(fixture_game.player)
	bridge.game=fixture_game;bridge.host=host
	check(bridge._guard(1,0,{"op":"configure"})!="","live challenge blocks bypass through legacy configure")
	fixture_game.school.activity={"mode":"Course"};fixture_game.school.phase="assignment";fixture_game.school.mode="Class";fixture_game.school.class_students={"enrolled":true}
	check(bridge._guard(1,0,{"op":"configure"})=="" and not bridge._allowed(1,0,"start"),"formal course retains equipment authority and blocks challenge start")
	fixture_game.school.activity={}
	for phase in ["travel","lesson","assignment"]:
		fixture_game.school.phase=phase;check(bridge._formal_class() and not bridge._allowed(1,0,"start") and not bridge._allowed(1,0,"resume"),"legacy formal_active blocks challenges in "+phase)
	bridge._refresh_briefs();check(bridge.briefs.is_empty(),"team objective cannot overwrite official class sheet")
	fixture_game.school.activity={};fixture_game.school.phase="freeplay";fixture_game.school.mode="Creative Freeplay"
	check(not bridge._allowed(1,0,"submit") and bridge._allowed(1,0,"view"),"Creative cannot race ledger flag for rewards; read-only history allowed")
	fixture_game.school.mode="Freeplay"
	host.recover_journal()
	check(bridge._guard(1,0,{"op":"configure"})=="","suspended journal never locks essential Freeplay equipment")
	bridge.free();fixture_game.free()
	check(not host.act(1,0,{"command":"submit","attempt_id":start.attempt_id}).ok,"reload requires explicit physical restore")
	check(host.act(1,0,{"command":"resume","attempt_id":start.attempt_id}).ok,"host restores same attempt and resets stale evidence")
	check(host.store.root().active["0"].id==start.attempt_id and host.store.root().active["0"].evidence.is_empty(),"attempt identity persists while proofs reset")
	check(host.act(1,0,{"command":"abandon","attempt_id":start.attempt_id}).ok,"optional team attempt can end without academic penalty")
	check(ledger.state.accounts[identity_a].profile.dollars==balance,"abandon creates no payment or academic zero")
	var malformed: Dictionary=host.store.root();malformed.progress[identity_a].count=999
	check(not host.store.valid(malformed),"corrupt progress cannot mint unlocks")
	for peer in range(3,9):
		var token := str(peer).repeat(48);var secret := str(peer).repeat(64)
		check(ledger.bind(peer,token,secret,profile.data).ok,"additional authenticated team participant")
	state.powered=false;configure_host();var team_id := perform(2)
	check(not team_id.is_empty() and host.store.root().history[-1].participants.size()==8,"eight bounded participants complete with real roles")
	check(host.store.root().history[-1].evidence["3".repeat(48)].verify,"verification role uses final safe preflight")
	var secret_record: Dictionary=host.store.root();secret_record.history[-1].measurements["credential"]="SECRET"
	check(not host.store.valid(secret_record),"record schema rejects private/unknown measurement fields")
	state.powered=false
	var suspended: Dictionary=host.act(1,0,{"command":"start","kind":"open_phase","seed":9})
	host.recover_journal();state.mode="Free Laboratory";state.powered=true
	var existing_revision: int=state.revision
	check(host.act(1,0,{"command":"abandon","attempt_id":suspended.attempt_id}).ok,"suspended journal can be abandoned")
	check(state.powered and state.mode=="Free Laboratory" and state.revision==existing_revision,"abandoning stale journal never changes current Freeplay circuit")
	var journal: Dictionary=host.store.root();var before_reset: Dictionary= journal.duplicate(true);check(ledger.reset_world(),"existing ledger reset_world still works")
	check(host.store.root()==before_reset,"existing world reset preserves durable team history/unlocks")
	host.store.authority=func():return false
	check(not host.act(1,0,{"command":"decorate","anchor":"left_award","decoration":"team_plaque"}).ok,"non-authoritative adapter cannot mutate progression")
	host.store.authority=func():return true
	print("BASE_HOST_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
