extends Node3D
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const PCBRun=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
const PCB_STEP := 0.05
const PCB_CATCHUP_LIMIT := 4
const MAX_PLACEMENTS := 48
const STRUCTURE_CHUNK_TARGET := 32768
const INTEREST_ENTER_DISTANCE_SQUARED := 42.0*42.0
const INTEREST_LEAVE_DISTANCE_SQUARED := 50.0*50.0
signal placement_finished(blueprint_id: String, message: String)
var game: Node
var placed: Dictionary={}
var visuals: Dictionary={}
var simulators: Dictionary={}
var pcb_holders: Dictionary={}
var pcb_panel: Window
var local_hold: Dictionary={}
var send_clock:=0.0
var sync_clock:=0.0
var pending_motion: Dictionary={}
var sent_structure: Dictionary={}
var structural_additions: Dictionary={}
var structural_removals: Array=[]
var pending_blueprint := ""
var last_placement_result := ""

func build(owner_game: Node) -> void:
	game=owner_game
	game.session.restarted.connect(func():
		placed.clear()
		local_hold.clear()
		simulators.clear()
		pcb_holders.clear()
		pending_motion.clear()
		sent_structure.clear()
		structural_additions.clear()
		structural_removals.clear()
		pending_blueprint=""
		_clear_visuals())
	game.session.roster_changed.connect(_roster_changed)

func _roster_changed() -> void:
	if not multiplayer.is_server():return
	for key in placed.keys():
		if not game.session.roster.has(int(placed[key].owner)):_remove_placed(key)
		else:
			for control in ["A","B"]:
				if int(placed[key].holder[control]) != 0 and not game.session.roster.has(int(placed[key].holder[control])):
					placed[key].state[control]=false
					placed[key].holder[control]=0
	for holder_key in pcb_holders.keys():
		if not game.session.roster.has(int(pcb_holders[holder_key].peer)):
			_release_pcb(holder_key)
	_sync()

func _remove_placed(key: String) -> void:
	placed.erase(key)
	simulators.erase(key)
	pending_motion.erase(key)
	if visuals.has(key):
		var view: Node3D=visuals[key]
		remove_child(view)
		view.queue_free()
		visuals.erase(key)
	for holder_key in pcb_holders.keys():
		if pcb_holders[holder_key].key==key:pcb_holders.erase(holder_key)

func request_place(id: String) -> String:
	if not game.front.in_game:return "Enter the game before placing an invention."
	if not pending_blueprint.is_empty():return "A placement request is already pending."
	if int(game.electronics.profile.data.get("invention_copies",{}).get(id,0))<1:return "Fabricate a copy first."
	var design: Dictionary=game.electronics.profile.data.get("inventions",{}).get(id,{})
	var drive: Dictionary=design.get("drive",{"A":"manual","B":"manual"})
	if drive.get("A","manual")!="manual" or drive.get("B","manual")!="manual":
		var live:=0
		for item in placed.values():
			if item.drive.A!="manual" or item.drive.B!="manual":live+=1
		if live>=8:return "Eight live PCB inventions are already placed. Retrieve one first."
	pending_blueprint=id
	if multiplayer.is_server():return _apply_place_local(id)
	command.rpc_id(1,{"op":"place","id":id})
	return "Waiting for placement confirmation."

func _apply_place_local(id: String) -> String:
	_apply(multiplayer.get_unique_id(),{"op":"place","id":id})
	return last_placement_result

func interact(target: Node,right: bool=false) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","") not in ["invention","invention_control","invention_pcb","invention_hinge"]:return false
	var key:=str(target.get_meta("invention_key",""))
	if not placed.has(key):return true
	if target.get_meta("role")=="invention_hinge":
		_request({"op":"hinge","key":key,"joint":target.get_meta("joint")})
		return true
	if target.get_meta("role")=="invention":
		if int(placed[key].owner)==multiplayer.get_unique_id():_request({"op":"pickup","key":key})
		else:game.ui.log_message("Only the owner can retrieve this invention.")
		return true
	if target.get_meta("role")=="invention_pcb":
		if is_instance_valid(pcb_panel):pcb_panel.queue_free()
		pcb_panel=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_panel.gd").new()
		add_child(pcb_panel);pcb_panel.open_board(game,key)
		return true
	var control:=str(target.get_meta("control","A"))
	var mode:=str(placed[key].controls.get(control,"hold"))
	if mode=="hold":
		local_hold={"key":key,"control":control,"right":right}
		_request({"op":"control","key":key,"control":control,"pressed":true})
	else:_request({"op":"control","key":key,"control":control,"pressed":true})
	return true

