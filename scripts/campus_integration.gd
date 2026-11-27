extends Node
## Composition belongs to the live game. All mutations still pass host services.
var elevator_service: Node
var game: Node
var provider = preload("res://scripts/campus_course_provider.gd").new()
var adapter = preload("res://scripts/campus/ui/campus_adapter.gd").new()
var facilities: Node3D
var facility_panel: PanelContainer
var sandwich_counter: Node3D
var binding_key := ""
var refresh_clock := 0.0
var gym_motion: Node3D
var social: Node
var equipment_optimizer: RefCounted
var social_decor: Node3D
var study_resources := {}
var study_finishes := {}
var clothing_room: Node3D
var clothing_panel: Control
var clothing_pending := ""
var m101_environment: Node3D
var teaching_finish: Node3D
var service_decor: Node3D
var m203_room: Node3D
var room_finish_results := {}

func build(owner_game: Node) -> void:
	game=owner_game
	game.school.configure_campus(game.campus.registry,provider,preload("res://scripts/campus_equipment_adapter.gd").new(game))
	game.session.academic_equipment_guard=func(peer,index,action):
		if action.get("op")=="dyn_measure" and action.get("pressed",true)==false:return true
		if not game.school.equipment_access(peer,index,"ELM253"):return false
		if is_instance_valid(game.lecture_classes) and game.lecture_classes.lab_practice.work.get("domain","")=="ac" and game.lecture_classes.lab_practice.work.get("bench",-1)==index:
			if not game.lecture_classes._inside(peer,"ac_lab"):return false
			var point: Vector3=game.lecture_classes._position(peer)
			var supply: Vector3=game.session.labs[index].positions.get("power",Vector3.INF)
			if point.distance_to(supply)>3.25:return false
			game.lecture_classes.lab_practice.yield_bench(index)
		return true
	game.session.academic_equipment_observer=func(peer,index,action,before):
		game.school.equipment_adapter.observe_ac_action(peer,index,action,before)
		if is_instance_valid(game.faculty):game.faculty.report_equipment_fault(peer,index,action,before)
	game.school.activity_started.connect(_activity_spawn)
	game.school_world.build_campus_furniture()
	adapter.configure(game.school,game.campus.registry,provider)
	game.front.set_campus_adapter(adapter)
	equipment_optimizer=preload("res://scripts/campus/performance/equipment_render_optimizer.gd").new()
	equipment_optimizer.cache=game.shared_equipment_meshes
	equipment_optimizer.optimize_legacy_game(game)
	game.campus.register_content("ac_lab",game.get_node("TrainingStation"))
	for station in game.stations:game.campus.register_content("ac_lab",station.equipment)
	game.campus.register_content("dc_lab",game.dc_lab)
	game.install_campus_performance(game.campus.registry)
	game.ui.graphics_controller.set_crowd_adapter(game.campus_performance)
	facilities=preload("res://scripts/campus/facilities/facility_service.gd").new()
	facilities.name="Facilities";add_child(facilities)
	facilities.configure(game.campus.registry,game.electronics_trade.authority.ledger,_facility_context,_interested)
	game.session.leaving.connect(facilities.controller.finish_session)
	game.session.restarted.connect(facilities.controller.reset_presentation)
	facilities.controller.host.table_surface=game.school._table_position
	facilities.controller.host.floor_surface=game.school.ground_drop_position
	facilities.controller.host.public_event.connect(func(_room: String, peer: int, event: Dictionary):
		if event.get("activity","")=="consume":game.health.heal_from_food(peer))
	facilities.install_movement_hooks(game.session,game.player)
	elevator_service=preload("res://scripts/campus/elevator/elevator_service.gd").new()
	elevator_service.name="ElevatorService";add_child(elevator_service)
	elevator_service.configure(self)
	game.campus.elevator_control_requested.connect(elevator_service.request)
	facilities.controller.room_event.connect(game.interaction_presentation.facility_event)
	facilities.controller.cable_selection_rejected.connect(game.ui.log_message)
	facilities.controller.room_event.connect(func(peer: int, event: Dictionary):
		if peer==multiplayer.get_unique_id() and event.get("activity","") in ["seat","idle","exercise"]:
			game.player.set_facility_seat(event))
	facilities.profile_committed.connect(_profile_committed)
	game.session.restarted.connect(func():
		facilities.local_locked=false
		game.player.set_facility_seat({})
		facility_panel.direct.clear()
		facility_panel.direct_in_flight=false
		facility_panel.pending=false
		facilities.controller.host.active.clear();facilities.controller.host.seats.clear()
		facilities.controller.host.gym_recovery_clock.clear()
		facilities.controller.host.last_request.clear();facilities.controller.room_states.clear()
		facility_panel.state.clear()
		for order in facilities.table_food.values():
			if is_instance_valid(order):order.queue_free()
		facilities.table_food.clear()
		if facilities.rooms.has("gym"):
			for machine in facilities.rooms.gym.gym_cables:
				machine.set_resistance(10)
		for room in facilities.rooms.values():
			for peer in room.placed_food.keys():room.sync_food(peer,{})
		for visual in facilities.visuals.values():
			if is_instance_valid(visual):visual.apply_event({"activity":"idle","held":{}},false)
		facility_panel.hide()
	)
	for id in ["gym","tim_hortons","subway"]:facilities.mount_room(id,game.campus)
	gym_motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd").new()
	gym_motion.name="GymEquipmentMotion";game.campus.add_child(gym_motion)
	gym_motion.grip_position=func(peer: int):
		var activity: Variant=facilities.visuals.get(peer)
		if not is_instance_valid(activity) or not activity.arms.has("ArmL") or not activity.arms.has("ArmR"):return null
		var joints=preload("res://scripts/campus/facilities/arm_bend.gd")
		var left: Node3D=joints.hand_for(activity.arms.ArmL.node)
		var right: Node3D=joints.hand_for(activity.arms.ArmR.node)
		return (left.global_position+right.global_position)*.5 if is_instance_valid(left) and is_instance_valid(right) else null
	facilities.controller.room_event.connect(gym_motion.on_room_event)
	var gym_decor=preload("res://scripts/campus/presentation/decor/m105/m105_decor.gd").new()
	game.campus.add_child(gym_decor)
	room_finish_results.m105=gym_decor.mount(game.campus)
	m101_environment=preload("res://scripts/campus/presentation/decor/m101_environment.gd").new()
	add_child(m101_environment)
	room_finish_results.m101=m101_environment.mount(game.campus,game.campus.registry)
	teaching_finish=preload("res://scripts/campus/presentation/decor/teaching_rooms/teaching_room_finish.gd").new()
	add_child(teaching_finish)
	room_finish_results.teaching=teaching_finish.mount_approved(game.campus,game.campus.registry,game.campus.registry.lecture_rooms())
	var m103_finish=preload("res://scripts/campus/presentation/decor/m103_room_finish.gd").new()
	add_child(m103_finish)
	room_finish_results.m103=m103_finish.mount(game.campus,game.campus.registry)
	if room_finish_results.m103:
		for x in [-6.0, 0.0, 6.0]:
			game._add_chair(Vector3(x, 0, 22.5), PI)
	m203_room=preload("res://scripts/campus/presentation/decor/computer_rooms/m203_room.gd").new()
	add_child(m203_room)
	room_finish_results.m203=m203_room.mount(game.campus,game.campus.registry)
	if room_finish_results.m203:
		game.computer_room_adapter=preload("res://scripts/campus/computers/classroom_adapter.gd").new()
		game.computer_room_adapter.name="ComputerClassroomAdapter"
		game.add_child(game.computer_room_adapter)
		if not game.computer_room_adapter.build(game,m203_room):push_error("M203 station integration failed")
		var commons=preload("res://scripts/campus/presentation/decor/computer_rooms/commons_room.gd").new()
		commons.name="ComputerCommons";add_child(commons)
		room_finish_results.computer_commons=commons.mount(game.campus,game.computer_room_adapter)
		if not room_finish_results.computer_commons:push_error("Computer commons integration failed")
	service_decor=preload("res://scripts/campus/presentation/decor/service_rooms/service_room_decor.gd").new()
	add_child(service_decor)
	room_finish_results.service={}
	for id in ["washroom_1","washroom_2","circulation_0","circulation_1"]:
		room_finish_results.service[id]=service_decor.mount_profile(id,game.campus)
	game.washroom_finish=preload("res://scripts/campus/presentation/decor/washrooms/washroom_finish.gd").new()
	game.washroom_finish.name="WashroomFinish"
	game.add_child(game.washroom_finish)
	if game.washroom_finish.install(game,game.campus):
		for id in ["washroom_1","washroom_2"]:
			if service_decor.built.has(id) and is_instance_valid(service_decor.built[id]):service_decor.built[id].queue_free()
	social_decor=preload("res://scripts/campus/presentation/decor/social_rooms/social_rooms.gd").new()
	social_decor.name="SocialRoomDecor";game.campus.add_child(social_decor)
	for id in ["cafeteria","tim_hortons","subway","library"]:
		if not social_decor.build_room(id,game.campus.registry,game.campus):continue
		if id in ["library","study"]:
			var center: Vector3=game.campus.registry.vector(game.campus.registry.get_room(id).center)
			var study_finish:=preload("res://scripts/campus/presentation/decor/social_rooms/study_finish.gd").new()
			study_finish.position=center;game.campus.add_child(study_finish)
			if study_finish.build(id) and game.campus.register_content(id,study_finish):study_finishes[id]=study_finish
			else:study_finish.queue_free()
		if id=="cafeteria":
			var cafeteria_finish:=preload("res://scripts/campus/presentation/decor/social_rooms/m104_finish.gd").new()
			cafeteria_finish.name="M104Finish"
			cafeteria_finish.position=Vector3(26,0,19)
			game.campus.add_child(cafeteria_finish)
			cafeteria_finish.build()
			if not game.campus.register_content("cafeteria",cafeteria_finish):cafeteria_finish.queue_free()
		if id in ["tim_hortons","subway"] and not social_decor.adopt_restaurant_visuals(id,facilities.rooms.get(id)):
			var failed_root = social_decor.roots.get(id)
			if is_instance_valid(failed_root):failed_root.queue_free()
			social_decor.roots.erase(id)
	if social_decor.roots.has("tim_hortons") and facilities.rooms.has("tim_hortons") and social_decor.replaced_visuals.has("tim_hortons"):
		var tim_finish:=preload("res://scripts/campus/presentation/decor/social_rooms/m106_finish.gd").new()
		tim_finish.name="M106Finish";tim_finish.position=Vector3(26,0,33)
		game.campus.add_child(tim_finish)
		if not tim_finish.build(facilities.controller.host.menu) or not game.campus.register_content("tim_hortons",tim_finish):tim_finish.queue_free()
	if social_decor.roots.has("subway") and facilities.rooms.has("subway") and social_decor.replaced_visuals.has("subway"):
		var subway_root: Node3D=social_decor.roots["subway"]
		var subway_finish:=preload("res://scripts/campus/presentation/decor/social_rooms/m108_subway_finish.gd").new()
		subway_finish.name="M108SubwayFinish";subway_finish.position=Vector3(26,0,47);subway_finish.rotation.y=PI
		subway_root.rotation.y=PI
		var furniture: Node3D=facilities.rooms.get("subway")
		if is_instance_valid(furniture):
			furniture.rotation.y=PI
			for station in furniture.stations.values():
				for key in ["position","seat_position"]:
					if station.has(key): station[key]=Vector3(26,0,47)+Basis(Vector3.UP,PI)*(station[key]-Vector3(26,0,47))
				if station.has("seat_yaw"):station.seat_yaw+=PI
			facilities.controller.host.anchors.merge(furniture.stations,true)
		for station in social_decor.seat_anchors.get("subway",{}).values():
			for key in ["position","seat_position"]:
				if station.has(key):station[key]=Vector3(26,0,47)+Basis(Vector3.UP,PI)*(station[key]-Vector3(26,0,47))
			station.seat_yaw+=PI
		subway_finish.build(facilities.controller.host.menu)
		game.campus.add_child(subway_finish)
		if game.campus.register_content("subway",subway_finish):
			sandwich_counter=preload("res://scripts/campus/facilities/sandwich_counter.gd").new()
			sandwich_counter.name="InteractiveSandwichCounter"
			subway_finish.add_child(sandwich_counter)
			sandwich_counter.bind(game,facilities.controller,furniture.get_node_or_null("Cashier") if is_instance_valid(furniture) else null)
			for visual in subway_root.get_children():
				if visual is GeometryInstance3D:visual.visible=false
		else:subway_finish.queue_free()
	var quiet_study=preload("res://scripts/campus/presentation/decor/social_rooms/quiet_study.gd").new()
	quiet_study.name="QuietStudy";game.campus.add_child(quiet_study)
	if quiet_study.build(game.campus):facilities.controller.host.anchors.merge(quiet_study.seat_anchors,true)
	for id in social_decor.roots:
		facilities.controller.host.anchors.merge(social_decor.seat_anchors.get(id, {}), true)
	if social_decor.roots.has("cafeteria"):
		facilities.cafeteria_seat_source=social_decor
	var layer := CanvasLayer.new();layer.layer=25;add_child(layer)
	facility_panel=preload("res://scripts/campus/facilities/facility_panel.gd").new()
	layer.add_child(facility_panel);facility_panel.bind(facilities.controller)
	facility_panel.orders_changed = func():game.hotbar._sync_food()
	facility_panel.has_order_space=func():return game.hotbar.slots.any(func(slot):return slot.is_empty())
	facility_panel.direct_error.connect(game.ui.log_message)
	if is_instance_valid(sandwich_counter): facility_panel.sandwich_builder_requested.connect(sandwich_counter.begin)
	_install_clothing_store(layer)
	facility_panel.position=Vector2(60,60);facility_panel.hide()
	facility_panel.visibility_changed.connect(func():
		if not facility_panel.visible and game.front.in_game:game.capture())
	_bind_facilities()
	social=preload("res://scripts/campus_social.gd").new();social.name="PublicProfiles";add_child(social);social.build(game,facilities)

