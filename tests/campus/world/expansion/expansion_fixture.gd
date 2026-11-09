extends SceneTree
## Bounded offline world acceptance. Invoke only after the active playtest ends.
var failed: Array[String]=[]
var checks:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed.append(label);push_error("EXPANSION FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var registry=preload("res://scripts/campus/world/room_registry.gd").new()
	var campus=preload("res://scenes/campus/Campus.tscn").instantiate();root.add_child(campus)
	await physics_frame;await physics_frame
	check(registry.rooms.size()==16,"16 current rooms")
	check(campus.room_roots.size()==16,"16 generated room shells")
	for id in registry.rooms:
		var room: Dictionary=registry.get_room(id)
		check(not room.is_empty() and registry.locate(registry.vector(room.center))==id,"located "+id)
		var route: PackedVector3Array=registry.route("exterior",id)
		check(route.size()>=5 and route[-1].is_equal_approx(registry.vector(room.anchor)),"entrance route "+id)
	for id in ["clothing_store","circuit_studio"]:check(not registry.get_room(id).is_empty(),"separate room "+id)
	var teaching=preload("res://scripts/campus/presentation/decor/teaching_rooms/teaching_room_finish.gd").new();campus.add_child(teaching)
	var teaching_result: Dictionary=teaching.mount_approved(campus,registry,["ac_lab","dc_lab","elm253_lecture","ety155_lecture","computer"])
	check(teaching_result.failed.is_empty() and teaching_result.mounted.size()==5,"teaching finishes")
	var service=preload("res://scripts/campus/presentation/decor/service_rooms/service_room_decor.gd").new();campus.add_child(service)
	for id in ["gym","washroom_1","washroom_2"]:check(service.mount_profile(id,campus),"service finish "+id)
	var social=preload("res://scripts/campus/presentation/decor/social_rooms/social_rooms.gd").new();campus.add_child(social)
	for id in ["cafeteria","tim_hortons","subway","library","study"]:check(social.build_room(id,registry,campus),"social finish "+id)
	var shop=preload("res://scripts/campus/presentation/decor/component_shop_fitout.gd").new();root.add_child(shop)
	var stations: Dictionary=shop.build()
	check(shop.activation_contract_valid() and stations.size()==2,"component and trading stations only")
	check(stations.shop.get_meta("page","")=="shop" and stations.trade.get_meta("page","")=="trade","shop action destinations")
	var dorm=preload("res://scripts/campus/dorms/world/dorm_hall.gd").new();root.add_child(dorm);dorm.build(8)
	check(dorm.room_contracts.size()==8 and dorm.door_targets.size()==8,"eight capacity dorm doors")
	# Downward rays exercise generated floor collisions at former corridor seams.
	var space: PhysicsDirectSpaceState3D=campus.get_world_3d().direct_space_state
	for y in [0.0,5.0]:
		for z in [50.0,54.0,59.0,64.0]:
			var query:=PhysicsRayQueryParameters3D.create(Vector3(13,y+1,z),Vector3(13,y-2,z),1)
			check(not space.intersect_ray(query).is_empty(),"hall floor y="+str(y)+" z="+str(z))
	print("EXPANSION checks=%d failures=%d"%[checks,failed.size()])
	quit(0 if failed.is_empty() else 1)