func _request(action: Dictionary) -> void:
	if multiplayer.is_server():_apply(multiplayer.get_unique_id(),action)
	else:command.rpc_id(1,action)

func request_pcb_input(key: String,id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> void:
	_request({"op":"pcb_input","key":key,"id":id,"pressed":pressed,"reverse":reverse,"command":command})

@rpc("any_peer","call_remote","reliable")
func command(action: Dictionary) -> void:
	if multiplayer.is_server():_apply(multiplayer.get_remote_sender_id(),action)

func _profile(peer: int) -> Dictionary:
	if game.session.online:
		var authority=game.electronics_trade.authority
		if not authority.healthy:return {}
		return authority.ledger.account(peer).get("profile",{})
	return game.electronics.profile.data if peer==1 else {}

func _pose(peer: int) -> Vector3:
	return game.player.global_position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)

func _apply(peer: int,action: Dictionary) -> void:
	if not game.session.roster.has(peer) or var_to_bytes(action).size()>512:return
	var op:=str(action.get("op",""))
	if op=="place":
		var id:=str(action.get("id",""))
		var profile:=_profile(peer)
		var designs: Dictionary=profile.get("inventions",{})
		var copies:=int(profile.get("invention_copies",{}).get(id,0))
		if copies<1 or copies>100:_placement_result(peer,"You have no fabricated copies available.");return
		if Model.validate(id,designs,profile.get("blueprints",{}))!="":_placement_result(peer,"The host could not validate this blueprint.");return
		var slot:=0
		while placed.has(_key(peer,id,slot)) and slot<copies:slot+=1
		if slot>=copies:_placement_result(peer,"All fabricated copies of this invention are already placed.");return
		if placed.size()>=MAX_PLACEMENTS:_placement_result(peer,"The maximum number of active inventions has been reached.");return
		var parts:=Model.flattened(id,designs,profile.get("blueprints",{}))
		var drive: Dictionary=designs[id].get("drive",{"A":"manual","B":"manual"}).duplicate(true)
		var wants_pcb: bool=drive.A!="manual" or drive.B!="manual"
		var pcb_runtime: RefCounted
		if wants_pcb:
			if simulators.size()>=8:_placement_result(peer,"Eight live PCB inventions are already placed.");return
			var mounted: Array=parts.filter(func(part):return part.type=="pcb" and part.has("pin_map"))
			if mounted.size()!=1:_placement_result(peer,"The blueprint needs one mapped PCB.");return
			pcb_runtime=PCBRun.new()
			if not pcb_runtime.configure(str(mounted[0].ref),profile.get("blueprints",{}),mounted[0].pin_map):_placement_result(peer,"The mounted PCB could not start.");return
		var bounds:=_bounds(parts)
		var pose:=_pose(peer)
		var position:=_placement(pose,peer,bounds)
		if position==Vector3.INF:_placement_result(peer,"Not enough clear space to place this invention.");return
		var features:={"battery":false,"wheel":false,"motor_a":false,"motor_b":false,"switch_a":false,"switch_b":false}
		for part in parts:
			if part.type=="battery":features.battery=true
			elif part.type=="wheel":features.wheel=true
			elif part.type=="dc_motor":features["motor_"+str(part.control).to_lower()]=true
			elif part.type=="switch":features["switch_"+str(part.control).to_lower()]=true
		Model.connect_wheels(parts)
		var key:=_key(peer,id,slot)
		placed[key]={"owner":peer,"id":id,"name":str(designs[id].name),"parts":parts,"bounds":bounds,"features":features,"controls":designs[id].controls.duplicate(true),"drive":drive,"state":{"A":false,"B":false},"effective":{"A":false,"B":false},"pcb_voltage":{"A":0.0,"B":0.0},"pcb_error":"","pcb_inputs":pcb_runtime.inputs.duplicate(true) if wants_pcb else [],"expiry":{"A":0,"B":0},"holder":{"A":0,"B":0},"position":position,"yaw":0.0,"angle":0.0}
		placed[key]["hinge_angles"]={}
		visuals[key]=_create_view(key,placed[key])
		if wants_pcb:simulators[key]={"runtime":pcb_runtime,"clock":0.0}
		_sync()
		_placement_result(peer,"Invention placed successfully.")
		return
	var key:=str(action.get("key",""))
	if key.length()>110 or not placed.has(key):return
	var item: Dictionary=placed[key]
	if _pose(peer).distance_to(item.position)>3.5:return
	if op=="hinge":
		var joint_index: Variant=action.get("joint")
		var view: Node3D=visuals.get(key)
		if not joint_index is int or not is_instance_valid(view):return
		var joints: Array=view.get_meta("joints",[])
		if joint_index<0 or joint_index>=joints.size() or joints[joint_index].control!="":return
		var joint: Dictionary=joints[joint_index]
		if joint.chain.is_empty() or _pose(peer).distance_to(view.to_global(Model.hinge_pose(joints,joint.chain)*joint.pivot))>3.5:return
		joints[joint_index].manual=not bool(joints[joint_index].manual)
		return
	if op=="pickup":
		if peer!=int(item.owner):return
		_remove_placed(key);_sync();return
	if op=="pcb_input":
		if not simulators.has(key) or not action.get("id") is String or not action.get("pressed") is bool or not action.get("reverse",false) is bool or not action.get("command",{}) is Dictionary or action.get("command",{}).size()>8:return
		var input_id:=str(action.id)
		if input_id.length()>96:return
		var input_record: Dictionary={}
		for entry in item.pcb_inputs:
			if entry.id==input_id:input_record=entry;break
		if input_record.is_empty():return
		var command_data: Dictionary=action.get("command",{})
		var holder_key:=key+"|"+input_id+":"+str(command_data.get("key",""))
		var holdable: bool=input_record.kind=="button" or str(command_data.get("op","")) in ["key","press","touch"] or (not action.pressed and input_record.kind in ["xpt2046","io_joystick"])
		var holder: Dictionary=pcb_holders.get(holder_key,{})
		# The joystick axes share the push-button lease. Another player cannot
		# steer a held joystick by sending an unleased move command.
		if input_record.kind=="io_joystick" and str(command_data.get("op",""))=="move":
			if int(holder.get("peer",0)) not in [0,peer] and Time.get_ticks_msec()<=int(holder.get("expiry",0)):return
		if holdable:
			if action.pressed and int(holder.get("peer",0)) not in [0,peer] and Time.get_ticks_msec()<=int(holder.get("expiry",0)):return
			if not action.pressed and int(holder.get("peer",0))!=peer:return
		# Do not acquire, renew or release a lease for a command the actual
		# circuit/input reducer rejected. Otherwise stale or invalid input can
		# lock other players out without changing the device.
		if not simulators[key].runtime.input(input_id,action.pressed,action.reverse,command_data):return
		if holdable:
			if action.pressed:pcb_holders[holder_key]={"peer":peer,"expiry":Time.get_ticks_msec()+650,"key":key,"id":input_id,"command":command_data.duplicate(true)}
			else:pcb_holders.erase(holder_key)
		return
	if op!="control":return
	var control:=str(action.get("control",""))
	if control not in ["A","B"] or not action.get("pressed") is bool:return
	if not bool(item.features.get("switch_"+control.to_lower(),false)):return
	var mode:=str(item.controls.get(control,""))
	if mode=="hold":
		if action.pressed and int(item.holder[control]) not in [0,peer] and Time.get_ticks_msec()<=int(item.expiry[control]):return
		if not action.pressed and int(item.holder[control])!=peer:return
		item.state[control]=bool(action.pressed)
		item.expiry[control]=Time.get_ticks_msec()+650 if action.pressed else 0
		item.holder[control]=peer if action.pressed else 0
	elif mode=="toggle" and action.pressed:item.state[control]=not bool(item.state[control])
	else:return
	pending_motion[key]=true

