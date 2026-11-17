extends Node3D
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const PCBRun=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
var game: Node
var placed: Dictionary={}
var visuals: Dictionary={}
var simulators: Dictionary={}
var pcb_holders: Dictionary={}
var pcb_panel: Window
var local_hold: Dictionary={}
var send_clock:=0.0
var sync_clock:=0.0

func build(owner_game: Node) -> void:
	game=owner_game
	game.session.restarted.connect(func():placed.clear();local_hold.clear();simulators.clear();pcb_holders.clear();_clear_visuals())
	game.session.roster_changed.connect(_roster_changed)

func _roster_changed() -> void:
	if not multiplayer.is_server():return
	for key in placed.keys():
		if not game.session.roster.has(int(placed[key].owner)):placed.erase(key);simulators.erase(key)
	_sync()

func request_place(id: String) -> String:
	if not game.front.in_game:return "Enter the game before placing an invention."
	if int(game.electronics.profile.data.get("invention_copies",{}).get(id,0))<1:return "Fabricate a copy first."
	var design: Dictionary=game.electronics.profile.data.get("inventions",{}).get(id,{})
	var drive: Dictionary=design.get("drive",{"A":"manual","B":"manual"})
	if drive.get("A","manual")!="manual" or drive.get("B","manual")!="manual":
		var live:=0
		for item in placed.values():
			if item.drive.A!="manual" or item.drive.B!="manual":live+=1
		if live>=8:return "Eight live PCB inventions are already placed. Retrieve one first."
	if multiplayer.is_server():_apply(multiplayer.get_unique_id(),{"op":"place","id":id})
	else:command.rpc_id(1,{"op":"place","id":id})
	return "Placing invention in front of you."

func interact(target: Node,right: bool=false) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","") not in ["invention","invention_control","invention_pcb"]:return false
	var key:=str(target.get_meta("invention_key",""))
	if not placed.has(key):return true
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
		if copies<1 or copies>100 or Model.validate(id,designs,profile.get("blueprints",{}))!="":return
		var slot:=0
		while placed.has(_key(peer,id,slot)) and slot<copies:slot+=1
		if slot>=copies:_notice(peer,"All fabricated copies of this invention are already placed.");return
		if placed.size()>=48:_notice(peer,"The world invention limit is reached.");return
		var parts:=Model.flattened(id,designs,profile.get("blueprints",{}))
		var drive: Dictionary=designs[id].get("drive",{"A":"manual","B":"manual"}).duplicate(true)
		var wants_pcb: bool=drive.A!="manual" or drive.B!="manual"
		var pcb_runtime: RefCounted
		if wants_pcb:
			if simulators.size()>=8:_notice(peer,"Eight live PCB inventions are already placed.");return
			var mounted: Array=parts.filter(func(part):return part.type=="pcb" and part.has("pin_map"))
			if mounted.size()!=1:return
			pcb_runtime=PCBRun.new()
			if not pcb_runtime.configure(str(mounted[0].ref),profile.get("blueprints",{}),mounted[0].pin_map):return
		var bounds:=_bounds(parts)
		var pose:=_pose(peer)
		var position:=_placement(pose,peer,bounds)
		if position==Vector3.INF:_notice(peer,"No clear space near you for this invention.");return
		var features:={"battery":false,"wheel":false,"motor_a":false,"motor_b":false,"switch_a":false,"switch_b":false}
		for part in parts:
			if part.type=="battery":features.battery=true
			elif part.type=="wheel":features.wheel=true
			elif part.type=="dc_motor":features["motor_"+str(part.control).to_lower()]=true
			elif part.type=="switch":features["switch_"+str(part.control).to_lower()]=true
		var key:=_key(peer,id,slot)
		placed[key]={"owner":peer,"id":id,"name":str(designs[id].name),"parts":parts,"bounds":bounds,"features":features,"controls":designs[id].controls.duplicate(true),"drive":drive,"state":{"A":false,"B":false},"effective":{"A":false,"B":false},"pcb_voltage":{"A":0.0,"B":0.0},"pcb_error":"","pcb_inputs":pcb_runtime.inputs.duplicate(true) if wants_pcb else [],"expiry":{"A":0,"B":0},"holder":{"A":0,"B":0},"position":position,"yaw":0.0,"angle":0.0}
		if wants_pcb:simulators[key]={"runtime":pcb_runtime,"clock":0.0}
		_sync();return
	var key:=str(action.get("key",""))
	if key.length()>110 or not placed.has(key):return
	var item: Dictionary=placed[key]
	if _pose(peer).distance_to(item.position)>3.5:return
	if op=="pickup":
		if peer!=int(item.owner):return
		placed.erase(key);simulators.erase(key);_sync();return
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
		var holdable: bool=input_record.kind=="button" or str(command_data.get("op","")) in ["key","press","touch"] or (not action.pressed and input_record.kind=="xpt2046")
		if holdable:
			var holder: Dictionary=pcb_holders.get(holder_key,{})
			if action.pressed and int(holder.get("peer",0)) not in [0,peer] and Time.get_ticks_msec()<=int(holder.get("expiry",0)):return
			if not action.pressed and int(holder.get("peer",0))!=peer:return
			if action.pressed:pcb_holders[holder_key]={"peer":peer,"expiry":Time.get_ticks_msec()+650,"key":key,"id":input_id,"command":command_data.duplicate(true)}
			else:pcb_holders.erase(holder_key)
		if simulators[key].runtime.input(input_id,action.pressed,action.reverse,command_data):simulators[key].clock=.05
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
	_sync()