func _bind_facilities() -> void:
	facilities.controller.host.exercise_alignment=_exercise_alignment
	facilities.controller.host.apply_exercise_alignment=_relocate
	var ledger: RefCounted=game.electronics_trade.authority.ledger
	var key: String=str(game.session.online)+":"+str(ledger.get_instance_id())+":"+game.school.local_identity+":"+str(game.electronics.profile.get_instance_id())
	if key==binding_key:return
	binding_key=key
	facility_panel.state.clear()
	if game.session.online:
		var next=preload("res://scripts/campus/facilities/ledger_adapter.gd").new()
		next.ledger=ledger;next.is_authority=func():return multiplayer.is_server()
		next.committed.connect(_profile_committed)
		facilities.adapter=next
		facilities.controller.host.load_profile=next.load_facilities
		facilities.controller.host.commit_profile=next.commit
	else:facilities.use_offline_profile(game.school.local_identity,game.electronics.profile)

func _exercise_alignment(peer: int,station: String,exercise: String,current: Vector3) -> Dictionary:
	var anchors: Dictionary=facilities.controller.host.anchors
	var anchor: Dictionary=anchors.get(station,{})
	var point:=current
	var yaw: float=game.session.poses.get(peer,{}).get("yaw", game.player.yaw_target)
	var machine:=_cable_machine(station)
	if is_instance_valid(machine):
		point=machine.to_global(Vector3(0,0,1.25))
		var facing: Vector3=machine.global_position-point
		if exercise in ["cable_fly","cable_press","overhead_extension"]:facing=-facing
		yaw=atan2(-facing.x,-facing.z)
	elif anchor.get("kind")=="pullup":
		var grip: Vector3=anchor.get("dip_grip" if exercise=="dip" else "pullup_grip",anchor.position)
		point=Vector3(grip.x,current.y,grip.z)
		yaw=0.0 if exercise!="dip" else PI
	elif anchor.get("kind")=="pushup":
		var mat: Vector3=anchor.mat_position
		point=Vector3(mat.x,current.y,mat.z+.39)
		yaw=0.0
	elif anchor.get("kind") in ["benchpress","seated_bench"]:
		var bench: Vector3=anchor.bench_position
		point=Vector3(bench.x,current.y,bench.z+1.0)
		yaw=preload("res://scripts/campus/facilities/gym_bench.gd").approach_yaw(exercise)
	elif anchor.get("kind")=="squat":
		point=anchor.position
		yaw=0.0
	if point.distance_to(current)<.12:return {"position":current,"yaw":yaw}
	# Test torso clearance without treating the floor/mat under the player's
	# feet as an obstruction. Collision and position checks stay on the host.
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.27
	capsule.height=1.34
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.99)
	query.collision_mask=1
	query.exclude=[game.player.get_rid()]
	if not game.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	for other in game.session.poses:
		if int(other)==peer:continue
		var position: Vector3=game.session.poses[other].get("position",Vector3.INF)
		if position.distance_to(point)<.68:return {}
	return {"position":point,"yaw":yaw}