func _key(peer: int,id: String,slot: int) -> String:return "%d:%s:%d"%[peer,id,slot]

func _part_center(part: Dictionary) -> Vector3:
	return Vector3(float(part.x),float(part.y),float(part.z))*.3+Vector3(0,.36,0)

func _part_size(kind: String) -> Vector3:
	if kind=="wheel":return Vector3(.09,.28,.28)
	if kind in ["pcb","battery","switch"]:return Vector3(.24,.12,.24)
	return Vector3(.28,.2,.28)

func _bounds(parts: Array) -> Dictionary:
	var low:=Vector3.INF
	var high:=-Vector3.INF
	for part in parts:
		var point:=_part_center(part)
		var extent:=_part_size(str(part.type))
		if int(part.get("turns",0))%2==1:extent=Vector3(extent.z,extent.y,extent.x)
		var half:=extent*.5
		low=low.min(point-half)
		high=high.max(point+half)
	return {"center":(low+high)*.5,"size":high-low}

func _clear_space(position: Vector3,bounds: Dictionary,exclude: Array[RID]=[]) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	var shape:=BoxShape3D.new();shape.size=bounds.size
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,position+bounds.center);query.collision_mask=1
	query.exclude=exclude
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _placement(pose: Vector3,peer: int,bounds: Dictionary) -> Vector3:
	if pose.y < -0.5 or pose.y>10:return Vector3.INF
	var yaw: float=game.player.rotation.y if peer==1 else float(game.session.poses.get(peer,{}).get("yaw",0.0))
	for offset in [Vector3(0,0,-1.4),Vector3(1.4,0,0),Vector3(-1.4,0,0),Vector3(0,0,1.4)]:
		var candidate: Vector3=pose+offset.rotated(Vector3.UP,yaw)
		var query:=PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.15,candidate-Vector3.UP*2.0,1)
		var ground:=get_world_3d().direct_space_state.intersect_ray(query)
		if ground.is_empty() or ground.normal.y<.95:continue
		var feet_y:=float(ground.position.y)
		candidate.y=feet_y-float(bounds.center.y)+float(bounds.size.y)*.5+.015
		var room_id: String=str(game.campus.registry.locate(candidate))
		if room_id in ["exterior","stairs","lobby"]:continue
		var near:=false
		var volume:=AABB(candidate+bounds.center-bounds.size*.5,bounds.size)
		for other in placed.values():
			var box: Dictionary=other.bounds
			if volume.intersects(AABB(other.position+box.center-box.size*.5,box.size)):near=true;break
		if near:continue
		if _clear_space(candidate,bounds):return candidate
	return Vector3.INF

