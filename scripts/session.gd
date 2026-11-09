extends Node
const MAX_PLAYERS := 8
var shop_returns := {}
var academic_equipment_guard: Callable
var lab_challenge_guard := Callable()
var lab_challenge_observer := Callable()
var lab_challenge_brief := Callable()
var academic_equipment_observer: Callable
var facility_translation_guard: Callable
var campus_enabled := false
## ENet authority: clients send actions, never solutions or equipment snapshots.
signal appearance_received(peer: int,data: PackedByteArray)
var local_appearance := PackedByteArray()
var appearances := {}
var appearance_incoming := {}
var appearance_queue: Array = []
var appearance_sent := false
signal chat_received(peer: int,sender: String,message: String)
signal leaving
signal restarted
signal changed(snapshot: Dictionary)
signal ac_readings_changed(station: int, revision: int, readings: Dictionary)
signal interaction_accepted(event: Dictionary)
var interaction_sequence := 0
signal message_received(text: String)
signal roster_changed
signal pose_received(id: int, data: Dictionary)
const State = preload("res://scripts/lab_state.gd")
const DormLayout = preload("res://scripts/campus/dorms/world/dorm_layout.gd")
const PORT := 24842
var lab = State.new()
var labs: Array = [lab]
var roster := {}
var poses := {}
var online := false
var was_host := false
var pose_epochs := {}
var local_pose_epoch := 0
var local_name := "Student"
var last_actions := {}
var last_pose := {}
var last_chat := {}
var port := PORT
var internet_port := 0
var internet_worker: Thread
var internet_mapping := {}
var internet_retry_at := 0

# Trusted host code supplies explicit section projections, never entire saves.
signal campus_public_profiles_changed
var campus_public_replication := preload("res://scripts/campus/social/profile_replication.gd").new()
var campus_public_cache := preload("res://scripts/campus/social/profile_cache.gd").new()
func campus_profile_publish(internal_identity: String, display_name: String, public_sections: Dictionary, visibility: Dictionary) -> void:
	if multiplayer.is_server(): campus_public_replication.publish(internal_identity,display_name,public_sections,visibility)
func campus_profile_send(peer: int, relevant_internal_identities: Array) -> void:
	if not multiplayer.is_server(): return
	for packet in campus_public_replication.collect(peer,relevant_internal_identities):
		if peer==1:
			if campus_public_cache.receive(packet): campus_public_profiles_changed.emit()
		elif online: _campus_profile_delta.rpc_id(peer,packet)