func _facility_context(peer: int) -> Dictionary:
	if not game.session.roster.has(peer):return {}
	var identity: String=str(game.electronics_trade.authority.ledger.bindings.get(peer,"")) if game.session.online else (game.school.local_identity if peer==1 else "")
	if identity.is_empty():return {}
	var pos: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
	if peer==1:pos=game.player.global_position
	var room_id: String=game.campus.registry.locate(pos)
	var floor_y := 5.0 if pos.y>=4.5 else 0.0
	return {"identity":identity,"position":pos,"room_id":room_id,"facility_kind":game.campus.registry.get_room(room_id).get("kind",""),"allowed":not game.school.formal_active(),"grounded":absf(pos.y-floor_y)<0.3}

func _interested(room_id: String) -> Array:
	var peers: Array=[]
	for peer in game.session.roster:
		if peer!=1 and game.session.online and not game.session.peer_connected_now(int(peer)):continue
		if game.campus.registry.locate(game.session.poses.get(peer,{}).get("position",Vector3.ZERO))==room_id:peers.append(int(peer))
	return peers

func _profile_committed(identity: String) -> void:
	if not multiplayer.is_server() or not game.session.online:return
	var authority: Node=game.electronics_trade.authority
	for peer in authority.ledger.bindings:
		if authority.ledger.bindings[peer]==identity:authority.send_snapshot(int(peer),authority.ledger.snapshot(int(peer)))

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if is_instance_valid(facilities) and facilities.rooms.has("gym") and is_instance_valid(facilities.rooms.gym):
		var aimed: Node3D
		if game.player.enabled and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and is_instance_valid(game.current_target):
			aimed=game.current_target
		for cable_machine in facilities.rooms.gym.gym_cables:cable_machine.highlight_pin(aimed)

	refresh_clock+=delta
	if refresh_clock<0.2:return
	refresh_clock=0
	_bind_facilities()
	if game.front.in_game and not facility_panel.state.has("profile") and not facility_panel.pending and not facility_panel.direct_in_flight and facility_panel.direct.is_empty():
		facilities.controller.refresh()

