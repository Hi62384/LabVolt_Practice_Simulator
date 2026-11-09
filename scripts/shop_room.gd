extends Node3D
const KIT_BUILDER_POSITION := Vector3(33,0,8.65)
const STORE_ROOM_ID := "campus_store"
const Signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
const Plant = preload("res://scripts/campus/presentation/decor/potted_plant.gd")
var game: Node
var active := false
var was_in_game := false
var return_transform := Transform3D.IDENTITY
var return_pitch := 0.0
var campus_mode := false
var campus_world: Node3D
var component_fitout: Node3D
var component_counters: Array[Node3D]=[]
var workshop: Node
var workshop_decor: Node3D

func build_campus(owner_game: Node, campus: Node3D) -> void:
	campus_mode=true
	campus_world=campus
	game=owner_game
	workshop_decor = preload("res://scripts/campus/presentation/decor/electronics_workshop.gd").new()
	add_child(workshop_decor)
	_build_workshop()
	campus_world.register_content("shop", self)
	_build_campus_store()

func _build_campus_store() -> void:
	var room: Dictionary = campus_world.registry.get_room(STORE_ROOM_ID)
	if room.is_empty():return
	var center: Vector3 = campus_world.registry.vector(room.center)
	var retail := preload("res://scripts/campus/presentation/decor/component_shop_fitout_candidate.gd").new()
	retail.name="CampusStore"
	retail.position=center-Vector3(26,0,5)
	campus_world.add_child(retail)
	var stations: Dictionary = retail.build()
	stations.shop.position=Vector3(21,0,10.24)
	stations.shop.rotation.y=PI
	component_counters.append(stations.shop)
	stations.trade.position=Vector3(31.75,0,9.65)
	workshop_decor.stock_counter(stations.shop)
	var supplies := Node3D.new()
	supplies.position=Vector3(26,0,10.24)
	supplies.rotation.y=PI
	retail.add_child(supplies)
	_build_supply_counter(supplies,Vector3.ZERO)
	_finish_campus_store(retail)
	campus_world.register_content(STORE_ROOM_ID,retail)

func _finish_campus_store(retail: Node3D) -> void:
	for sign in [["ELECTRONICS STORE",21.0],["STUDY SUPPLIES",26.0],["PLAYER TRADING",31.75]]:
		Signage.mount(retail,str(sign[0]),Vector3(float(sign[1]),2.32,10.80),PI,Vector2(3.2,.45),34)
	for z in [-.86,10.86]:
		game._box(retail,Vector3(26,.55,z),Vector3(19.62,1.10,.036),Color("547489"))
		game._box(retail,Vector3(26,1.11,z),Vector3(19.62,.053,.06),Color("a58264"))
	for z in [1.45,4.65,7.85]:
		workshop_decor.build_storage_rack(retail,Vector3(35.48,0,z))
	for x in [20.9,24.1,27.3,30.5]:
		workshop_decor.build_storage_rack(retail,Vector3(x,0,-.46),0.0)
	for point in [Vector3(17.25,0,1.05),Vector3(17.5,0,9.45),Vector3(34.72,0,9.65)]:
		Plant.mount(retail,point)
	game._box(retail,Vector3(22.2,.006,5),Vector3(10.7,.012,2.25),Color("587384"))

