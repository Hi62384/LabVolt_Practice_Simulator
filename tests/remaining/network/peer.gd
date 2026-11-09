extends SceneTree
## Real ENet/Session + the production-owned Bridge endpoint. A host-only fixture
## chooses poses, builds actual DCStation snapshots, and compares receiver hashes.
const Session=preload("res://scripts/session.gd")
const Station=preload("res://scripts/dc_station.gd")
const Registry=preload("res://scripts/campus/world/room_registry.gd")
const Context=preload("res://scripts/campus/performance/bench_interest_context.gd")
const Bridge=preload("res://scripts/campus/performance/dc_interest_bridge.gd")
var role:="host"
var slot:=0
var total:=2
var port:=26002
var output:="user://network-result.json"
var session: Node
var bridge: Node
var control: Node
var registry:=Registry.new()
var context:=Context.new()
var stations: Array=[]
var states: Array=[]
var workload: Array=[]
var dc: Array=[]
var ac: Array=[]
var links: Array=[]
var school: Dictionary={}
var all_objects:=false
var expected: Dictionary={}
var acknowledgements: Dictionary={}
var phase_number:=0
var global_ticks:=0
var finished:=false
var failures: Array[String]=[]
var reports: Array=[]
var deadline:=0
var received_timer:=0
var client_deadline:=0