func _sync() -> void:
	if not game.session.online or not multiplayer.is_server():return
	var peers: Array=game.session.connected_peers()
	for peer in sent_structure.keys():
		if peer not in peers:sent_structure.erase(peer)
	var row_sizes: Dictionary={}
	for peer in peers:
		var previous: Dictionary=sent_structure.get(peer,{})
		var pose: Vector3=_pose(peer)
		var keys: Dictionary={}
		for key in placed:
			var item: Dictionary=placed[key]
			var limit:=INTEREST_LEAVE_DISTANCE_SQUARED if previous.has(key) else INTEREST_ENTER_DISTANCE_SQUARED
			if int(item.owner)==peer or pose.distance_squared_to(item.position)<=limit:keys[key]=true
		if previous==keys and sent_structure.has(peer):continue
		var removed: Array=[]
		for key in previous:
			if not keys.has(key):removed.append(key)
		var chunk: Dictionary={}
		var total_bytes:=0
		for key in keys:
			if previous.has(key):continue
			if not row_sizes.has(key):row_sizes[key]=var_to_bytes({key:placed[key]}).size()
			var row_bytes: int=row_sizes[key]
			if not chunk.is_empty() and total_bytes+row_bytes>STRUCTURE_CHUNK_TARGET:
				receive.rpc_id(peer,chunk,removed,false)
				chunk={}
				removed=[]
				total_bytes=0
			chunk[key]=placed[key]
			total_bytes+=row_bytes
		# An empty final packet also closes a first sync with no placed items.
		receive.rpc_id(peer,chunk,removed,true)
		sent_structure[peer]=keys