func _key(peer: int,id: String,slot: int) -> String:return "%d:%s:%d"%[peer,id,slot]

func _bounds(parts: Array) -> Dictionary:
	var low:=Vector3(-.36,.10,-.36)
	var high:=Vector3(.36,.72,.36)
	for part in parts:
		var point:=Vector3(float(part.x),float(part.y),float(part.z))*.3+Vector3(0,.36,0)
		low=low.min(point-Vector3(.17,.14,.17))
		high=high.max(point+Vector3(.17,.17,.17))
	return {"center":(low+high)*.5,"size":high-low}

func _clear_space(position: Vector3,bounds: Dictionary) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	var shape:=BoxShape3D.new();shape.size=bounds.size
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,position+bounds.center);query.collision_mask=1
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _placement(pose: Vector3,peer: int,bounds: Dictionary) -> Vector3:
	if pose.y < -0.5 or pose.y>10:return Vector3.INF
	var yaw: float=game.player.rotation.y if peer==1 else float(game.session.poses.get(peer,{}).get("yaw",0.0))
	for offset in [Vector3(0,0,-1.4),Vector3(1.4,0,0),Vector3(-1.4,0,0),Vector3(0,0,1.4)]:
		var candidate: Vector3=pose+offset.rotated(Vector3.UP,yaw)
		candidate.y=5.0 if pose.y>3 else 0.0
		var room_id: String=str(game.campus.registry.locate(candidate))
		if room_id in ["exterior","stairs","lobby"]:continue
		var near:=false
		for other in placed.values():
			if candidate.distance_to(other.position)<1.2:near=true;break
		if near:continue
		if _clear_space(candidate,bounds):return candidate
	return Vector3.INF

func _sync() -> void:
	if game.session.online and multiplayer.is_server():
		for peer in game.session.connected_peers():receive.rpc_id(peer,placed)

func _notice(peer: int,message: String) -> void:
	if peer==1:notice(message)
	elif game.session.roster.has(peer):notice.rpc_id(peer,message)

@rpc("authority","call_remote","reliable")
func notice(message: String) -> void:
	if is_instance_valid(game) and is_instance_valid(game.ui):game.ui.log_message(message.left(140))