@rpc("authority","call_remote","reliable")
func _campus_profile_delta(packet: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1: return
	if campus_public_cache.receive(packet): campus_public_profiles_changed.emit()
func _campus_profiles_reset() -> void:
	campus_public_cache.clear()
	campus_public_replication=preload("res://scripts/campus/social/profile_replication.gd").new()
	campus_public_profiles_changed.emit()

const RelayPeer = preload("res://scripts/lab_relay_peer.gd")

static func relay_endpoint() -> String:
	var override := OS.get_environment("LABVOLT_RELAY_URL").strip_edges()
	return override if not override.is_empty() else str(ProjectSettings.get_setting("network/labvolt/relay_url", ""))

func room_code() -> String:
	var transport = multiplayer.multiplayer_peer
	return transport.room_code if transport is RelayPeer and was_host else ""

func _ready() -> void:
	# Every game message is host mediated; the explicit roster handles peer presence.
	if multiplayer is SceneMultiplayer:multiplayer.server_relay=false
	multiplayer.peer_disconnected.connect(_left)
	multiplayer.connected_to_server.connect(func(): register.rpc_id(1,local_name))
	multiplayer.connection_failed.connect(func():
		var transport = multiplayer.multiplayer_peer
		var reason: String = transport.failure if transport is RelayPeer else "Connection failed. Check host IP, UDP port and firewall."
		leave()
		message_received.emit(reason)
	)
	multiplayer.server_disconnected.connect(func(): leave(true); message_received.emit("Host disconnected. Returned to local laboratory."))

func initialize(ids: Array, locations: Dictionary) -> void:
	lab.initialize(ids,locations)
	roster = {1:{"name":local_name,"ready":false}}
	poses[1] = {"position":(Vector3(13,0,-18) if campus_enabled else Vector3(0,0,1.75)),"yaw":0.0,"pitch":0.0,"crouch":false}
	changed.emit(world_snapshot())
	roster_changed.emit()

func host_game(player_name: String, selected_port := PORT, automatic_forwarding := false) -> Error:
	leave()
	local_name = player_name.strip_edges().left(24)
	if local_name=="":
		local_name="Student"
	port = selected_port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port,MAX_PLAYERS-1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	online = true
	was_host=true
	if automatic_forwarding:
		internet_port = port
		internet_retry_at = 0
	roster[1] = {"name":local_name,"ready":false}
	roster_changed.emit()
	return OK

func join_game(address: String, player_name: String, selected_port := PORT) -> Error:
	leave()
	local_name = player_name.strip_edges().left(24)
	if local_name=="":
		local_name="Student"
	port = selected_port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(),selected_port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	online = true
	was_host=false
	roster.clear()
	roster_changed.emit()
	return OK

func start_relay_host(peer: MultiplayerPeer, player_name: String) -> void:
	leave()
	local_name = player_name.strip_edges().left(24)
	if local_name.is_empty():
		local_name = "Student"
	multiplayer.multiplayer_peer = peer
	online = true
	was_host = true
	roster[1] = {"name":local_name,"ready":false}
	roster_changed.emit()

func join_relay(code: String, player_name: String, endpoint := "") -> Error:
	var peer := RelayPeer.new()
	var error := peer.open(relay_endpoint() if endpoint.is_empty() else endpoint, code)
	if error != OK:
		return error
	leave()
	local_name = player_name.strip_edges().left(24)
	if local_name.is_empty():
		local_name = "Student"
	multiplayer.multiplayer_peer = peer
	online = true
	was_host = false
	roster.clear()
	roster_changed.emit()
	return OK

func leave(authority_lost := false) -> void:
	last_local_pose.clear()
	relay_pose_dirty = false
	relay_pose_clock = 0.0
	internet_port = 0
	interaction_sequence=0
	var transport: MultiplayerPeer=multiplayer.multiplayer_peer
	var disconnected: bool=online and transport!=null and transport.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED
	set_meta("lost_authority",authority_lost or (disconnected and not was_host))
	if disconnected:
		online=false
		multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	_campus_profiles_reset()
	leaving.emit() # Synchronous host-owned persistence before network/world teardown.
	appearance_sent=false
	appearance_queue.clear()
	appearance_incoming.clear()
	appearances.clear()
	appearances[1]=local_appearance
	if online:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	roster = {1:{"name":local_name,"ready":false}}
	poses.clear();shop_returns.clear();pose_epochs.clear();local_pose_epoch=0
	poses[1] = {"position":(Vector3(13,0,-18) if campus_enabled else Vector3(0,0,1.75)),"yaw":0.0,"pitch":0.0,"crouch":false}
	for state in labs:
		for c in state.cables:
			c.owner=0
		state.release(-1)
	last_actions.clear()
	last_pose.clear()
	last_chat.clear()
	roster_changed.emit()
	changed.emit(world_snapshot())
	restarted.emit()

@rpc("any_peer","call_remote","reliable")
func register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.size() >= MAX_PLAYERS or roster.has(id):
		return
	roster[id] = {"name":player_name.strip_edges().left(24),"ready":false}
	poses[id] = {"position":(Vector3(13,0,-18) if campus_enabled else Vector3(0,0,1.75)),"yaw":0.0,"pitch":0.0,"crouch":false}
	_send_connected("_roster",[roster])
	_snapshot.rpc_id(id,world_snapshot())
	if uses_relay(): relay_pose_dirty = true
	for peer in appearances:
		_queue_appearance(id,int(peer),appearances[peer])
	_send_connected("_chat",["%s joined the laboratory." % roster[id].name])

func _left(id: int) -> void:
	campus_public_replication.forget_peer(id)
	if not multiplayer.is_server():
		return
	if online and was_host and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:return
	roster.erase(id)
	poses.erase(id);shop_returns.erase(id)
	appearances.erase(id)
	appearance_incoming.erase(id)
	for state in labs:
		state.release(id)
	broadcast()
	if online:
		_send_connected("_roster",[roster])
	roster_changed.emit()

@rpc("authority","call_remote","reliable")
func _roster(data: Dictionary) -> void:
	roster = data
	roster_changed.emit()
	if roster.has(multiplayer.get_unique_id()) and not appearance_sent:
		appearance_sent=true
		_queue_appearance(1,multiplayer.get_unique_id(),local_appearance)

func ready_toggle() -> void:
	if online and not multiplayer.is_server():
		_ready_request.rpc_id(1)
	else:
		_set_ready(1)

@rpc("any_peer","call_remote","reliable")
func _ready_request() -> void:
	if multiplayer.is_server():
		_set_ready(multiplayer.get_remote_sender_id())

func _set_ready(id: int) -> void:
	if roster.has(id):
		roster[id].ready = not roster[id].ready
		if online:
			_send_connected("_roster",[roster])
		roster_changed.emit()

func request(action: Dictionary) -> void:
	if online and multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if online and not multiplayer.is_server():
		_action.rpc_id(1,action)
	else:
		apply_action(1,action)

@rpc("any_peer","call_remote","reliable")
func _action(action: Dictionary) -> void:
	if multiplayer.is_server():
		apply_action(multiplayer.get_remote_sender_id(),action)

func apply_action(id: int, action: Dictionary) -> void:
	if not roster.has(id) or action.size() > 12:
		return
	for key in ["delta","index","id","color","task","seed","v","i","p","station","element"]:
		if action.has(key) and (not typeof(action[key]) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(action[key]))):
			return
	var now := Time.get_ticks_msec()
	if now - int(last_actions.get(id,-1000)) < 35:
		return
	last_actions[id] = now
	var station := clampi(int(action.get("station",0)),0,labs.size()-1)
	if academic_equipment_guard.is_valid() and not academic_equipment_guard.call(id,station,action):return
	if str(action.get("op","")) in ["pickup","unstash"]:
		for state in labs:
			if not state.holding(id).is_empty():
				return
	var before: Dictionary=labs[station].snapshot() if academic_equipment_observer.is_valid() or lab_challenge_observer.is_valid() or str(action.get("op","")) in ["plug","unplug","undo","switch","voltage","frequency","dyn_load","supply_meter","power","dyn_measure","igbt_damping","pickup","unstash","grab"] else {}
	var error: String=str(lab_challenge_guard.call(id,station,action)) if lab_challenge_guard.is_valid() else ""
	var origin := -1
	var moved := {}
	if error=="" and action.get("op")=="plug" and labs[station].holding(id).is_empty() and labs[station].cables.size()<120:
		for i in labs.size():
			var cable: Dictionary=labs[i].holding(id)
			if cable.is_empty() or cable.a!="" or cable.b!="":continue
			origin=i
			moved=cable.duplicate()
			moved.id=labs[station].next_id
			labs[station].cables.append(moved)
			break
	if error=="":error=labs[station].act(id,action,poses.get(id,{}).get("position",Vector3.ZERO),id==1)
	if origin>=0:
		if error.is_empty():
			labs[origin].cables.erase(labs[origin].holding(id))
			labs[origin].revision+=1
			labs[station].next_id+=1
		else:labs[station].cables.erase(moved)
	if error=="" and academic_equipment_observer.is_valid():academic_equipment_observer.call(id,station,action,before)
	if error=="" and lab_challenge_observer.is_valid():lab_challenge_observer.call(id,station,action,before)
	if error != "":
		if id == 1:
			message_received.emit(error)
		else:
			_notice.rpc_id(id,error)
	# Failed live edits can increment safety strikes; synchronize that too.
	broadcast()
	if error=="" and not before.is_empty():
		interaction_sequence+=1
		var event: Dictionary=preload("res://scripts/interaction_presentation/accepted_event.gd").project(id,station,action,before,labs[station].snapshot(),labs[station].positions,interaction_sequence)
		if not event.is_empty():
			interaction_accepted.emit(event)
			if online:_send_connected("_interaction_event",[event])