func _placement_result(peer: int,message: String) -> void:
	if peer==1:receive_placement(message)
	elif game.session.roster.has(peer):receive_placement.rpc_id(peer,message)

@rpc("authority","call_remote","reliable")
func receive_placement(message: String) -> void:
	var blueprint_id:=pending_blueprint
	pending_blueprint=""
	last_placement_result=message
	notice(message)
	placement_finished.emit(blueprint_id,message)

@rpc("authority","call_remote","reliable")
func notice(message: String) -> void:
	if is_instance_valid(game) and is_instance_valid(game.ui):game.ui.log_message(message.left(140))

@rpc("authority","call_remote","reliable")
func receive(additions: Dictionary,removals: Array,final: bool) -> void:
	if additions.size()>MAX_PLACEMENTS or removals.size()>MAX_PLACEMENTS or var_to_bytes(additions).size()>131072:
		structural_additions.clear()
		structural_removals.clear()
		return
	structural_additions.merge(additions,true)
	structural_removals.append_array(removals)
	if not final:return
	for key in structural_removals:placed.erase(key)
	placed.merge(structural_additions,true)
	structural_additions.clear()
	structural_removals.clear()

# Reliable updates share the structural channel, so an old update cannot
# affect a new invention reusing a retrieved copy's slot.
@rpc("authority","call_remote","reliable")
func receive_motion(updates: Dictionary) -> void:
	for key in updates:
		if placed.has(key):
			placed[key].merge(updates[key],true)

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if is_instance_valid(pcb_panel) and not placed.has(pcb_panel.key):
		pcb_panel._close()
	if not local_hold.is_empty():
		var pressed:=Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT if local_hold.right else MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(game.player.keys.interact)
		if not pressed or not game.player.enabled:
			_request({"op":"control","key":local_hold.key,"control":local_hold.control,"pressed":false})
			local_hold.clear()
		else:
			send_clock+=delta
			if send_clock>.25:
				send_clock=0
				_request({"op":"control","key":local_hold.key,"control":local_hold.control,"pressed":true})
	for key in visuals.keys():
		if not placed.has(key):visuals[key].queue_free();visuals.erase(key)
	for key in placed:
		var item: Dictionary=placed[key]
		if not visuals.has(key):visuals[key]=_create_view(key,item)
		var root: Node3D=visuals[key]
		root.position=item.position if multiplayer.is_server() else root.position.lerp(item.position,1.0-exp(-delta*18.0))
		root.rotation.y=float(item.yaw)
		for control in ["A","B"]:
			var button:=root.find_child("Control"+control,true,false) as Node3D
			if is_instance_valid(button):button.position.y=.10 if item.state[control] else .14
		for shaft in root.get_meta("shafts",[]):
			if shaft.get_meta("kind")=="wheel" and item.effective.get(shaft.get_meta("control",""),false):shaft.rotation.x=float(item.angle)
		if not multiplayer.is_server():
			var joints: Array=root.get_meta("joints",[])
			var articulation_changed:=false
			for joint in joints:
				if joint.chain.is_empty():continue
				var angle: float=item.get("hinge_angles",{}).get(joint.index,0.0)
				var next:=move_toward(float(joint.angle),angle,Model.HINGE_SPEED*delta)
				articulation_changed=articulation_changed or not is_equal_approx(next,float(joint.angle))
				joint.angle=next
			if articulation_changed:_apply_hinges(joints)