class TestControl extends Node:
	var driver: SceneTree
	@rpc("authority","call_remote","reliable",4)
	func phase(info: Dictionary) -> void:
		driver.expected=info
		driver.global_ticks+=1
		driver.received_timer=int(info.timer_token)
		driver.client_deadline=Time.get_ticks_msec()+4000
	@rpc("any_peer","call_remote","reliable",4)
	func ack(number: int, okay: bool, error: String, observed: Dictionary) -> void:
		if not multiplayer.is_server():return
		var sender:=multiplayer.get_remote_sender_id()
		if not driver.session.peer_connected_now(sender):return
		driver.acknowledgements[sender]={"phase":number,"ok":okay,"error":error,"observed":observed}
	@rpc("authority","call_remote","reliable",4)
	func reconnect() -> void:
		driver.expected={}
		driver.session.leave()
		driver.session.join_game("127.0.0.1","Client"+str(driver.slot),driver.port)
	@rpc("authority","call_remote","reliable",4)
	func force_gap() -> void:
		# Skip one expected delivery locally, so the next packet is a forward gap.
		# Raising the counter would only simulate a duplicate/older packet.
		driver.bridge.service._sequence-=1
		rpc_id(1,"ack",-777,true,"",{"forced_gap":true})
	@rpc("authority","call_remote","reliable",4)
	func finish() -> void:
		driver.finish_client()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps=60
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.split("=",true,1)
		if pair.size()!=2:continue
		match pair[0]:
			"--role":role=pair[1]
			"--slot":slot=int(pair[1])
			"--total":total=int(pair[1])
			"--port":port=int(pair[1])
			"--output":output=pair[1]
	deadline=Time.get_ticks_msec()+24000
	session=Session.new();session.name="Session";session.campus_enabled=true;root.add_child(session);session.initialize([],{})
	bridge=Bridge.new();bridge.name="BenchInterest";root.add_child(bridge);bridge.configure(session,_projection,func():pass)
	control=TestControl.new();control.name="TestControl";control.driver=self;root.add_child(control)
	if role!="host":
		var error: Error=session.join_game("127.0.0.1","Client"+str(slot),port)
		if error!=OK:failures.append("Join failed");finish_client()
		return
	for i in 3:
		var station:=Station.new();station.master=true;station.channels[0].enabled=true;station.channels[0].voltage=5.0+i
		station.wires=[["CH0+","R1a"],["R1b","CH0-"]];station.step(0.0005);stations.append(station)
		dc.append({"CH0+":Vector3((i-1)*6,1,19),"CH0-":Vector3((i-1)*6,1,19)})
		ac.append({"P_A":Vector3((i-1)*6,1,0)})
	_refresh()
	# Capture one real deterministic solver sequence once. Both traffic phases
	# replay exactly these snapshots, including identical scope history lengths.
	workload.append(states.duplicate(true))
	for tick in 12:
		for i in stations.size():
			stations[i].channels[0].voltage=6.0+i+tick*0.125
			stations[i].revision+=1;stations[i].step(0.0005)
		_refresh();workload.append(states.duplicate(true))
	states=workload[0].duplicate(true)
	# Retain the exact authoritative replay, not only a workload hash.
	var capture:=FileAccess.open(output+".workload.bin",FileAccess.WRITE)
	if capture==null:failures.append("Cannot preserve workload capture");await finish_host();return
	capture.store_buffer(var_to_bytes(workload));capture.close()
	var history: Array=[]
	for frame in workload:
		var details: Array=[]
		for state in frame:details.append({"revision":state.revision,"scope_samples":state.samples.size(),"samples_sha256":digest(state.samples),"state_sha256":digest(state)})
		history.append(details)
	var capture_manifest:=FileAccess.open(output+".workload.json",FileAccess.WRITE)
	if capture_manifest==null:failures.append("Cannot preserve workload manifest");await finish_host();return
	capture_manifest.store_string(JSON.stringify({"frame_count":workload.size(),"workload_sha256":digest(workload),"history":history},"\t"));capture_manifest.close()
	var error: Error=session.host_game("Host",port)
	if error!=OK:failures.append("Host failed");await finish_host();return
	var ready:=FileAccess.open(output+".ready",FileAccess.WRITE);ready.store_string("ready");ready.close()
	if not await _roster_ready():failures.append("Roster startup timeout");await finish_host();return
	# Actual all-object control with same Bridge/wire schema, followed by interest.
	_positions("gym");all_objects=true
	await announce("all-object-control",_all_indices())
	var before: Dictionary=bridge.service.metrics()
	await active_ticks()
	await announce("all-object-control-final",_all_indices())
	_record_delta("all-object-control",before)
	all_objects=false;_positions("separated");states=workload[0].duplicate(true)
	await announce("separated",_separated_indices())
	before=bridge.service.metrics()
	await active_ticks()
	await announce("separated-final",_separated_indices())
	_record_delta("separated",before)
	before=bridge.service.metrics()
	for i in 20:bridge.publish()
	var after: Dictionary=bridge.service.metrics()
	if after.queued_packets!=before.queued_packets:failures.append("Unchanged snapshots emitted packets")
	reports.append({"phase":"unchanged","queued_packets":after.queued_packets-before.queued_packets})
	_positions("gym");await announce("depart",{})
	stations[0].board_epoch+=1;_refresh();_positions("left")
	await announce("reentry",{1:[0]})
	_positions("gym");stations[2].board_owner=_peer_for_slot(1);_refresh()
	await announce("owner-remote",{1:[2]})
	stations[2].board_owner=0;_refresh()
	school={"identities":{},"allocation":{},"activity":{"course_id":"ETY155","kind":"lab"}}
	var group_expected: Dictionary={}
	for participant in range(1,mini(total,3)):
		var peer:=_peer_for_slot(participant);var identity:="student-"+str(participant)
		school.identities[peer]=identity;school.allocation[identity]={"bench":1,"group":1};group_expected[participant]=[1]
	await announce("shared-activity",group_expected)
	school={};_positions("ac")
	links=[{"a":{"station":0,"port":"CH0+"},"b":{"station":3,"port":"P_A"}},{"a":{"station":3,"port":"P_A"},"b":{"station":2,"port":"CH0-"}}]
	await announce("cross-room-coupling",{1:[0,2]})
	links=[];_positions("left")
	var old_peer:=_peer_for_slot(1)
	control.rpc_id(old_peer,"reconnect")
	await pause(0.15)
	if not await _roster_ready(old_peer):failures.append("Reconnect timeout")
	_positions("left");await announce("reconnected",{1:[0]})
	bridge.reset_session();await announce("stream-reset",{1:[0]})
	var recovering_peer:=_peer_for_slot(1)
	control.rpc_id(recovering_peer,"force_gap")
	var ack_deadline:=Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<ack_deadline and int(acknowledgements.get(recovering_peer,{}).get("phase",0))!=-777:await pause(0.025)
	stations[0].revision+=1;stations[0].step(0.0005);_refresh()
	await announce("sequence-gap-recovery",{1:[0]})
	states[0]["transport_fixture_deleted"]={"memory":PackedByteArray([1,3,5])}
	await announce("field-present",{1:[0]})
	states[0].erase("transport_fixture_deleted")
	await announce("field-tombstone",{1:[0]})
	await finish_host()

func _process(_delta: float) -> bool:
	if finished:return false
	if deadline>0 and Time.get_ticks_msec()>deadline:
		failures.append("Global fixture deadline");finished=true;_write();quit(1);return false
	if role!="host" and not expected.is_empty():
		var indices: Array=[]
		for i in 3:
			if bridge.service.active(i):indices.append(i)
		var valid: bool=indices==expected.indices and received_timer==int(expected.timer_token)
		if valid:
			for i in indices:
				if digest(bridge.service.state(i))!=str(expected.hashes[str(i)]):valid=false
		if valid or Time.get_ticks_msec()>client_deadline:
			var number:=int(expected.number)
			var observed: Dictionary={"indices":indices,"stream":bridge.service._stream,"metrics":bridge.service.metrics(),"global_timer":received_timer}
			control.rpc_id(1,"ack",number,valid,"" if valid else "Interest/hash/timer mismatch",observed)
			if not valid:failures.append("Phase "+str(expected.label)+" mismatch")
			expected={}
	return false