@rpc("authority","call_remote","reliable")
func receive(snapshot: Dictionary) -> void:
	if snapshot.size()>48 or var_to_bytes(snapshot).size()>131072:return
	placed=snapshot

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
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
		root.position=item.position;root.rotation.y=float(item.yaw)
		for control in ["A","B"]:
			var button:=root.get_node_or_null("Control"+control) as Node3D
			if is_instance_valid(button):button.position.y=.62 if item.state[control] else .66
		for shaft in root.get_meta("shafts",[]):
			if shaft.get_meta("kind")=="wheel":shaft.rotation.x=float(item.angle)
			elif shaft.get_meta("kind")=="servo":shaft.rotation.y=deg_to_rad(65.0 if item.effective.get(shaft.get_meta("control","B"),false) else -65.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not multiplayer.is_server():return
	var changed:=false
	var now:=Time.get_ticks_msec()
	for holder_key in pcb_holders.keys():
		var holder: Dictionary=pcb_holders[holder_key]
		if now>int(holder.expiry):
			if simulators.has(holder.key):
				var release: Dictionary=holder.get("command",{}).duplicate(true)
				if str(release.get("op",""))=="touch":release={"op":"release"}
				elif release.has("pressed"):release.pressed=false
				simulators[holder.key].runtime.input(str(holder.id),false,false,release)
			pcb_holders.erase(holder_key)
	for key in placed:
		var item: Dictionary=placed[key]
		if simulators.has(key):
			simulators[key].clock+=delta
			if float(simulators[key].clock)>=.05:
				var pcb_result: Dictionary=simulators[key].runtime.tick(float(simulators[key].clock))
				simulators[key].clock=0.0
				var pcb_error: String=str(pcb_result.get("error","")) if not pcb_result.get("ok",false) else ""
				if pcb_error!=str(item.pcb_error):item.pcb_error=pcb_error;changed=true
				for control in ["A","B"]:
					var voltage: float=float(pcb_result.get(control,0.0)) if pcb_result.get("ok",false) else 0.0
					if absf(voltage-float(item.pcb_voltage[control]))>.01:item.pcb_voltage[control]=voltage;changed=true
		for control in ["A","B"]:
			if item.controls[control]=="hold" and item.state[control] and now>int(item.expiry[control]):item.state[control]=false;item.holder[control]=0;changed=true
			var pcb_high: bool=float(item.pcb_voltage[control])>=2.5
			var effective: bool=bool(item.state[control]) if item.drive[control]=="manual" else pcb_high if item.drive[control]=="pcb" else bool(item.state[control]) and pcb_high
			if effective!=bool(item.effective[control]):item.effective[control]=effective;changed=true
		var active_motor: bool=bool(item.features.battery) and ((bool(item.features.motor_a) and bool(item.effective.A)) or (bool(item.features.motor_b) and bool(item.effective.B)))
		if active_motor:
			item.angle=wrapf(float(item.angle)+delta*8.0,0,TAU)
			if item.features.wheel:
				var next: Vector3=item.position+Vector3(0,0,-delta*.5).rotated(Vector3.UP,float(item.yaw))
				if game.campus.registry.locate(next)==game.campus.registry.locate(item.position):
					if _clear_space(next,item.bounds):item.position=next
			changed=true
	if changed:
		sync_clock+=delta
		if sync_clock>=.1:sync_clock=0;_sync()

func _create_view(key: String,item: Dictionary) -> StaticBody3D:
	var root:=StaticBody3D.new();root.collision_layer=4;root.collision_mask=0
	root.set_meta("role","invention");root.set_meta("invention_key",key);root.set_meta("label",str(item.name)+" · retrieve")
	add_child(root)
	var hit:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=Vector3(.72,.52,.72);hit.shape=bounds;hit.position.y=.26;root.add_child(hit)
	var shafts: Array=[]
	for part in item.parts:
		var kind:=str(part.type)
		var pivot:=Node3D.new();pivot.position=Vector3(float(part.x),float(part.y),float(part.z))*.3+Vector3(0,.36,0);root.add_child(pivot)
		if kind in ["wheel","servo"]:pivot.set_meta("kind",kind);pivot.set_meta("control",part.get("control","B"));shafts.append(pivot)
		var mesh:=MeshInstance3D.new()
		if kind=="wheel":
			var cylinder:=CylinderMesh.new();cylinder.top_radius=.14;cylinder.bottom_radius=.14;cylinder.height=.09;mesh.mesh=cylinder;mesh.rotation.z=PI/2
		else:
			var box:=BoxMesh.new();box.size=Vector3(.24,.12,.24) if kind in ["pcb","battery","switch"] else Vector3(.28,.2,.28);mesh.mesh=box
		var material:=StandardMaterial3D.new();material.albedo_color=Color(str(Model.PARTS.get(kind,{}).get("color","777777")));mesh.material_override=material;pivot.add_child(mesh)
		if kind=="pcb" and (item.drive.A!="manual" or item.drive.B!="manual"):
			var pcb_target:=StaticBody3D.new();pcb_target.collision_layer=4;pcb_target.collision_mask=0;pcb_target.position=pivot.position+Vector3(0,.24,0);root.add_child(pcb_target)
			pcb_target.set_meta("role","invention_pcb");pcb_target.set_meta("invention_key",key);pcb_target.set_meta("label",str(item.name)+" · inspect live PCB")
			var pcb_hit:=CollisionShape3D.new();var pcb_shape:=BoxShape3D.new();pcb_shape.size=Vector3(.28,.16,.28);pcb_hit.shape=pcb_shape;pcb_target.add_child(pcb_hit)
	root.set_meta("shafts",shafts)
	for control in ["A","B"]:
		if not item.features.get("switch_"+control.to_lower(),false):continue
		var button:=StaticBody3D.new();button.name="Control"+control;button.collision_layer=4;button.collision_mask=0;button.position=Vector3(-.25 if control=="A" else .25,.66,-.25);root.add_child(button)
		button.set_meta("role","invention_control");button.set_meta("invention_key",key);button.set_meta("control",control);button.set_meta("label",str(item.name)+" · control "+control+" ("+str(item.controls[control])+")")
		var cap:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.18,.1,.18);cap.mesh=box;button.add_child(cap)
		var color:=StandardMaterial3D.new();color.albedo_color=Color("e2ad65" if control=="A" else "83cae0");cap.material_override=color
		var button_hit:=CollisionShape3D.new();var button_shape:=BoxShape3D.new();button_shape.size=Vector3(.22,.13,.22);button_hit.shape=button_shape;button.add_child(button_hit)
	return root

func _clear_visuals() -> void:
	for view in visuals.values():if is_instance_valid(view):view.queue_free()
	visuals.clear()