func _apply_hinges(joints: Array) -> void:
	for joint in joints:
		var pose:=Model.hinge_pose(joints,joint.chain)
		for binding in joint.bindings:binding.node.transform=pose*binding.rest

func _hinge_clear(view: Node3D,joint: Dictionary,angle: float) -> bool:
	var solid: StaticBody3D=view.get_node("Solid")
	var query:=PhysicsShapeQueryParameters3D.new()
	query.collision_mask=1
	query.exclude=[solid.get_rid()]
	var space:=get_world_3d().direct_space_state
	var joints: Array=view.get_meta("joints",[])
	for affected in joints:
		if joint.index not in affected.chain:continue
		var pose:=Model.hinge_pose(joints,affected.chain,joint.index,angle)
		for binding in affected.bindings:
			var collider:=binding.node as CollisionShape3D
			if collider==null or collider.get_parent()!=solid:continue
			query.shape=collider.shape
			query.transform=solid.global_transform*pose*binding.rest
			if not space.intersect_shape(query,1).is_empty():return false
	return true

func _release_pcb(holder_key: String) -> void:
	var holder: Dictionary=pcb_holders[holder_key]
	if simulators.has(holder.key):
		var release: Dictionary=holder.get("command",{}).duplicate(true)
		if str(release.get("op","")) in ["touch","press"]:release={"op":"release"}
		elif release.has("pressed"):release.pressed=false
		simulators[holder.key].runtime.input(str(holder.id),false,false,release)
	pcb_holders.erase(holder_key)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not multiplayer.is_server():return
	var now:=Time.get_ticks_msec()
	for holder_key in pcb_holders.keys():
		var holder: Dictionary=pcb_holders[holder_key]
		if now>int(holder.expiry):_release_pcb(holder_key)
	for key in placed:
		var item: Dictionary=placed[key]
		var changed:=false
		if simulators.has(key):
			var simulator: Dictionary=simulators[key]
			simulator.clock+=delta
			var steps:=0
			while float(simulator.clock)+0.000001>=PCB_STEP and steps<PCB_CATCHUP_LIMIT:
				var pcb_result: Dictionary=simulator.runtime.tick(PCB_STEP)
				simulator.clock=maxf(0.0,float(simulator.clock)-PCB_STEP)
				steps+=1
				var pcb_error: String=str(pcb_result.get("error","")) if not pcb_result.get("ok",false) else ""
				if pcb_error!=str(item.pcb_error):item.pcb_error=pcb_error;changed=true
				for control in ["A","B"]:
					var voltage: float=float(pcb_result.get(control,0.0)) if pcb_result.get("ok",false) else 0.0
					var previous: float=float(item.pcb_voltage[control])
					# A small change across the activation knee is significant
					# even when it falls below the 10 mV telemetry deadband.
					var crossed_threshold: bool=(voltage>=2.5)!=(previous>=2.5)
					if absf(voltage-previous)>.01 or crossed_threshold:
						item.pcb_voltage[control]=voltage
						changed=true
		for control in ["A","B"]:
			if item.controls[control]=="hold" and item.state[control] and now>int(item.expiry[control]):item.state[control]=false;item.holder[control]=0;changed=true
			var effective:=Model.energized(item.drive[control],item.state[control],item.pcb_voltage[control])
			if effective!=bool(item.effective[control]):item.effective[control]=effective;changed=true
		var hinge_view: Node3D=visuals.get(key)
		if is_instance_valid(hinge_view):
			var joints: Array=hinge_view.get_meta("joints",[])
			var articulation_changed:=false
			for joint in joints:
				if joint.chain.is_empty():continue
				var angle: float
				if joint.control=="":
					angle=move_toward(float(joint.angle),Model.HINGE_OPEN if joint.manual else 0.0,Model.HINGE_SPEED*delta)
				else:
					angle=Model.hinge_angle(joint.angle,joint.control,item.effective,item.features.battery,delta)
				if not is_equal_approx(angle,float(joint.angle)) and _hinge_clear(hinge_view,joint,angle):
					joint.angle=angle
					item.hinge_angles[joint.index]=angle
					articulation_changed=true
					changed=true
			if articulation_changed:_apply_hinges(joints)
		var drive_direction:=Vector3.ZERO
		if item.features.battery:
			for part in item.parts:
				if part.type=="wheel" and item.effective.get(part.get("motor_control",""),false):
					drive_direction=Vector3(Model.rotate_grid(Vector3i.FORWARD,int(part.get("turns",0))))
					break
		if drive_direction!=Vector3.ZERO:
			var view: StaticBody3D=visuals.get(key)
			var solid: StaticBody3D=view.get_node("Solid") if is_instance_valid(view) else null
			var next: Vector3=item.position+(drive_direction*delta*.5).rotated(Vector3.UP,float(item.yaw))
			if is_instance_valid(solid) and game.campus.registry.locate(next)==game.campus.registry.locate(item.position):
				if _clear_space(next,item.bounds,[solid.get_rid()]):
					item.position=next
					view.position=next
					item.angle=wrapf(float(item.angle)+delta*.5/.14,0,TAU)
					changed=true
		if changed:pending_motion[key]=true
	sync_clock+=delta
	if sync_clock<.1:return
	sync_clock=fmod(sync_clock,.1)
	_sync()
	if game.session.online and not pending_motion.is_empty():
		var updates: Dictionary={}
		for key in pending_motion:
			var item: Dictionary=placed[key]
			updates[key]={"position":item.position,"yaw":item.yaw,"angle":item.angle,"state":item.state,"effective":item.effective,"pcb_voltage":item.pcb_voltage,"pcb_error":item.pcb_error,"hinge_angles":item.hinge_angles}
		for peer in sent_structure:
			var visible: Dictionary={}
			for key in updates:
				if sent_structure[peer].has(key):visible[key]=updates[key]
			if not visible.is_empty():receive_motion.rpc_id(peer,visible)
	pending_motion.clear()