func build(owner_game: Node) -> void:
	game=owner_game
	if not campus_mode:
		# Standalone main-menu shop retains its original bounds and entry API.
		_shop_solid(Vector3(26,-.12,3),Vector3(12,.2,10),Color("526b70"))
		_shop_solid(Vector3(26,4,3),Vector3(12,.2,10),Color("e0ddd1"))
		for x in [20.,32.]:_shop_solid(Vector3(x,2,3),Vector3(.2,4,10),Color("a8b8b4"))
		for z in [-2.,8.]:_shop_solid(Vector3(26,2,z),Vector3(12,4,.2),Color("9aadaa"))
	component_fitout=preload("res://scripts/campus/presentation/decor/component_shop_fitout_candidate.gd").new()
	add_child(component_fitout)
	var physical_stations: Dictionary=component_fitout.build(not campus_mode)
	var physical_ready: bool=component_fitout.activation_contract_valid(not campus_mode)
	if physical_ready: component_counters.append(physical_stations.shop)
	if physical_ready and not campus_mode:physical_stations.trade.position=Vector3(30,0,5)
	if not physical_ready:component_fitout.queue_free();component_fitout=null
	for row in [[Vector3(22,0,1),"Electronics Store","shop"],[Vector3(30,0,5),"PLAYER TRADING","trade"]]:
		if physical_ready or (campus_mode and row[2] == "trade"):continue
		var pos: Vector3=row[0]
		_shop_solid(pos+Vector3(0,.55,0),Vector3(2.4,1.1,.7),Color("244e59"))
		var body := StaticBody3D.new();body.collision_layer=4;body.collision_mask=0;body.position=pos+Vector3(0,1.35,0);add_child(body)
		var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(2.4,.5,.2);shape.shape=box;body.add_child(shape)
		body.set_meta("role","shop_station");body.set_meta("page",row[2]);body.set_meta("label",row[1])
		if row[2] == "shop": component_counters.append(body)
		game._box(body,Vector3.ZERO,Vector3(2.4,.5,.08),Color("152e37"))
	for x in ([] if campus_mode else [22.,30.]):
		var light := OmniLight3D.new();light.position=Vector3(x,3.45,3);light.light_energy=.45;light.omni_range=5;light.shadow_enabled=false;add_child(light)

func _build_supply_counter(retail: Node3D, point: Vector3) -> void:
	_shop_solid(point+Vector3(0,.47,0),Vector3(2.45,.94,.84),Color("35495b"),retail)
	_shop_solid(point+Vector3(0,.97,0),Vector3(2.60,.09,1.02),Color("b68e67"),retail)
	game._box(retail,point+Vector3(-.57,1.045,.07),Vector3(.48,.05,.35),Color("527887"))
	game._box(retail,point+Vector3(0,1.05,.10),Vector3(.26,.064,.43),Color("222b3a"))
	game._box(retail,point+Vector3(.53,1.07,.06),Vector3(.46,.09,.19),Color("9a5348"))
	var target := StaticBody3D.new()
	target.position=point+Vector3(0,1.05,.47)
	target.collision_layer=4
	target.collision_mask=0
	target.set_meta("role","shop_station")
	target.set_meta("page","supplies")
	target.set_meta("label","Shop study supplies")
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(2.45,1.25,.15)
	hit.shape=shape
	target.add_child(hit)
	retail.add_child(target)

