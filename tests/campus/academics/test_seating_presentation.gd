extends SceneTree
## Real Main scene chairs, navigation collisions, generated student rig and HUD.
## Provider calls and physical microphone input are deliberately not required.
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);printerr("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(80.).timeout.connect(func():printerr("SEATING_PRESENTATION timeout");quit(3))
	root.size=Vector2i(1280,720)
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	game.host_openai.enabled=false
	game.player.set_physics_process(false)
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	var students: Node=game.lecture_classes.classroom_students
	students.seating.set_process(false)
	Legacy.seed(students.population,12)
	var person: Dictionary=students.population.profile_for("campus_student_00")
	var room_id:="elm253_lecture"
	var chairs: Array=game.chairs.filter(func(chair):return str(chair.get_meta("classroom_room",""))==room_id)
	check(chairs.size()==8,"Classroom mounts eight actual stable chairs")
	if chairs.size()<2:quit(1);return
	var first: Node3D=chairs[0]
	game.player.global_position=first.global_position+Vector3(0,0,1.6)
	for frame in 3:await physics_frame
	var room: Dictionary=game.school.room_bridge.room("ELM253","lecture",room_id)
	var member:={"profile":person,"seat":first.global_position,"position":first.global_position,"arrival":0.,"arrived":true,
		"seated":true,"standing":false,"walking":false,"has_seat":true,"action":"listening","next":999999.,"turns":0}
	var activity:={"id":"seating-fixture","course":"ELM253","kind":"lecture","teacher":"mr_bro","phase":"arrival","room":room,"classmates":{person.id:member}}
	game.lecture_classes.classes[room_id]=activity
	check(students.seating.assign(member,str(activity.id)),"NPC claims a real chair")
	check(first.seat_state()=="npc" and first.occupant==0,"Unified chair reports NPC occupancy")
	check(not students.seating.assign(member,str(activity.id)),"Second claim cannot occupy same chair")
	var other: Dictionary=member.duplicate(true);other.profile=students.population.profile_for("campus_student_01")
	check(not students.seating.assign(other,str(activity.id)),"Different NPC cannot overlap same chair")
	var displaced: Node3D=chairs.back()
	var authored_position: Vector3=displaced.global_position
	displaced.global_position+=Vector3(1000,0,0)
	var no_players: Array[Vector3]=[]
	check(not students.seating.available_points(room,no_players).has(displaced.global_position),"A chair rolled outside the classroom is not an available class seat")
	var misplaced: Dictionary=other.duplicate(true);misplaced.seat=displaced.global_position
	check(not students.seating.assign(misplaced,str(activity.id)),"Displaced chair cannot spawn a new NPC claim outside the room")
	check(not students.seating.move_student(member,activity,room_id,displaced.global_position),"Discipline cannot send a student to a displaced hallway chair")
	displaced.global_position=authored_position
	var public:={room_id:{"classmates":students.snapshot(activity,1.)}}
	students.render(room_id,public,.1)
	var model: Node3D=students.models[str(activity.id)+":"+str(person.id)]
	var animation:=model.get_node("AnimationPlayer") as AnimationPlayer
	animation.play("Seated");animation.seek(.5,true);animation.pause()
	var body_yaw:=model.rotation.y
	var target:=model.global_position+Vector3(4,1.4,0)
	for frame in 20:Motion.express(model,"sad",.1,"",.2,Vector3.INF,{"sadness":.9},person.traits,target)
	check(absf(wrapf(model.rotation.y-body_yaw,-PI,PI))<.001,"Attention never rotates seated pelvis")
	var head:=model.get_node("Body/Head") as Node3D
	check(absf(head.rotation.y)>.1 and absf(head.rotation.y)<=1.151,"Head tracks within limits while retaining affect")
	var knee:=model.get_node("LegL/Knee") as Node3D
	check(absf(knee.rotation.x-PI*.5)<.01,"Seated student has bent knee")
	check(absf(knee.global_basis.y.normalized().dot(Vector3.UP))>.9,"Shin points down instead of projecting straight ahead")
	check(model.get_node("StudentName").text==str(person.name),"Only name appears above the NPC")
	var player: Node=game.faculty.speech_player
	player.configure(false,true)
	game.hotbar.show();game.health.overlay.show();game.held_hint.show();game.held_hint.text="E: request chair"
	check(player.accept("presentation-fixture","Riley",1,"This caption must remain above the health bar, inventory and interaction prompt.",3,model),"Caption accepted")
	for frame in 4:await process_frame
	player._layout_subtitles()
	var caption: Label=player.subtitles["presentation-fixture"].label
	for obstacle: Control in [game.hotbar.bar,game.health.bar,game.held_hint]:
		if obstacle.is_visible_in_tree():check(not caption.get_global_rect().intersects(obstacle.get_global_rect()),"Caption clears "+str(obstacle.get_class()))
	if DisplayServer.get_name()!="headless":
		var camera:=Camera3D.new();root.add_child(camera);camera.current=true
		camera.global_position=model.global_position+Vector3(2.4,1.5,-.4)
		camera.look_at(model.global_position+Vector3.UP*.85)
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		var output:=OS.get_environment("LABVOLT_STARTUP_CAPTURE")
		if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("classroom-seating-subtitles.png"))==OK,"Rendered classroom capture saved")
	root.size=Vector2i(960,540);root.content_scale_factor=1.25
	for frame in 3:await process_frame
	player._layout_subtitles()
	check(caption.get_viewport_rect().encloses(caption.get_global_rect()),"Caption remains inside smaller scaled viewport")
	# Use the real walk/return path from a claimed chair, not a route-only mock.
	var previous_player: Vector3=game.player.global_position
	game.player.global_position=first.global_position+Vector3(0,0,2.7)
	check(students.act(room_id,activity,member,"approach",game.player.global_position,1.),"A seated student can leave their own chair to approach")
	for step in 200:
		if not member.has("walk"):break
		students._step_walk(activity,member,1.+float(step)*.2,.1)
	check(not member.has("walk") and member.seated and (member.position as Vector3).distance_to(first.global_position)<.15,"Approach returns to the original claimed chair")
	var foreign: Dictionary=member.duplicate(true);foreign.seat_id=chairs[1].seat_id
	check(students._own_chair_bodies(foreign).is_empty(),"Approach cannot exclude another chair's collisions")
	game.player.global_position=previous_player
	game.session.roster[2]={"name":"Second human"};game.session.poses[2]={"position":game.player.global_position}
	game._claim_chair(1,game.chairs.find(first))
	check(first.reserved_peer==1 and first.occupant==0 and member.has("seat_relocation"),"Human request reserves chair and stands NPC before sitting")
	game._claim_chair(2,game.chairs.find(first))
	check(first.reserved_peer==1 and first.occupant==0,"Simultaneous request cannot steal reservation")
	# An empty destination may roll before the NPC reaches it. Abort in place
	# and make the request retryable instead of snapping to the moved chair.
	if member.has("seat_relocation"):
		var moving: Node3D=students.seating.chair_for(str(member.seat_relocation.destination))
		if moving!=null:
			var prior_chair: Vector3=moving.global_position
			var prior_student: Vector3=member.position
			moving.global_position+=Vector3(0,0,1.)
			member.seat_relocation.starts=0;students.seating.step(member,.08);students.seating._process(1.)
			check(not member.has("seat_relocation") and not member.seated and member.position==prior_student,"Moved destination cannot teleport a seated NPC")
			check(moving.npc_occupant.is_empty() and first.reserved_peer==0,"Moved destination releases pending claims")
			moving.global_position=prior_chair
			check(students.act(room_id,activity,member,"sit",member.position,2.),"Student can reseat after an aborted request")
			game._claim_chair(1,game.chairs.find(first))
	if member.has("seat_relocation"):
		var blocked_destination: Node3D=students.seating.chair_for(str(member.seat_relocation.destination))
		var stopped_at: Vector3=member.position
		game.session.roster[3]={"name":"Aisle blocker"};game.session.poses[3]={"position":stopped_at+Vector3(.4,0,0)}
		member.seat_relocation.starts=0;students.seating.step(member,.08)
		check(not member.has("seat_relocation") and member.position==stopped_at,"New actor obstruction stops movement in place")
		check(first.reserved_peer==0 and first.npc_occupant==str(person.id) and (blocked_destination==null or blocked_destination.npc_occupant.is_empty()),"Blocked route retains only the real origin occupant")
		game.session.roster.erase(3);game.session.poses.erase(3)
		check(students.act(room_id,activity,member,"sit",member.position,3.),"Blocked request leaves a recoverable seat")
		game._claim_chair(1,game.chairs.find(first))
	if member.has("seat_relocation"):
		var stopped_at: Vector3=member.position
		# NPC interaction colliders use layer 4, outside the floor-route mask.
		# Their authoritative body positions still have to block relocation.
		activity.classmates[other.profile.id]={"profile":other.profile,"position":stopped_at+Vector3(.4,0,0),"arrival":0.,"arrived":true,"seated":false}
		member.seat_relocation.starts=0;students.seating.step(member,.08)
		check(not member.has("seat_relocation") and member.position==stopped_at,"A standing NPC blocks relocation without body overlap")
		activity.classmates.erase(other.profile.id)
		if not member.has("seat_relocation"):
			check(students.act(room_id,activity,member,"sit",member.position,3.5),"NPC obstruction also leaves a recoverable seat")
			game._claim_chair(1,game.chairs.find(first))
	check(member.has("seat_relocation"),"Clearing the route permits a fresh handoff")
	if member.has("seat_relocation"):
		member.seat_relocation.starts=0
		for step in 240:
			students.seating.step(member,.08)
			if step%10==0:await process_frame
			if not member.has("seat_relocation"):break
		await process_frame
		check(not member.has("seat_relocation") and member.seated,"NPC completes real collision-checked relocation")
		check(first.npc_occupant.is_empty() and first.occupant==1,"Human sits only after original chair clears")
		var destination: Node3D=students.seating.chair_for(str(member.get("seat_id","")))
		check(destination!=null and destination!=first and destination.npc_occupant==str(person.id),"NPC occupies a distinct real destination chair")
		for candidate in chairs:
			if candidate.available_for_npc() and students.seating.move_student(member,activity,room_id,candidate.global_position):break
		check(member.has("seat_relocation"),"Class-end cleanup is tested during a second move")
		game.lecture_classes.classes.clear();students.seating._process(1.)
		check(destination==null or destination.npc_occupant.is_empty(),"Class ending releases NPC occupancy")
		check(chairs.all(func(chair):return chair.npc_occupant!=str(person.id)),"Class ending releases both in-flight origin and destination")
	var reservation: Node3D=chairs[1]
	reservation.reserved_peer=2;reservation.reservation_until=Time.get_ticks_msec()+5000
	game.session.roster.erase(2)
	students.seating._process(1.)
	check(reservation.reserved_peer==0,"Disconnected requester's reservation is released")
	reservation.reserved_peer=1;reservation.reservation_until=1
	students.seating._process(1.)
	check(reservation.reserved_peer==0,"Expired reservation cannot softlock a chair")
	game.session.roster.erase(2);game.session.poses.erase(2)
	game.queue_free();await process_frame
	print("SEATING_PRESENTATION %s (real Main, chairs, paths, claims, rig, HUD; no live provider/hardware)"%("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