func _create_view(key: String,item: Dictionary) -> StaticBody3D:
	var root:=StaticBody3D.new();root.collision_layer=4;root.collision_mask=0
	root.set_meta("role","invention");root.set_meta("invention_key",key);root.set_meta("label",str(item.name)+" · retrieve")
	add_child(root)
	root.position=item.position
	var solid:=StaticBody3D.new()
	solid.name="Solid";solid.collision_layer=1;solid.collision_mask=0;root.add_child(solid)
	var shafts: Array=[]
	var bindings: Array=[]
	var switch_mounts: Dictionary={}
	for part in item.parts:
		var kind:=str(part.type)
		var pivot:=Node3D.new();pivot.position=_part_center(part);root.add_child(pivot)
		pivot.rotation.y=float(part.get("turns",0))*PI*.5
		pivot.set_meta("assembly_kind",kind)
		if kind=="switch" and str(part.get("control","")) in ["A","B"] and not switch_mounts.has(str(part.control)):
			switch_mounts[str(part.control)]=pivot
		var part_hit:=CollisionShape3D.new()
		var part_box:=BoxShape3D.new();part_box.size=_part_size(kind);part_hit.shape=part_box;part_hit.position=pivot.position;solid.add_child(part_hit)
		part_hit.rotation.y=pivot.rotation.y
		var moving_nodes: Array=[{"node":pivot,"rest":pivot.transform},{"node":part_hit,"rest":part_hit.transform}]
		var interaction_shape:=CollisionShape3D.new()
		interaction_shape.shape=part_box
		interaction_shape.transform=part_hit.transform
		root.add_child(interaction_shape)
		moving_nodes.append({"node":interaction_shape,"rest":interaction_shape.transform})
		bindings.append(moving_nodes)
		var mesh:=MeshInstance3D.new()
		if kind=="wheel":
			var cylinder:=CylinderMesh.new();cylinder.top_radius=.14;cylinder.bottom_radius=.14;cylinder.height=.09;mesh.mesh=cylinder;mesh.rotation.z=PI/2
			# Roll on a child axis so a hinge can rotate the entire wheel mount.
			var shaft:=Node3D.new()
			shaft.set_meta("kind",kind)
			shaft.set_meta("control",part.get("motor_control",""))
			pivot.add_child(shaft)
			shaft.add_child(mesh)
			shafts.append(shaft)
		else:
			var box:=BoxMesh.new();box.size=_part_size(kind);mesh.mesh=box
			pivot.add_child(mesh)
		var material:=StandardMaterial3D.new();material.albedo_color=Color(str(Model.PARTS.get(kind,{}).get("color","777777")));mesh.material_override=material
		if kind=="pcb" and part.has("pin_map") and (item.drive.A!="manual" or item.drive.B!="manual"):
			var pcb_target:=StaticBody3D.new();pcb_target.collision_layer=4;pcb_target.collision_mask=0;pcb_target.position=pivot.position+Vector3(0,.24,0);root.add_child(pcb_target)
			pcb_target.set_meta("role","invention_pcb");pcb_target.set_meta("invention_key",key);pcb_target.set_meta("label",str(item.name)+" · inspect live PCB")
			var pcb_hit:=CollisionShape3D.new();var pcb_shape:=BoxShape3D.new();pcb_shape.size=Vector3(.28,.16,.28);pcb_hit.shape=pcb_shape;pcb_target.add_child(pcb_hit)
			moving_nodes.append({"node":pcb_target,"rest":pcb_target.transform})
	root.set_meta("shafts",shafts)
	var joints:=Model.hinges(item.parts)
	for index in joints.size():
		var joint:=joints[index]
		joint.pivot.y+=.22 # The editor displays the same grid below the installed body.
		joint.index=index
		joint.angle=float(item.get("hinge_angles",{}).get(index,0.0))
		joint.manual=false
		joint.bindings=[]
		for part_index in joint.indices:joint.bindings.append_array(bindings[part_index])
		if joint.control=="" and not joint.chain.is_empty():
			var target:=StaticBody3D.new()
			target.collision_layer=4
			target.collision_mask=0
			target.position=joint.pivot
			root.add_child(target)
			target.set_meta("role","invention_hinge")
			target.set_meta("invention_key",key)
			target.set_meta("joint",index)
			target.set_meta("label",str(item.name)+" · swing hinge")
			var shape:=CollisionShape3D.new()
			var box:=BoxShape3D.new()
			box.size=Vector3(.3,.3,.3)
			shape.shape=box
			target.add_child(shape)
			bindings[joint.part_index].append({"node":target,"rest":target.transform})
	for joint in joints:
		if joint.chain.size()>1:joints[joint.chain[-2]].bindings.append_array(bindings[joint.part_index])
	root.set_meta("joints",joints)
	_apply_hinges(joints)
	for control in ["A","B"]:
		if not item.features.get("switch_"+control.to_lower(),false):continue
		var mount: Node3D=switch_mounts.get(control)
		if not is_instance_valid(mount):continue
		# The physical button belongs to the actual placed switch, even if its
		# subassembly moves on a hinge. It must not float at a fixed root offset.
		var button:=StaticBody3D.new();button.name="Control"+control;button.collision_layer=4;button.collision_mask=0;button.position=Vector3(0,.14,0);mount.add_child(button)
		button.set_meta("role","invention_control");button.set_meta("invention_key",key);button.set_meta("control",control);button.set_meta("label",str(item.name)+" · control "+control+" ("+str(item.controls[control])+")")
		var cap:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.18,.1,.18);cap.mesh=box;button.add_child(cap)
		var color:=StandardMaterial3D.new();color.albedo_color=Color("e2ad65" if control=="A" else "83cae0");cap.material_override=color
		var button_hit:=CollisionShape3D.new();var button_shape:=BoxShape3D.new();button_shape.size=Vector3(.22,.13,.22);button_hit.shape=button_shape;button.add_child(button_hit)
	return root

func _clear_visuals() -> void:
	for view in visuals.values():if is_instance_valid(view):view.queue_free()
	visuals.clear()