@rpc("authority","call_remote","reliable")
func _interaction_event(event: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1:return
	interaction_accepted.emit(event)

func broadcast() -> void:
	var data: Dictionary = world_snapshot()
	changed.emit(data)
	if online:
		_send_connected("_snapshot",[data])

func publish_ac_readings(station: int, revision: int, readings: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	ac_readings_changed.emit(station, revision, readings)
	if online:
		_send_connected("_ac_readings", [station, revision, readings])

@rpc("authority","call_remote","unreliable_ordered")
func _ac_readings(station: int, revision: int, readings: Dictionary) -> void:
	ac_readings_changed.emit(station, revision, readings)

@rpc("authority","call_remote","reliable")
func _snapshot(data: Dictionary) -> void:
	changed.emit(data)

@rpc("authority","call_remote","reliable")
func _notice(value: String) -> void:
	message_received.emit(value)

var relay_pose_interval := 0.1
var relay_skip_idle := true
var relay_pose_dirty := false
var relay_pose_clock := 0.0
var last_local_pose := {}
var last_local_pose_time := 0

func uses_relay() -> bool:
	return online and multiplayer.multiplayer_peer is RelayPeer

func send_pose(data: Dictionary) -> void:
	data=data.duplicate();data["pose_epoch"]=local_pose_epoch
	if uses_relay() and relay_skip_idle:
		var now := Time.get_ticks_msec()
		var acknowledged: Dictionary = poses.get(multiplayer.get_unique_id(), {})
		var accepted_position: Vector3 = acknowledged.get("position", Vector3.INF)
		if data == last_local_pose and now - last_local_pose_time < 2000 and accepted_position.distance_to(data.position) < 0.05:
			return
		last_local_pose = data
		last_local_pose_time = now
	if online and multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if online and not multiplayer.is_server():
		_pose.rpc_id(1,data)
	else:
		accept_pose(1,data)

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _pose(data: Dictionary) -> void:
	if multiplayer.is_server():
		accept_pose(multiplayer.get_remote_sender_id(),data)

var rest_pose_guard: Callable

func accept_pose(id: int,data: Dictionary) -> void:
	if int(data.get("pose_epoch",0))!=int(pose_epochs.get(id,0)):return
	if not roster.has(id) or not data.get("position") is Vector3:
		return
	for key in ["yaw","pitch"]:
		if data.has(key) and not typeof(data[key]) in [TYPE_INT,TYPE_FLOAT]:
			return
	var pos: Vector3 = data.position
	if not pos.is_finite():
		return
	var now := Time.get_ticks_msec()
	var elapsed := clampf((now-float(last_pose.get(id,now-100)))/1000.0,0.01,0.5)
	var old: Vector3 = poses.get(id,{}).get("position",(Vector3(13,0,-18) if campus_enabled else Vector3(0,0,1.75)))
	if facility_translation_guard.is_valid():pos=facility_translation_guard.call(id,pos,old)
	var displacement := pos-old
	if displacement.length() > 6.0*elapsed+0.4:
		pos = old + displacement.normalized()*(6.0*elapsed)
	if campus_enabled:
		pos.x=clampf(pos.x,-9.6,35.6)
		var dorm_min_x := DormLayout.CORRIDOR_X_MIN - DormLayout.ROOM_WIDTH
		var dorm_max_x := DormLayout.CORRIDOR_X_MAX + DormLayout.ROOM_WIDTH
		var dorm_path := pos.x >= dorm_min_x and pos.x <= dorm_max_x
		var north_limit := DormLayout.hall_end_z(MAX_PLAYERS) - .4 if dorm_path else 67.6
		pos.z=clampf(pos.z,-24.6,north_limit)
		pos.y=clampf(pos.y,0,8.0)
	else:
		pos.x = clampf(pos.x,20.4,31.6) if shop_returns.has(id) else clampf(pos.x,-9.4,9.4)
		pos.z = clampf(pos.z,-1.6,7.6) if shop_returns.has(id) else clampf(pos.z,-2.3,9.4)
		pos.y = clampf(pos.y,0,3)
	var clean := {"position":pos,"yaw":float(data.get("yaw",0)),"pitch":clampf(float(data.get("pitch",0)),-1.46,1.46),"crouch":bool(data.get("crouch",false)),"seated":bool(data.get("seated",false))}
	if not is_finite(clean.yaw) or not is_finite(clean.pitch):
		return
	if rest_pose_guard.is_valid():clean=rest_pose_guard.call(id,clean)
	poses[id] = clean
	last_pose[id] = now
	pose_received.emit(id,clean)
	if uses_relay():
		relay_pose_dirty = true
	elif online:
		_send_connected("_poses",[poses])

@rpc("authority","call_remote","unreliable_ordered",1)
func _poses(data: Dictionary) -> void:
	poses = data
	for id in data:
		pose_received.emit(id,data[id])

func chat(value: String) -> void:
	if online and not multiplayer.is_server():
		_chat_request.rpc_id(1,value)
	else:
		accept_chat(1,value)

@rpc("any_peer","call_remote","reliable")
func _chat_request(value: String) -> void:
	if multiplayer.is_server():
		accept_chat(multiplayer.get_remote_sender_id(),value)

func accept_chat(id: int,value: String) -> void:
	if not roster.has(id) or Time.get_ticks_msec()-int(last_chat.get(id,-1000)) < 600:
		return
	last_chat[id] = Time.get_ticks_msec()
	var message := value.strip_edges().replace("\n"," ").left(240)
	if message=="":return
	chat_received.emit(id,str(roster[id].name),message)
	if online:_send_connected("_player_chat",[id,str(roster[id].name),message])

@rpc("authority","call_remote","reliable")
func _player_chat(peer: int,sender: String,message: String) -> void:
	chat_received.emit(peer,sender,message)

@rpc("authority","call_remote","reliable")
func _chat(value: String) -> void:
	message_received.emit(value)

func add_station(ids: Array, locations: Dictionary) -> void:
	var state = State.new()
	state.initialize(ids,locations)
	labs.append(state)

func world_snapshot() -> Dictionary:
	var data: Dictionary=lab.snapshot()
	var extra: Array=[]
	for i in range(1,labs.size()):
		extra.append(labs[i].snapshot())
	if lab_challenge_brief.is_valid():
		data["team_challenge"]=lab_challenge_brief.call(0)
		for i in extra.size():extra[i]["team_challenge"]=lab_challenge_brief.call(i+1)
	data["stations"]=extra
	return data

func set_appearance(data: PackedByteArray) -> void:
	if not data.is_empty() and not preload("res://scripts/avatar_model.gd").valid(data):return
	local_appearance=data
	if not online or multiplayer.is_server():
		appearances[1]=data
		if online:
			for peer in roster:
				if peer!=1:_queue_appearance(peer,1,data)
	elif roster.has(multiplayer.get_unique_id()):
		_queue_appearance(1,multiplayer.get_unique_id(),data)

func _queue_appearance(target: int,peer: int,data: PackedByteArray) -> void:
	appearance_queue.append({"target":target,"peer":peer,"data":data,"offset":0})

func _process(delta: float) -> void:
	_poll_internet_mapping()
	if uses_relay() and was_host:
		relay_pose_clock = minf(relay_pose_clock + delta, relay_pose_interval)
		if relay_pose_dirty and relay_pose_clock >= relay_pose_interval:
			relay_pose_dirty = false
			relay_pose_clock = 0.0
			if not connected_peers().is_empty():
				_poses.rpc(poses)
	if online and was_host and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:
		leave()
		return
	if appearance_queue.is_empty() or not online or multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
	var job: Dictionary=appearance_queue[0]
	if not multiplayer.get_peers().has(job.target):
		appearance_queue.pop_front()
		return
	var end := mini(job.offset+65536,job.data.size())
	_appearance_chunk.rpc_id(job.target,job.peer,job.data.size(),job.offset,job.data.slice(job.offset,end))
	job.offset=end
	if end==job.data.size():appearance_queue.pop_front()

func _poll_internet_mapping() -> void:
	if internet_worker != null:
		if internet_worker.is_alive():
			return
		var result: Dictionary = internet_worker.wait_to_finish()
		internet_worker = null
		if not result.is_empty():
			if result.has("gateway"):
				var newly_mapped := internet_mapping.is_empty()
				internet_mapping = result
				if newly_mapped and internet_port == result.port:
					message_received.emit("Internet hosting · %s · UDP %d" % [result.address, result.port])
			elif internet_port == result.port:
				message_received.emit("Automatic port forwarding failed. Forward UDP %d on your router to host over the internet." % internet_port)
			internet_retry_at = Time.get_ticks_msec() + 300000
	if not internet_mapping.is_empty() and internet_mapping.port != internet_port:
		var previous := internet_mapping
		internet_mapping = {}
		_start_internet_job(_remove_internet_mapping.bind(previous))
	elif internet_port != 0 and Time.get_ticks_msec() >= internet_retry_at:
		_start_internet_job(_open_internet_mapping.bind(internet_port))

func _start_internet_job(work: Callable) -> void:
	internet_worker = Thread.new()
	if internet_worker.start(work) != OK:
		internet_worker = null
		internet_retry_at = Time.get_ticks_msec() + 300000
		message_received.emit("Automatic port forwarding could not start. Use manual UDP forwarding.")

static func _open_internet_mapping(selected_port: int) -> Dictionary:
	var router := UPNP.new()
	if router.discover(1500) != UPNP.UPNP_RESULT_SUCCESS:
		return {"port":selected_port}
	var gateway := router.get_gateway()
	if gateway == null or gateway.add_port_mapping(selected_port, selected_port, "LabVolt College Simulator", "UDP", 600) != UPNP.UPNP_RESULT_SUCCESS:
		return {"port":selected_port}
	return {"gateway":gateway, "port":selected_port, "address":gateway.query_external_address()}

static func _remove_internet_mapping(mapping: Dictionary) -> Dictionary:
	mapping.gateway.delete_port_mapping(mapping.port, "UDP")
	return {}

func _exit_tree() -> void:
	if internet_worker != null:
		var result: Dictionary = internet_worker.wait_to_finish()
		if result.has("gateway"):
			internet_mapping = result
	if not internet_mapping.is_empty():
		_remove_internet_mapping(internet_mapping)

@rpc("any_peer","call_remote","reliable",3)
func _appearance_chunk(peer: int,total: int,offset: int,chunk: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if peer!=sender or not roster.has(sender):return
	elif sender!=1:return
	if total<0 or total>67108864 or chunk.size()>65536 or offset<0 or offset+chunk.size()>total:return
	if offset==0:appearance_incoming[peer]={"total":total,"bytes":PackedByteArray()}
	if not appearance_incoming.has(peer):return
	var pending: Dictionary=appearance_incoming[peer]
	if pending.total!=total or pending.bytes.size()!=offset:
		appearance_incoming.erase(peer)
		return
	pending.bytes.append_array(chunk)
	if pending.bytes.size()!=total:return
	var data: PackedByteArray=pending.bytes
	appearance_incoming.erase(peer)
	if not data.is_empty() and not preload("res://scripts/avatar_model.gd").valid(data):return
	appearances[peer]=data
	appearance_received.emit(peer,data)
	if multiplayer.is_server():
		for target in roster:
			if target!=1 and target!=peer:_queue_appearance(target,peer,data)

func shop_travel(enter: bool) -> void:
	if multiplayer.is_server():_travel(1,enter)
	else:_shop_travel.rpc_id(1,enter)
@rpc("any_peer","call_remote","reliable")
func _shop_travel(enter: bool) -> void:
	if multiplayer.is_server():_travel(multiplayer.get_remote_sender_id(),enter)
func _travel(peer: int,enter: bool) -> void:
	if not roster.has(peer):return
	if enter:
		if shop_returns.has(peer):return
		shop_returns[peer]=poses.get(peer,{}).get("position",(Vector3(13,0,-18) if campus_enabled else Vector3(0,0,1.75)))
		poses[peer]={"position":Vector3(26,0,3),"yaw":0.,"pitch":0.}
	else:
		if not shop_returns.has(peer):return
		poses[peer]={"position":shop_returns[peer],"yaw":0.,"pitch":0.};shop_returns.erase(peer)
	last_pose[peer]=Time.get_ticks_msec()

func connected_peers() -> Array:
	var result: Array=[]
	if not online:return result
	var transport: MultiplayerPeer=multiplayer.multiplayer_peer
	if transport is RelayPeer:
		return Array(multiplayer.get_peers())
	if not transport is ENetMultiplayerPeer:return result
	for peer in multiplayer.get_peers():
		var endpoint: ENetPacketPeer=transport.get_peer(int(peer))
		if endpoint!=null and endpoint.get_state()==ENetPacketPeer.STATE_CONNECTED and endpoint.get_channels()>0:result.append(int(peer))
	return result

func peer_connected_now(peer: int) -> bool:
	return peer==1 or peer in connected_peers()

func _send_connected(method: String,args: Array) -> void:
	for peer in connected_peers():callv("rpc_id",[peer,method]+args)