func aimed_prompt() -> String:
	if not game.player.enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return ""
	var interact_key := OS.get_keycode_string(game.player.keys.interact)
	if game.school.formal_active(): return ""
	if _aimed_order():return "%s - Pick up %s" % [interact_key,game.current_target.get_meta("label","order")]
	var target: Node=game.current_target
	if is_instance_valid(target):
		match target.get_meta("role",""):
			"gym_cable_load":
				if game.gym_barbells.held_plate(multiplayer.get_unique_id())>=0:return "%s - Add weight plate" % interact_key
			"gym_cable_plate":
				return "%s - %s weight plate" % [interact_key,"Add" if game.gym_barbells.held_plate(multiplayer.get_unique_id())>=0 else "Remove"]
	var aimed := _aimed_facility()
	if aimed.is_empty() or (aimed.kind=="seat" and not game.player.facility_seat.is_empty()): return ""
	if aimed.kind in ["benchpress","seated_bench"]:return "%s - %s" % [interact_key,"Bench" if aimed.kind=="benchpress" else "Use seated bench"]
	var action := "Open cable exercises" if aimed.kind=="cable" else ("Sit" if aimed.kind=="seat" else ("Cashier" if str(aimed.kind).begins_with("counter:") else str(aimed.kind).capitalize()))
	return "%s - %s" % [interact_key, action]

