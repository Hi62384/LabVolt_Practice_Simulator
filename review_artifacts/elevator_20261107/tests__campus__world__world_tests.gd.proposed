extends SceneTree
var failures: Array = []
var checks := 0
func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var registry=preload("res://scripts/campus/world/room_registry.gd").new()
	check(registry.rooms.size()==14,"14 uniquely registered purpose-built rooms")
	var numbers: Array=[]
	for room in registry.rooms.values():
		check(not numbers.has(room.number),"unique number "+str(room.number))
		numbers.append(room.number)
		check(registry.locate(registry.vector(room.center))==room.id,"room bounds "+str(room.id))
		check(registry.room_slip(room.id).room_number==room.number,"slip number "+str(room.id))
		var route: PackedVector3Array=registry.route("exterior",room.id)
		check(route.size()>=5,"route to "+str(room.id))
		check(route[route.size()-1].is_equal_approx(registry.vector(room.anchor)),"route destination "+str(room.id))
	check(registry.course_room("ELM253","lab").id=="ac_lab","ELM253 AC room")
	check(registry.course_room("ETY155","lecture").number=="M202","ETY155 lecture room")
	check(registry.search("DC Electrical").size()==1,"directory search")
	check(registry.search("M102")[0].id=="shop","number search")
	check(registry.get_room("unknown").is_empty(),"unknown room safe")
	var copy: Dictionary=registry.get_room("ac_lab")
	copy.number="bad"
	check(registry.get_room("ac_lab").number=="M101","defensive copy")
	check(registry.activity_room("ETY155","lab").id=="dc_lab","academic adapter DC room")
	check(registry.activity_room("ETY155","lab").benches[0].z==22,"DC composition keeps centre aisle clear")
	check(registry.activity_room("ETY155","lab").desks.size()==3,"DC papers use three actual workbench surfaces")
	check(registry.activity_room("ELM253","lecture").seats.size()==8,"eight academic seat anchors")
	check(registry.room_contains("ac_lab",Vector3(0,0,3)),"academic room contains")
	check(registry.route_from_position(Vector3(14,5,25),"dc_lab").size()>8,"upper corridor route uses stairs")
	check(registry.route("hall_f1","dc_lab").size()>8,"direct hall route preserves upper floor")
	var guide=preload("res://scripts/campus/world/navigation.gd").new()
	check(not guide.select_room("unknown",Vector3.ZERO),"guidance rejects unknown room")
	check(guide.select_room("shop",Vector3(13,0,-18)),"optional guide selects real room")
	check(guide.update(Vector3(13,0,-18)).number=="M102","guide uses central number")
	check(guide.update(Vector3(26,0,3)).arrived,"guide detects arrival")
	guide.clear()
	check(not guide.update(Vector3.ZERO).enabled,"guide can be disabled")
	check(registry.route_from_position(Vector3(11.5,2,55),"ety155_lecture")[1]==Vector3(11.5,5,62),"mid-stair navigation goes to actual landing")
	var campus=preload("res://scenes/campus/Campus.tscn").instantiate()
	root.add_child(campus)
	await physics_frame
	await physics_frame
	check(campus.room_roots.size()==14,"all shells built")
	check(campus.materials.size()<12,"shared materials bounded")
	check(campus.solid_count<180,"modest static collision count")
	# Horizontal body-sized sweeps prove each open door is clear in the built physics world.
	var capsule := CapsuleShape3D.new()
	capsule.radius=.27
	capsule.height=1.7
	var physics: PhysicsDirectSpaceState3D = campus.get_world_3d().direct_space_state
	for room in registry.rooms.values():
		var door: Vector3=registry.vector(room.door)
		var start: Vector3=door+Vector3(-1 if door.x<13 else 1,.9,0)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,start)
		query.motion=Vector3(2 if door.x<13 else -2,0,0)
		query.collision_mask=1
		var fraction: PackedFloat32Array=physics.cast_motion(query)
		check(fraction[0]>.99,"walkable door "+str(room.id))
	# Continuous ground hall and upper bypass are clear of solid walls.
	for segment in [[Vector3(14.5,.9,-18),Vector3(0,0,83)],[Vector3(14.5,5.9,-3),Vector3(0,0,68)]]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,segment[0])
		query.motion=segment[1]
		query.collision_mask=1
		check(physics.cast_motion(query)[0]>.99,"connected floor corridor")
	# Actual CharacterBody traversal, no teleport, same collision layer as existing player.
	var walker := CharacterBody3D.new()
	walker.collision_layer=2
	walker.collision_mask=1
	walker.floor_snap_length=.3
	var cs := CollisionShape3D.new()
	cs.shape=capsule
	cs.position.y=.85
	walker.add_child(cs)
	root.add_child(walker)
	walker.position=Vector3(11.5,.05,49)
	var max_y := 0.0
	for i in range(650):
		walker.velocity=Vector3(0,-2,2.7)
		walker.move_and_slide()
		max_y=maxf(max_y,walker.position.y)
		await physics_frame
		if walker.position.z>63: break
	print("STAIR_WALK position=",walker.position," max_y=",max_y); check(max_y>4.9 and walker.position.z>62.5,"player capsule climbs real staircase")
	walker.queue_free()
	var content := Node3D.new()
	campus.add_child(content)
	check(campus.register_content("shop",content),"register presentation")
	campus.streamer.set_process(false)
	campus.set_viewer_position(Vector3(26,0,3))
	check(campus.streamer.advance(50000)==0,"slow frame gates activation")
	check(campus.streamer.queue.size()>0,"gate preserves queued work")
	for i in range(10): campus.streamer.advance(16000)
	check(content.visible,"near shop activates")
	campus.set_viewer_position(Vector3(0,5,33))
	for i in range(10): campus.streamer.advance(16000)
	check(not content.visible,"other floor deactivates shop presentation")
	check(content.process_mode==Node.PROCESS_MODE_INHERIT,"simulation not disabled")
	var staged := [0]
	campus.streamer.register_loader("shop",func(): staged[0]+=1; return staged[0]>=3)
	campus.set_viewer_position(Vector3(26,0,3))
	campus.streamer.advance(50000)
	check(staged[0]==0,"budget gate prevents heavy loader invocation")
	campus.streamer.advance(16000)
	check(staged[0]==1,"loader performs only one unfinished stage per advance")
	check(not content.visible,"unfinished zone stays hidden")
	for i in range(5): campus.streamer.advance(16000)
	check(staged[0]==3 and content.visible,"incremental loader completes then activates")
	var slow_loader=preload("res://scripts/campus/world/zone_streamer.gd").new()
	var recovered := [0]
	slow_loader.register_loader("shop",func(): recovered[0]+=1; return false)
	for i in range(5): slow_loader.advance(33333)
	check(recovered[0]==1,"sustained 30 FPS admits one bounded recovery stage")
	check(slow_loader.metrics().recovery_admissions==1,"slow-client recovery admission measured")
	slow_loader.free()
	var target: Node
	for child in campus.elevator_geometry.get_children():
		if child.get_meta("role", "") == "elevator_control": target=child; break
	check(is_instance_valid(target), "physical elevator controls mounted")
	var actor := Node3D.new()
	campus.add_child(actor); actor.global_position=target.global_position
	var old: Vector3=actor.position
	var calls := [0]
	campus.elevator_control_requested.connect(func(_floor, _button): calls[0]+=1)
	campus.interact(target,actor)
	check(actor.position==old, "world never bypasses host multi-rider service")
	check(calls[0]==1, "physical control requests authoritative service")
	actor.position=Vector3.ZERO; campus.interact(target,actor)
	check(calls[0]==1, "remote control rejected")
	print("WORLD_METRICS ",JSON.stringify(campus.metrics()))
	print("WORLD_TESTS checks=",checks," failures=",failures.size())
	campus.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)