func _build_workshop() -> void:
	workshop = preload("res://scripts/campus/facilities/circuit_studio/interaction_adapter.gd").new()
	add_child(workshop)
	workshop.configure(game, "shop")
	var signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
	signage.mount(self, "ELECTRONICS WORKSHOP", Vector3(26, 2.72, 9.78), PI, Vector2(5.2, .72), 54)
	var diffuser := StandardMaterial3D.new()
	diffuser.albedo_color = Color("fff6e6")
	diffuser.emission_enabled = true
	diffuser.emission = Color("fff1d9")
	diffuser.emission_energy_multiplier = .45
	for x in [21.0, 26.0, 31.0]:
		for z in [0.0, 6.0]:
			var fixture := Node3D.new()
			fixture.position=Vector3(x,3.93,z)
			add_child(fixture)
			game._box(fixture, Vector3.ZERO, Vector3(2.2,.09,.66), Color("415469"))
			var panel: MeshInstance3D = game._box(fixture, Vector3(0,-.057,0), Vector3(2.06,.033,.53), Color.WHITE)
			panel.material_override = diffuser
			preload("res://scripts/campus/presentation/fixture_light.gd").ceiling_omni(fixture, panel.position, 1.65, 5.4, false)
	for z in [-3.87, 9.87]:
		game._box(self, Vector3(26,.58,z), Vector3(19.70,1.15,.034), Color("55728a"))
		game._box(self, Vector3(26,.085,z), Vector3(19.70,.15,.062), Color("344c62"))
	game._box(self, Vector3(35.87,.58,3), Vector3(.034,1.15,13.72), Color("55728a"))
	workshop_decor.build_room()
	for station in [
		[Vector3(18.6, 0, 8.65), "electronics_store", "ELECTRONICS STORE"],
		[Vector3(22.2, 0, 8.65), "prototype_bench", "CUSTOM CIRCUIT MAKER"],
		[Vector3(25.8, 0, 8.65), "ic_builder", "IC BUILDER"],
		[Vector3(29.4, 0, 8.65), "pcb_builder", "PCB BUILDER"],
		[KIT_BUILDER_POSITION, "components_counter", "COMPONENTS COUNTER"],
	]:
		var position: Vector3 = station[0]
		var bench: Node3D = workshop_decor.build_station(position, station[1], station[2])
		var target := StaticBody3D.new()
		target.position = position + Vector3(0, 1.15, 0)
		target.collision_layer = 4
		target.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.6, .28, 1.03)
		collision.shape = shape
		target.add_child(collision)
		add_child(target)
		if station[1]=="electronics_store":
			component_counters.append(bench)
			target.set_meta("role","shop_station")
			target.set_meta("page","shop")
			target.set_meta("label","Electronics Store")
		elif station[1]=="components_counter":
			target.set_meta("role","shop_station")
			target.set_meta("page","counter")
			target.set_meta("label","Components Counter")
		else:workshop.register_station(target, station[1])
	workshop_decor.batch_static_props()

func near_kit_builder(point: Vector3) -> bool:
	return campus_mode and point.distance_to(KIT_BUILDER_POSITION)<3.2 and campus_world.registry.room_contains("shop",point)

func near_component_counter(point: Vector3) -> bool:
	return near_kit_builder(point)

func near_components_store(point: Vector3) -> bool:
	for counter in component_counters:
		if not is_instance_valid(counter):continue
		var local := counter.to_local(point)
		var nearest := Vector3(clampf(local.x,-1.49,1.49),clampf(local.y,0.0,1.05),clampf(local.z,-.45,.45))
		if local.distance_to(nearest)<3.2:return true
	return false
func enter() -> void:
	if active:return
	if not game.hotbar.stow():return
	if game.player.inspecting:game.end_inspection()
	game._stand_from_chair()
	was_in_game=game.front.in_game;return_transform=game.player.global_transform;return_pitch=game.player.pitch_target
	game.session.shop_travel(true)
	active=true;game.player.position=Vector3(26,0,3);game.player.velocity=Vector3.ZERO;game.player.yaw_target=0;game.player.rotation.y=0;game.player.pitch_target=0;game.capture()
func leave() -> void:
	if not active:
		if campus_mode:
			game.player.position=Vector3(14.5,0,3)
			game.player.velocity=Vector3.ZERO
			game.capture()
		return
	game.session.shop_travel(false);active=false;game.player.global_transform=return_transform;game.player.yaw_target=return_transform.basis.get_euler().y;game.player.pitch_target=return_pitch;game.player.velocity=Vector3.ZERO
	if was_in_game:game.capture()
	else:game.front.in_game=false;game.release_mouse();game.front.home()
func interact(target: Node) -> bool:
	if is_instance_valid(workshop) and workshop.interact(target):return true
	if not is_instance_valid(target) or target.get_meta("role","")!="shop_station":return false
	var page := str(target.get_meta("page"))
	if page not in ["shop","trade","supplies","counter"]:return false
	if page=="counter":
		var index: int=game.dc_lab.held_board()
		if index>=0 and game.dc_lab.states[index].get("board",{}).get("authority_kit_id","existing_kit")=="":
			game.dc_lab.request(index,{"op":"counter_return"})
			return true
	game.electronics.open(page)
	return true

func _shop_solid(pos: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> void:
	if parent == null:parent=self
	game._box(parent,pos,size,color)
	var body := StaticBody3D.new()
	body.position=pos
	body.collision_layer=1
	body.collision_mask=0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	body.add_child(collision)
	parent.add_child(body)