func _aimed_facility() -> Dictionary:
	var target: Node = game.current_target
	if not is_instance_valid(target) or not target.get_meta("role","") in ["facility_seat","restaurant_cashier","gym_equipment","gym_progress"]:
		return {}
	if target.get_meta("role","")=="gym_progress":return {"id":"gym/progress","kind":"gym_progress"}
	var id := str(target.get_meta("station",""))
	var point: Vector3 = game.player.global_position
	var host: RefCounted = facilities.controller.host
	if not host.reachable({"position":point,"room_id":game.campus.registry.locate(point)},id):
		return {}
	return {"id":id,"kind":host.anchors[id].kind}

func _aimed_order() -> bool:
	var target: Node=game.current_target
	return is_instance_valid(target) and target.get_meta("role","")=="facility_food" and target.get_meta("owner",-1)==multiplayer.get_unique_id()

func _route_cable_plate() -> bool:
	var target: Node=game.current_target
	if not is_instance_valid(target) or not target.get_meta("role","") in ["gym_cable_load","gym_cable_plate"]:return false
	var station:=str(target.get_meta("station",""))
	var machine:=_cable_machine(station)
	if not is_instance_valid(machine) or machine.occupant!=0:return true
	var peer:=multiplayer.get_unique_id()
	var held: int=game.gym_barbells.held_plate(peer)
	if held>=0:
		if game.gym_barbells.cable_plates(station).size() >= machine.PLATE_LIMIT:
			game.ui.log_message("This loading post is full.")
		else:game.gym_barbells.request_plate("cable_attach",held,station)
	elif target.get_meta("role","")=="gym_cable_plate":
		if game.hotbar.slots.any(func(slot):return slot.is_empty()) and game.hotbar.stow():
			game.gym_barbells.request_plate("cable_detach",int(target.get_meta("id",-1)),station)
		else:game.ui.log_message("Free a hotbar slot to remove the plate.")
	return true