func digest(value: Variant) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()

func _projection() -> Dictionary:
	var view: Dictionary=context.build(session.roster,session.poses,registry,states,dc,ac,links,school)
	if all_objects:
		for object in view.objects.values():object.meta.global=true
	return view

func _refresh() -> void:
	states.clear()
	for station in stations:states.append(station.snapshot())

func active_ticks() -> void:
	for tick in 12:
		states=workload[tick+1].duplicate(true)
		bridge.publish();await pause(0.025)

func _record_delta(label: String, before: Dictionary) -> void:
	var after: Dictionary=bridge.service.metrics()
	reports.append({"phase":label,"workload_sha256":digest(workload),"queued_packets":after.queued_packets-before.queued_packets,"queued_payload_bytes":after.queued_payload_bytes-before.queued_payload_bytes,"queued_raw_bytes":after.queued_raw_bytes-before.queued_raw_bytes,"elapsed_seconds":after.elapsed_seconds-before.elapsed_seconds,"byte_scope":after.byte_scope})

func _peer_for_slot(number: int) -> int:
	for peer in session.roster:
		if str(session.roster[peer].get("name",""))=="Client"+str(number):return int(peer)
	return -1

func _positions(kind: String) -> void:
	for number in range(1,total):
		var peer:=_peer_for_slot(number)
		if peer<0:continue
		var point:=Vector3(0,0,33)
		if kind=="separated":
			if number==1:point=Vector3(-9,0,18)
			elif number==2:point=Vector3(9,0,18)
		elif kind=="left" and number==1:point=Vector3(-9,0,18)
		elif kind=="ac" and number==1:point=Vector3(-6,0,0)
		# Test-host teleport, not a client-supplied pose or a movement validation test.
		session.poses[peer]={"position":point}

func _all_indices() -> Dictionary:
	var result: Dictionary={}
	for number in range(1,total):result[number]=[0,1,2]
	return result

func _separated_indices() -> Dictionary:
	var result: Dictionary={1:[0]}
	if total>2:result[2]=[2]
	return result

func announce(label: String, by_slot: Dictionary) -> void:
	phase_number+=1;acknowledgements.clear();bridge.publish()
	for number in range(1,total):
		var peer:=_peer_for_slot(number)
		if peer<0:failures.append("Missing peer "+str(number));continue
		var wanted: Array=by_slot.get(number,[])
		var hashes: Dictionary={}
		for index in wanted:hashes[str(index)]=digest(states[index])
		control.rpc_id(peer,"phase",{"number":phase_number,"label":label,"indices":wanted,"hashes":hashes,"timer_token":phase_number})
	var until:=Time.get_ticks_msec()+4500
	while Time.get_ticks_msec()<until:
		var complete:=true
		for peer in session.roster:
			if int(peer)!=1 and (not acknowledgements.has(peer) or int(acknowledgements[peer].phase)!=phase_number):complete=false
		if complete and session.roster.size()==total:break
		await pause(0.025)
	for number in range(1,total):
		var peer:=_peer_for_slot(number)
		var answer: Dictionary=acknowledgements.get(peer,{})
		if int(answer.get("phase",-1))!=phase_number or not answer.get("ok",false):failures.append(label+" peer "+str(number)+" "+str(answer.get("error","no ack")))
	reports.append({"phase":label,"answers":acknowledgements.duplicate(true)})

func _roster_ready(exclude: int=-1) -> bool:
	var until:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<until:
		if session.roster.size()==total and (exclude<0 or not session.roster.has(exclude)):return true
		await pause(0.025)
	return false

func pause(seconds: float) -> void:await create_timer(seconds).timeout

func finish_client() -> void:
	if finished:return
	finished=true;_write();session.leave();quit(1 if not failures.is_empty() else 0)

func finish_host() -> void:
	for peer in session.roster:
		if int(peer)!=1 and session.peer_connected_now(int(peer)):control.rpc_id(int(peer),"finish")
	await pause(0.75)
	finished=true;_write();session.leave();quit(1 if not failures.is_empty() else 0)

func _write() -> void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"role":role,"slot":slot,"total":total,"port":port,"failures":failures,"phases":reports,"global_timer_messages_received":global_ticks,"metrics":bridge.service.metrics(),"enqueue_error":bridge.last_enqueue_error,"scope":"actual ENet and production Bridge; actual DCStation snapshots, host-authored fixture poses; control/class event channel is a separate fixture, not full SchoolSession acceptance"},"\t"));file.close()
	print("NETWORK C %s slot=%d total=%d failures=%d"%[role,slot,total,failures.size()])
