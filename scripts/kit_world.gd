extends Node3D
const Backpacks = preload("res://scripts/campus/dorms/authority/backpack_inventory.gd")
var game: Node
var kits := {}
var placed := {}
var menu_kit_id := ""
var visuals := {}
func build(owner_game: Node) -> void:
	game=owner_game
	game.session.restarted.connect(func():kits.clear();placed.clear();sync())
	game.session.roster_changed.connect(func():
		if multiplayer.is_server():
			for peer in kits.keys():
				if not game.session.roster.has(peer):kits.erase(peer)
			for key in placed.keys():
				if not game.session.roster.has(placed[key].owner):placed.erase(key)
			sync()
	)
func held() -> bool:return kits.get(multiplayer.get_unique_id(),{}).get("held",false)
func _key(peer: int,id: String) -> String:return "%d:%s" % [peer,id]
func is_placed(peer: int,id: String) -> bool:return placed.has(_key(peer,id))
func request(action: Dictionary) -> void:
	if game.session.online and action.get("op")=="equip":game.electronics_trade.authority.request_kit(action);return
	if multiplayer.is_server():apply(1,action)
	else:command.rpc_id(1,action)
@rpc("any_peer","call_remote","reliable")
func command(action: Dictionary) -> void:
	if multiplayer.is_server():apply(multiplayer.get_remote_sender_id(),action)
func apply(peer: int,action: Dictionary) -> void:
	if not game.session.roster.has(peer):return
	var op := str(action.get("op",""));var pose: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
	if op=="equip":
		if game.school.held(peer)!=0 or game.school._holding_cable(peer) or (is_instance_valid(game.dc_lab) and game.dc_lab.held_board(peer)>=0):return
		var id := str(action.get("id",""))
		if id.length()>64 or id.is_empty():return
		var profile: Dictionary=game.electronics_trade.authority.ledger.account(peer).get("profile",{}) if game.session.online else game.electronics.profile.data
		var dorm: Dictionary=profile.get("dorm",{})
		if id!=profile.get("equipped","") or not profile.get("kits",{}).has(id) or id in dorm.get("stored_kits",[]) or Backpacks.has_kit(dorm,id):return
		if "kit:"+id not in dorm.get("carry_items",[]) or is_placed(peer,id):return
		var title := str(profile.kits[id].name).left(32)
		if kits.has(peer) and not kits[peer].get("stowed",false):return
		kits[peer]={"id":id,"owner":peer,"name":title,"held":true,"stowed":false,"open":false,"position":pose}
	elif op in ["place","drop"]:
		if not kits.has(peer):return
		var pos=action.get("position")
		if not kits[peer].held:return
		if op=="drop":
			pos=game.school.ground_drop_position(pos,peer)
			if pos==null:return
		elif not pos is Vector3 or not game.school._table_position(pos) or pose.distance_to(pos)>3.6:return
		if not _set_carry(peer,str(kits[peer].id),false):return
		kits[peer].held=false;kits[peer].position=pos
		placed[_key(peer,kits[peer].id)]=kits[peer]
		kits.erase(peer)
	elif op=="stow":
		if not kits.get(peer,{}).get("held",false):return
		kits[peer].held=false;kits[peer].stowed=true
	else:
		var id := str(action.get("id",""))
		var key := _key(peer,id)
		var kit: Dictionary = placed.get(key,{})
		if kit.is_empty() or pose.distance_to(kit.position)>3.6:return
		var board := _board_for(peer,id)
		match op:
			"pickup":
				if board>=0:_notice(peer,"Return the breadboard before picking up the kit.");return
				if kit.open:_notice(peer,"Close the kit before picking it up.");return
				if held_by(peer) or game.school.held(peer)!=0 or game.school._holding_cable(peer) or game.dc_lab.held_board(peer)>=0:return
				if not _set_carry(peer,id,true):return
				kit.held=true
				kits[peer]=kit
				placed.erase(key)
			"take_board":
				if board>=0 or held_by(peer):return
				var error: String=game.dc_lab.take_kit_board(peer,id)
				if not error.is_empty():_notice(peer,error);return
				kit.open=true
			"return_held_board":
				if kit.open and board>=0 and game.dc_lab.benches[board].board_held:_recall_board(peer,board,kit)
			"close":
				if action.get("recall",false) and board>=0 and not _recall_board(peer,board,kit):return
				kit.open=false
			_:return
		game.dc_lab.broadcast()
	sync()