func _route_bench_equipment(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):return false
	var kind:=""
	if is_instance_valid(game.gym_barbells) and not game.gym_barbells.held_bar(multiplayer.get_unique_id()).is_empty():kind="bench_barbell"
	elif is_instance_valid(game.gym_weights) and game.gym_weights.held_id(multiplayer.get_unique_id())>=0:kind="bench_dumbbell"
	if kind.is_empty():return false
	var bench:=_aimed_facility()
	if bench.get("kind","")!="benchpress":return false
	game.release_mouse();facility_panel.open_for(bench.id,kind)
	return true

func route_event(event: InputEvent) -> bool:
	if game==null:return false
	if is_instance_valid(sandwich_counter) and sandwich_counter.route_event(event):return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==game.player.keys.interact and is_instance_valid(game.current_target) and game.current_target.get_meta("role","")=="gym_cable_pin":
		var station:=str(game.current_target.get_meta("station",""))
		var weight:=int(game.current_target.get_meta("weight",10))
		var machine:=_cable_machine(station)
		if is_instance_valid(machine) and game.player.enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if machine.occupant != 0 or game.player.global_position.distance_to(game.current_target.global_position) > 3.5:
				game.ui.log_message("Move closer to the stack and wait until the machine is free.")
				return true
			facilities.controller.select_cable_weight(station,weight)
			return true
	if game.player.enabled and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not game.school.formal_active():
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==game.player.keys.interact and _route_cable_plate():return true
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and is_instance_valid(game.gym_barbells):
			var belt: int = game.gym_barbells.held_belt(multiplayer.get_unique_id())
			if belt >= 0:
				game.gym_barbells.request_belt("wear", belt)
				return true
		if _route_bench_equipment(event):return true
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==game.player.keys.interact and _aimed_order():
			if facility_panel.has_order_space.call():facility_panel.request_direct({"op":"pickup","order_id":str(game.current_target.get_meta("order_id","0"))})
			else:game.ui.log_message("Free a hotbar slot first.")
			return true
		if event is InputEventMouseButton and event.pressed and not game.hotbar.selected_food().is_empty():
			if event.button_index==MOUSE_BUTTON_RIGHT:
				facility_panel.request_direct({"op":"consume","order_id":game.hotbar.selected_food().id})
				return true
			if event.button_index==MOUSE_BUTTON_LEFT:
				var camera: Camera3D=game.camera
				var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.0,5)
				var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty() and hit.normal.y>.8 and game.school._table_position(hit.position,multiplayer.get_unique_id()):
					facility_panel.request_direct({"op":"place","order_id":game.hotbar.selected_food().id,"position":hit.position})
					return true
	if is_instance_valid(clothing_panel) and clothing_panel.visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		clothing_panel.hide();game.capture();return true
	if event is InputEventKey and event.pressed and not event.echo and game.player.enabled and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and event.physical_keycode==game.player.keys.interact:
		var target = game.current_target
		if is_instance_valid(target) and target.get_meta("role","")=="clothing_shop":
			game.release_mouse();clothing_panel.show()
			var profile = game.electronics.profile
			var economy: Dictionary=profile.get_meta("economy_display",{}) if game.session.online else preload("res://scripts/economy/temporary_playtest/policy.gd").display_snapshot(true)
			clothing_panel.open_profile(profile.data,null,economy,str(target.get_meta("shop_category","")));return true
	if is_instance_valid(social) and social.route_event(event):return true
	if event is InputEventKey and event.pressed and not event.echo:
		if facility_panel.visible and event.keycode==KEY_ESCAPE:
			facility_panel.close_or_end_workout();return true
		if game.player.enabled and event.physical_keycode==game.player.keys.emotes:
			game.release_mouse();facility_panel.open_for("", "emotes");return true
		if game.player.enabled and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			if not game.player.facility_seat.is_empty() and event.physical_keycode==game.player.keys.jump:
				facility_panel.request_direct({"op":"stand"})
				return true
			if event.physical_keycode==game.player.keys.interact and not game.school.formal_active():
				var aimed := _aimed_facility()
				if not aimed.is_empty() and not (aimed.kind=="seat" and not game.player.facility_seat.is_empty()):
					if aimed.kind=="seat":
						facility_panel.request_direct({"op":"sit","station":aimed.id})
					elif aimed.kind=="seated_bench":
						var peer:=multiplayer.get_unique_id()
						var held:="seated_barbell" if not game.gym_barbells.held_bar(peer).is_empty() else ("seated_dumbbell" if game.gym_weights.held_id(peer)>=0 else "")
						if held.is_empty():game.ui.log_message("Equip dumbbells or a barbell to use the seated bench.")
						else:
							game.release_mouse()
							facility_panel.open_for(aimed.id,held)
							facility_panel.request_direct({"op":"sit","station":aimed.id})
					else:
						game.release_mouse()
						facility_panel.open_for(aimed.id,aimed.kind)
					return true
	return false

