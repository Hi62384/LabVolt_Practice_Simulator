extends Node
## Host-curated, relevance-limited public cards. No client sends profile contents.
var game: Node
var service: Node
var visibility := {}
var preference_times := {}
var last_preferences := ""
var peer_public_ids := {}
var inspector: PanelContainer
var clock := 0.0
var avatar_models := {}
var local_visual: Node3D
var local_peer := 1
var catalog_cache := {}

func build(owner_game: Node,facilities: Node) -> void:
	game=owner_game;service=facilities
	var layer := CanvasLayer.new();layer.layer=26;add_child(layer)
	inspector=preload("res://scripts/campus/ui/profile_inspector.gd").new();layer.add_child(inspector);inspector.position=Vector2(60,60);inspector.hide()
	inspector.visibility_changed.connect(func():
		if not inspector.visible and game.front.in_game:game.capture())
	game.session.restarted.connect(func():visibility.clear();preference_times.clear();last_preferences="";peer_public_ids.clear())
	local_visual=Node3D.new();local_visual.name="LocalHeldFood";game.camera.add_child(local_visual);local_visual.position=Vector3(0,-1.3,-0.6)
	local_peer=multiplayer.get_unique_id();service.bind_avatar(local_peer,local_visual)
	catalog_cache=preload("res://scripts/electronics_catalog.gd").all()

func preferences(peer: int,values: Dictionary) -> void:
	if not multiplayer.is_server() or not game.session.roster.has(peer) or values.size()>7:return
	var now := Time.get_ticks_msec()
	if now-int(preference_times.get(peer,-1000))<200:return
	var safe := {}
	for key in preload("res://scripts/campus/social/public_profiles.gd").FIELDS:
		if values.has(key) and not values[key] is bool:return
		safe[key]=bool(values.get(key,key in ["appearance","emotes"]))
	preference_times[peer]=now;visibility[peer]=safe

@rpc("any_peer","call_remote","reliable",4)
func _preferences(values: Dictionary) -> void:
	preferences(multiplayer.get_remote_sender_id(),values)

func _source(peer: int) -> Dictionary:
	var ledger: RefCounted=game.electronics_trade.authority.ledger
	var profile: Dictionary=ledger.account(peer).get("profile",{}) if game.session.online else (game.electronics.profile.data if peer==1 else {})
	var inventory: Dictionary=profile.get("inventory",{})
	var items: Array=[];var count := 0
	var catalog: Dictionary=catalog_cache
	for id in inventory:
		count+=int(inventory[id]);items.append({"id":id,"name":catalog.get(id,{}).get("name",id),"count":int(inventory[id])})
	var equipped := str(profile.get("equipped",""))
	var kit: Dictionary=profile.get("kits",{}).get(equipped,{})
	var gym: Dictionary=service.adapter.load_facilities(str(ledger.bindings.get(peer,"")) if game.session.online else game.school.local_identity)
	var course: Dictionary={"course_id":str(game.school.activity.get("course_id","ELM253"))}
	var academic_identity := str(game.school.identities.get(peer,""))
	var totals := {"lecture":[],"lab":[]}
	for record in game.school.gradebook.values():
		if str(record.get("profile",""))!=academic_identity or record.get("lesson",false) or str(record.get("course_id","ELM253"))!=course.course_id:continue
		var kind := str(record.get("kind","lab"))
		if totals.has(kind) and is_finite(float(record.get("score",NAN))):totals[kind].append(float(record.score))
	var averages: Array=[]
	for kind in totals:
		if totals[kind].is_empty():continue
		var total := 0.0
		for score in totals[kind]:total+=score
		course[kind]=total/totals[kind].size();averages.append(course[kind])
	if not averages.is_empty():
		var total := 0.0
		for score in averages:total+=score
		course.overall=total/averages.size()
	return {"kit":{"name":kit.get("name",""),"capacity":profile.get("capacity",0),"equipped":equipped},"parts":{"count":count,"items":items},"money":{"dollars":profile.get("dollars",0)},"course":course,"gym":{"level":1+int(gym.get("xp",0))/100,"xp":gym.get("xp",0)},"emotes":{"unlocked":gym.get("unlocks",["wave"]),"equipped":"wave"}}

func _visible(from: Vector3,to: Vector3,distance: float) -> bool:
	if from.distance_squared_to(to)>distance*distance:return false
	if game.campus.registry.locate(from)!=game.campus.registry.locate(to):return false
	var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP*1.5,to+Vector3.UP*1.5,1)
	return game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _process(delta: float) -> void:
	if game==null:return
	clock+=delta
	if clock<0.25:return
	clock=0
	var peer_id := multiplayer.get_unique_id()
	if peer_id!=local_peer:
		service.unbind_avatar(local_peer);avatar_models.erase(local_peer)
		local_peer=peer_id;service.bind_avatar(local_peer,local_visual)
	var prefs: Dictionary=game.ui.public_visibility.values
	var signature := str(prefs)
	if signature!=last_preferences and game.session.roster.has(multiplayer.get_unique_id()):
		last_preferences=signature
		if multiplayer.is_server():preferences(1,prefs)
		elif game.session.online:_preferences.rpc_id(1,prefs)
	if multiplayer.is_server():_publish()
	for peer in game.avatars:
		var avatar: Node3D=game.avatars[peer]
		var model: Node3D=avatar.get_node_or_null("CharacterModel")
		if model!=null and avatar_models.get(peer,0)!=model.get_instance_id():
			avatar_models[peer]=model.get_instance_id();service.bind_avatar(peer,model)
	for peer in avatar_models.keys():
		if not game.avatars.has(peer):service.unbind_avatar(peer);avatar_models.erase(peer)

func _publish() -> void:
	var identities := {};var session: Node=game.session
	for peer in session.roster:
		var identity := str(game.school.identities.get(peer,""))
		if identity.is_empty():continue
		identities[peer]=identity
		session.campus_profile_publish(identity,str(session.roster[peer].name),_source(int(peer)),visibility.get(peer,{"appearance":true,"emotes":true}))
	for recipient in session.roster:
		var relevant: Array=[];var mapping := {}
		var from: Vector3=session.poses.get(recipient,{}).get("position",Vector3.ZERO)
		for peer in identities:
			var to: Vector3=session.poses.get(peer,{}).get("position",Vector3.ZERO)
			if peer==recipient or _visible(from,to,16):
				relevant.append(identities[peer]);mapping[peer]=session.campus_public_replication.identity_map.public_id(identities[peer])
		session.campus_profile_send(int(recipient),relevant)
		if recipient==1:peer_public_ids=mapping
		elif session.online:_public_map.rpc_id(int(recipient),mapping)

@rpc("authority","call_remote","reliable",4)
func _public_map(mapping: Dictionary) -> void:
	if mapping.size()>8:return
	peer_public_ids=mapping.duplicate()

func route_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and inspector.visible:
		inspector.hide();return true
	if not game.player.enabled or not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):return false
	var best := 0;var best_dot := 0.985
	for peer in game.avatars:
		var target: Vector3=game.avatars[peer].global_position+Vector3.UP*1.4
		var direction: Vector3=target-game.camera.global_position
		if not _visible(game.player.global_position,game.avatars[peer].global_position,4):continue
		var alignment: float=(-game.camera.global_basis.z).dot(direction.normalized())
		if alignment>best_dot and peer_public_ids.has(peer):best=peer;best_dot=alignment
	if best==0:return false
	var profile: Dictionary=game.session.campus_public_cache.profiles.get(peer_public_ids[best],{})
	if profile.is_empty():return false
	game.release_mouse();inspector.show_profile(profile);return true