func held_by(peer: int) -> bool:return kits.get(peer,{}).get("held",false)

func _set_carry(peer: int,id: String,carry: bool) -> bool:
	var dorm = game.dorm_interactions
	var identity: String=dorm.authenticated_identity(peer)
	var profile: Dictionary=dorm._profile(identity).duplicate(true)
	if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():return false
	var d: Dictionary=profile.dorm
	var key := "kit:"+id
	var items: Array=d.get("carry_items",[])
	var stored: Array=d.get("stored_kits",[])
	# Reserve the kit in its owner's save while its world copy is out.
	# If the session ends, the same copy is available at the cabinet.
	if carry:
		if key in items or id not in stored or items.size()+d.get("carried_components",[]).size()>=6:
			_notice(peer,"Free a hotbar slot before picking up the kit.");return false
		stored.erase(id)
		items.append(key)
	else:
		if key not in items or id in stored:return false
		if stored.size()>=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").CAPACITY:
			_notice(peer,"Too many kits are already stored or placed.");return false
		items.erase(key)
		stored.append(id)
	d.carry_items=items
	d.stored_kits=stored
	d.revision+=1
	var saved: Dictionary=dorm._commit_world_inventory(peer,identity,profile)
	if not saved.ok:_notice(peer,str(saved.error))
	return bool(saved.ok)

func blocks_dorm_transfer(peer: int, intent: Dictionary) -> bool:
	var id := ""
	if intent.get("op") == "carry_item":
		var key := str(intent.get("item",""))
		if key.begins_with("kit:"):id=key.trim_prefix("kit:")
	elif intent.get("op") == "bag_pack":
		var item: Variant = intent.get("item")
		if item is Dictionary and item.get("kind")=="kit":id=str(item.get("id",""))
	return not id.is_empty() and (is_placed(peer,id) or (held_by(peer) and kits[peer].id==id))

func _board_for(peer: int,id: String) -> int:
	for index in game.dc_lab.benches.size():
		var station=game.dc_lab.benches[index]
		if station.board_owner==peer and station.board.get("authority_kit_id","")==id:return index
	return -1

func _recall_board(peer: int,index: int,kit: Dictionary) -> bool:
	var error: String=game.dc_lab.authority_recall(peer,index)
	if not error.is_empty():
		_notice(peer,error)
		return false
	kit.open=false
	game.dc_lab.broadcast()
	sync()
	return true

func _notice(peer: int,message: String) -> void:
	if peer==1:game.dc_lab.feedback(message)
	else:game.dc_lab.feedback.rpc_id(peer,message)
func sync() -> void:
	if multiplayer.is_server() and game.session.online:
		for peer in game.session.connected_peers():receive.rpc_id(peer,kits,placed)
@rpc("authority","call_remote","reliable")
func receive(data: Dictionary,world_kits: Dictionary) -> void:
	kits=data
	placed=world_kits