func cable_resistance(station: String) -> int:
	var machine:=_cable_machine(station)
	return machine.selected_resistance() if is_instance_valid(machine) else 10

func _cable_machine(station: String) -> Node:
	if not is_instance_valid(facilities) or not facilities.rooms.has("gym"):return null
	for machine in facilities.rooms.gym.gym_cables:
		if is_instance_valid(machine) and str(machine.station_id)==station:return machine
	return null

func _install_clothing_store(layer: CanvasLayer) -> void:
	clothing_room=preload("res://scripts/campus/facilities/clothing_store/room_builder.gd").new()
	clothing_room.position=Vector3(2,5,49);clothing_room.rotation.y=PI/2
	game.campus.add_child(clothing_room)
	# The campus shell supplies floor/wall collision and the exact corridor doorway.
	for child in clothing_room.get_children():
		if str(child.name) in ["Floor","BackWall","LeftWall","RightWall","EntryHeader","EntryLeft","EntryRight","FeatureWall","BrandPanel","Lighthouse","LanternRoom"] or (child is Label3D and child.text.begins_with("M207")):child.hide()
	game.campus.register_content("clothing_store",clothing_room)
	clothing_panel=preload("res://scripts/campus/facilities/clothing_store/store_panel.gd").new()
	layer.add_child(clothing_panel);clothing_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);clothing_panel.hide()
	clothing_panel.close_requested.connect(func():clothing_panel.hide();game.capture())
	clothing_panel.request_id_factory=func():return Crypto.new().generate_random_bytes(16).hex_encode()
	clothing_panel.session.purchase_requested.connect(func(request: Dictionary):
		clothing_pending=str(request.request_id)
		var profile = game.electronics.profile
		if profile.authority_submit.is_valid():profile.authority_submit.call(str(request.op),[request.intent])
		else:
			var cosmetics = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
			if not cosmetics.load_catalog():return
			var adapter=cosmetics.authoritative_adapter(func():return true)
			var result: Dictionary=adapter.commit_local(profile,request.intent)
			clothing_panel.accept_purchase(clothing_pending,result,profile.data);clothing_pending="")
	game.electronics_trade.authority.operation_result.connect(func(op: String,result: Dictionary):
		if op in ["cosmetic_purchase","avatar_cosmetic"] and clothing_pending!="":
			clothing_panel.accept_purchase(clothing_pending,result,game.electronics.profile.data);clothing_pending="")

