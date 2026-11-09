extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
const Adapter=preload("res://scripts/campus/facilities/profile_adapter.gd")
var h=Host.new()
var t:=1000
var ledger:={"student-a":{"dollars":100,"facilities":Host.empty_profile()},"student-b":{"dollars":100,"facilities":Host.empty_profile()}}
var contexts:={}
var failures:=0
var checks:=0
var reject_save:=false

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)

func _initialize() -> void:
	h.authority=func():return true
	h.clock=func():return t
	h.context=func(peer):return contexts.get(peer,{})
	h.load_profile=func(id):return ledger[id].facilities.duplicate(true)
	h.commit_profile=func(id,delta,p):
		if reject_save or ledger[id].dollars+delta<0:return false
		ledger[id].dollars+=delta
		ledger[id].facilities=p.duplicate(true)
		return true
	for peer in [1,2]:
		contexts[peer]={"identity":"student-a" if peer==1 else "student-b","position":Vector3.ZERO,"room_id":"test-room","allowed":true,"grounded":true}
	h.anchors={"counter":{"room_id":"test-room","position":Vector3.ZERO,"kind":"counter:tim_hortons"},"seat":{"room_id":"test-room","position":Vector3.ZERO,"kind":"seat"},"rack":{"room_id":"test-room","position":Vector3.ZERO,"kind":"pushup"}}
	check(not h.act(99,{"op":"buy","item":"coffee","station":"counter","sequence":1}).ok,"unregistered sender rejected")
	check(send(1,{"op":"buy","item":"coffee","station":"counter"}).ok,"real purchase")
	check(ledger["student-a"].dollars==97 and ledger["student-a"].facilities.held.servings==3,"existing dollars debit and held item")
	t+=100
	check(not h.act(1,{"op":"buy","item":"coffee","station":"counter","sequence":1}).ok,"duplicate request rejected")
	check(ledger["student-a"].dollars==97,"duplicate cannot debit")
	check(send(1,{"op":"place","station":"seat"}).ok,"place food on table")
	contexts[1].position=Vector3(10,0,0)
	check(not send(1,{"op":"pickup"}).ok,"remote pickup rejected")
	contexts[1].position=Vector3.ZERO
	check(send(1,{"op":"pickup"}).ok,"owner pickup")
	check(not send(2,{"op":"consume"}).ok,"other student cannot consume owner item")
	for i in 3:t+=800;check(send(1,{"op":"consume"}).ok,"consume serving")
	check(ledger["student-a"].facilities.held.is_empty(),"food consumed exactly once")
	check(send(1,{"op":"sit","station":"seat"}).ok,"sit")
	check(not send(2,{"op":"sit","station":"seat"}).ok,"occupied seat rejected")
	check(h.movement_locked(1),"seat locks translation")
	check(send(1,{"op":"stand"}).ok and not h.movement_locked(1),"stand unlocks")
	reject_save=true
	check(not send(1,{"op":"buy","item":"donut","station":"counter"}).ok,"failed atomic save rejects purchase")
	check(ledger["student-a"].dollars==97 and ledger["student-a"].facilities.held.is_empty(),"failure leaves balance/item unchanged")
	reject_save=false
	contexts[1].allowed=false
	check(not send(1,{"op":"start","station":"rack"}).ok,"formal activity restriction")
	contexts[1].allowed=true
	check(not send(1,{"op":"finish","reps":30,"xp":999}).ok,"forged result rejected")
	check(send(1,{"op":"start","station":"rack"}).ok,"exercise start")
	check(not send(2,{"op":"start","station":"rack"}).ok,"equipment exclusive")
	check(not send(1,{"op":"beat"}).ok,"fast beat rejected")
	for i in 40:
		t+=600
		check(send(1,{"op":"beat"}).ok,"host-paced beat")
	check(send(1,{"op":"finish"}).ok,"finish earned set")
	check(ledger["student-a"].facilities.xp==100,"XP server computed")
	check(ledger["student-a"].facilities.records.pushup.reps==20,"personal record")
	check("cheer" in ledger["student-a"].facilities.unlocks,"level unlock")
	check(not send(1,{"op":"finish"}).ok,"cannot duplicate XP")
	check(send(1,{"op":"emote","emote":"cheer"}).ok,"unlocked emote")
	check(h.movement_locked(1),"emote locks translation")
	contexts[1].position=Vector3(0.5,0,0)
	h.tick()
	check(not h.movement_locked(1),"invalid movement cancels emote")
	contexts[1].position=Vector3.ZERO
	check(h.public_profile(1).is_empty(),"privacy default")
	check(not h.public_profile(1,true).has("dollars") and not h.public_profile(1,true).has("identity"),"public whitelist")
	var saved:=JSON.stringify(ledger)
	var file:=FileAccess.open("user://facilities-test.json",FileAccess.WRITE)
	file.store_string(saved);file.close()
	ledger=JSON.parse_string(FileAccess.get_file_as_string("user://facilities-test.json"))
	check(Host.valid_profile(ledger["student-a"].facilities),"JSON save reload validates")
	check(ledger["student-a"].facilities.xp==100 and ledger["student-b"].facilities.xp==0,"individual progression persists")
	# Same stable identity on a new connection retains sequence/rewards; peer id is not profile id.
	contexts[7]=contexts[1].duplicate(true)
	check(h.private_state(7).profile.xp==100,"reconnect restores stable identity")
	t+=100
	check(not h.act(7,{"op":"finish","sequence":1}).ok,"reconnect replay rejected")
	for exercise in Host.EXERCISES:
		h.anchors.rack.kind=exercise
		check(send(7,{"op":"start","station":"rack"}).ok,"start "+exercise)
		for beat in 2:
			t+=int(Host.EXERCISES[exercise])/2-100
			check(send(7,{"op":"beat"}).ok,"beat "+exercise)
		check(send(7,{"op":"finish"}).ok,"finish "+exercise)
	check(h.private_state(7).profile.records.size()==5,"all five minigames produce records")
	print("FACILITIES checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func send(peer: int, r: Dictionary) -> Dictionary:
	t+=100
	var req:=r.duplicate(true)
	req.sequence=int(ledger[contexts[peer].identity].facilities.last_sequence)+1
	return h.act(peer,req)