func _process(_delta: float) -> void:
	if not is_instance_valid(game):return
	var world := placed.duplicate()
	for peer in kits:world[_key(peer,kits[peer].id)]=kits[peer]
	for key in visuals.keys():
		if not world.has(key):visuals[key].queue_free();visuals.erase(key)
	for key in world:
		var kit: Dictionary=world[key]
		var peer := int(kit.owner)
		if not visuals.has(key):
			var root := StaticBody3D.new();root.collision_layer=4;root.collision_mask=0;root.set_meta("role","kit");root.set_meta("owner",peer);root.set_meta("kit_id",kit.id);root.set_meta("label",kit.name);add_child(root)
			game._box(root,Vector3(0,.1,0),Vector3(.65,.2,.4),Color("284654"))
			var lid=game._box(root,Vector3(0,.218,0),Vector3(.67,.035,.42),Color("c1a76b"));lid.name="Lid"
			var hit := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(.68,.26,.44);hit.shape=box;hit.position.y=.12;root.add_child(hit)
			var lid_hit := CollisionShape3D.new()
			lid_hit.name="LidHit"
			var lid_shape := BoxShape3D.new()
			lid_shape.size=Vector3(.67,.045,.42)
			lid_hit.shape=lid_shape
			root.add_child(lid_hit)
			visuals[key]=root
		var root: StaticBody3D=visuals[key];root.visible=not kit.stowed;root.collision_layer=0 if kit.stowed or kit.held else 4
		var lid: Node3D=root.get_node("Lid");lid.rotation.x=-1.3 if kit.open else 0;lid.position=Vector3(0,.4,-.18) if kit.open else Vector3(0,.218,0)
		var lid_hit := root.get_node("LidHit") as CollisionShape3D
		lid_hit.transform=lid.transform
		if kit.held:
			var local := int(peer)==multiplayer.get_unique_id()
			var pose: Dictionary=game.session.poses.get(peer,{})
			var basis: Basis=game.camera.global_basis if local else Basis(Vector3.UP,float(pose.get("yaw",0.0)))
			var fallback: Vector3=game.camera.to_global(Vector3(.37,-.27,-.59)) if local else pose.get("position",Vector3.ZERO)+Vector3(0,1.2,0)
			var hand: Vector3=game.held_item_position(peer,fallback)
			root.global_transform=Transform3D(basis,hand-basis*Vector3(.26,.20,.23))
			root.visible=not local or game.player.enabled
		else:root.position=kit.position;root.rotation=Vector3.ZERO
func can_return_held_board(target: Node) -> bool:
	var peer := multiplayer.get_unique_id()
	if int(target.get_meta("owner",0))!=peer:return false
	var kit: Dictionary=placed.get(_key(peer,str(target.get_meta("kit_id",""))),{})
	var held_slot: int=game.dc_lab.held_board()
	return kit.get("open",false) and held_slot>=0 and game.dc_lab.states[held_slot].get("board",{}).get("authority_kit_id","")==kit.get("id","")

func interact(target: Node,right: bool) -> bool:
	if not is_instance_valid(target):return false
	var role := str(target.get_meta("role",""))
	if role=="table" and not right and held():
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3,1))
		if not hit.is_empty() and hit.normal.y>.8:request({"op":"place","position":hit.position+Vector3(0,.015,0)})
		return true
	if role!="kit":return false
	if int(target.get_meta("owner"))!=multiplayer.get_unique_id():game.ui.log_message("This kit belongs to another player.");return true
	var id := str(target.get_meta("kit_id",""))
	var held_slot: int = game.dc_lab.held_board()
	if held_slot>=0:
		if can_return_held_board(target):request({"op":"return_held_board","id":id})
		return true
	if not right:
		if game.dc_lab.held_board()<0 and not game.hotbar.slots.has({}):
			_notice(multiplayer.get_unique_id(),"Free a hotbar slot before picking up the kit.")
			return true
		request({"op":"pickup","id":id})
		return true
	if not game.electronics.profile.data.kits.has(id):return true
	menu_kit_id=id
	game.electronics.open("kit_world")
	return true
func menu(parent: Node) -> void:
	var ui=game.electronics
	var UI = preload("res://scripts/ui/design_system/widgets.gd")
	parent.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	var picture := TextureRect.new()
	picture.texture=game.hotbar.portraits.texture({"kind":"board"},ui.profile)
	picture.custom_minimum_size.y=76
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(picture)
	var peer := multiplayer.get_unique_id()
	var kit_id := menu_kit_id
	if game.dc_lab.states.any(func(state):return int(state.get("board_owner",0))==peer and state.get("board",{}).get("authority_kit_id","")==kit_id):
		parent.add_child(UI.action("Return breadboard","",func():
			ui.close()
			request({"op":"close","id":kit_id,"recall":true})))
		return
	if placed.get(_key(peer,kit_id),{}).get("open",false):
		parent.add_child(UI.action("Close kit","close",func():
			ui.close()
			request({"op":"close","id":kit_id})))
	parent.add_child(UI.action("Take breadboard","",func():
		if not game.hotbar.slots.has({}):
			ui.status.text="Free a hotbar slot for the breadboard."
			ui.status.show()
			return
		ui.close()
		request({"op":"take_board","id":kit_id}),true))
