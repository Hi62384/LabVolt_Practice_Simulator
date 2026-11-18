extends SceneTree
func _initialize() -> void:call_deferred("run")
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	game.electronics.profile.open("scattered-computer-test")
	game.school.local_identity=game.electronics.profile.data.dorm.owner
	game.session.online=false;game.session.roster[1]={}
	var furniture=game.campus_services.get_node("ComputerCommons")
	var ids:=[]
	for id in furniture.stations:
		if str(id).begins_with("hall_public_") or str(id).begins_with("lobby_public_") or str(id).begins_with("commons_"):ids.append(id)
	if ids.size()!=16:fail("Expected sixteen public workstations");return
	await physics_frame
	for id in ids:
		var station: Node3D=furniture.stations[id]
		if str(id).begins_with("hall_public_"):
			var rear: Vector3=station.global_basis*Vector3(0,0,-1)
			var user_side: Vector3=station.global_basis*Vector3(0,0,1)
			var left_wall:=station.position.x<13.0
			var expected_wall:=Vector3.LEFT if left_wall else Vector3.RIGHT
			var expected_x:=10.52 if left_wall else 15.48
			var wall_gap:=station.position.x-.43-10.08 if left_wall else 15.92-(station.position.x+.43)
			if absf(station.position.x-expected_x)>.01 or rear.dot(expected_wall)<.99 or user_side.dot(-expected_wall)<.99 or wall_gap<0.0 or wall_gap>.03:fail("Hall workstation is not flush to the wall and facing its user side into the corridor: "+str(id));return
		if not game.computers.stations.has(id) or not game.computers.stations[id].has("power"):fail("Unregistered station "+id);return
		var point: Vector3=game.computers.stations[id].anchor
		game.player.global_position=point;game.session.poses[1]={"position":point}
		var start: Vector3=station.to_global(Vector3(.69,.56,.3))
		var finish: Vector3=station.to_global(Vector3(.69,.56,.025))
		var ray:=PhysicsRayQueryParameters3D.create(start,finish,4)
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if not is_instance_valid(hit.get("collider")) or hit.collider.get_meta("role","")!="public_computer_power" or hit.collider.get_meta("station","")!=id:fail("Power target inaccessible "+id);return
		game.computers.request({"op":"power","station":id})
		await create_timer(1.8).timeout
		game.computers.request({"op":"enter","station":id})
		if not game.computers.sessions.has(1):fail("Session failed "+id);return
		if id=="commons_r0_c0":
			var desktop=game.computer_room_adapter.desktop
			desktop.app_list.item_selected.emit(4);await process_frame
			var calculator: Node
			for child in desktop.content.get_children():
				if child.has_method("press") and child.has_method("evaluate"):calculator=child
			if calculator==null:fail("Desktop calculator missing");return
			for label in ["2","+","3","="]:
				var found:=false
				for b in calculator.find_children("*","Button",true,false):
					if b.text==label:b.pressed.emit();found=true;break
				if not found:fail("Calculator key missing: "+label);return
			if not calculator.result.text.is_valid_float() or not is_equal_approx(float(calculator.result.text),5.0):fail("Calculator arithmetic failed: %s -> %s"%[calculator.display.text,calculator.result.text]);return
			desktop.app_list.item_selected.emit(0);await process_frame
		game.computers.stations[id].power.last_activity_ms=Time.get_ticks_msec()-game.computers.stations[id].power.IDLE_TIMEOUT_MS
		game.computers._prune()
		if game.computers.stations[id].power.powered or game.computers.sessions.has(1):fail("Idle shutdown failed "+id);return
	for z in [11.0,26.0,40.0]:
		for y in [0.0,5.0]:
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(13,y+.7,z-1),Vector3(13,y+.7,z+1),1)
			ray.exclude=[game.player.get_rid()]
			if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():fail("Central hallway blocked at %s, %s"%[y,z]);return
	print("SCATTERED_WORKSTATIONS PASS")
	game.queue_free();await process_frame;quit()