func _activity_spawn(entrance: Vector3) -> void:
	if not multiplayer.is_server():return
	var index := 0
	for peer in game.session.roster:
		var target := entrance+Vector3((index%4-1.5)*0.7,0,float(index/4)*0.8)
		index+=1
		_relocate(int(peer),target)

func _relocate(peer: int,target: Vector3,yaw := 0.0) -> void:
	var epoch: int=int(game.session.pose_epochs.get(peer,0))+1
	game.session.pose_epochs[peer]=epoch
	game._release_chair(peer)
	game.session.poses[peer]={"position":target,"yaw":yaw,"pitch":0.0,"crouch":false,"seated":false}
	game.session.last_pose[peer]=Time.get_ticks_msec()
	game.session.pose_received.emit(peer,game.session.poses[peer])
	if peer==1:_relocate_local(target,epoch,yaw)
	elif game.session.online:_relocate_local.rpc_id(peer,target,epoch,yaw)

@rpc("authority","call_remote","reliable",4)
func _relocate_local(target: Vector3,epoch: int,yaw: float) -> void:
	game.session.local_pose_epoch=epoch
	if game.player.inspecting:game.end_inspection()
	if is_instance_valid(game.player.seated):
		game.player.seated.rider=null;game.player.seated=null
		game.player.collider.set_deferred("disabled",false)
	game.standing_pending=false
	game.player.global_position=target;game.player.velocity=Vector3.ZERO
	game.player.yaw_target=yaw;game.player.rotation.y=yaw

