extends SceneTree
var failures := 0
func check(value: bool,label: String) -> void:
	if value:print("PASS "+label)
	else:failures+=1;printerr("FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	await process_frame;await process_frame
	game.school.start("Freeplay",0)
	var service: Node=game.campus_services.facilities
	var host: RefCounted=service.controller.host
	check(service.movement_ready,"live movement hooks installed")
	check(service.rooms.size()==3,"gym and both restaurants use real campus rooms")
	var counter := "";var seat := ""
	for id in host.anchors:
		if host.anchors[id].kind=="counter:tim_hortons":counter=id
		if host.anchors[id].kind=="seat" and host.anchors[id].room_id=="tim_hortons":seat=id
	check(counter!="" and seat!="","real counter and seats registered")
	var point: Vector3=host.anchors[counter].position;point.y=0
	game.player.global_position=point;game.session.poses[1]={"position":point}
	var before: float=game.electronics.profile.data.dollars
	var sequence: int=int(host.private_state(1).profile.last_sequence)+1
	var response: Dictionary=host.act(1,{"op":"buy","station":counter,"item":"coffee","sequence":sequence})
	check(response.get("ok",false),"buy coffee through actual authority and physical counter")
	check(game.electronics.profile.data.dollars==before-3,"same profile money debited atomically")
	var reload_profile=preload("res://scripts/electronics_profile.gd").new();reload_profile.open(game.characters.selected if game.characters.selected!="" else "__default__")
	# The exact file bound by ElectronicsUI is authoritative for the offline adapter.
	var stored: Variant=JSON.parse_string(FileAccess.get_file_as_string(game.electronics.profile.path))
	check(stored is Dictionary and stored.facilities.held.item=="coffee" and stored.dollars==before-3,"food and money saved together")
	point=host.anchors[seat].position;point.y=0
	game.player.global_position=point;game.session.poses[1]={"position":point}
	host.last_request.clear()
	sequence=int(host.private_state(1).profile.last_sequence)+1
	response=host.act(1,{"op":"sit","station":seat,"sequence":sequence})
	check(response.get("ok",false) and host.movement_locked(1),"physical seat locks authoritative translation")
	var proposed := point+Vector3.RIGHT
	check(service.accept_translation(1,proposed,point)==point,"host rejects movement while seated")
	host.last_request.clear();sequence=int(host.private_state(1).profile.last_sequence)+1
	response=host.act(1,{"op":"stop","sequence":sequence})
	check(response.get("ok",false) and not host.movement_locked(1),"stand restores movement")
	game.school.mode="Class";game.school.phase="assignment";game.school.class_students={"test":{"done":false}}
	host.last_request.clear();sequence=int(host.private_state(1).profile.last_sequence)+1
	response=host.act(1,{"op":"sit","station":seat,"sequence":sequence})
	check(not response.get("ok",true),"active class prevents facility bypass")
	game.school._reset_session()
	var epoch: int=int(game.session.pose_epochs.get(1,0))
	game.campus_services._relocate(1,Vector3(13,0,-18))
	game.session.accept_pose(1,{"position":point,"pose_epoch":epoch})
	check(game.session.poses[1].position==Vector3(13,0,-18),"stale pre-teleport movement packet rejected")
	var project: Dictionary=game.campus_services.provider.generate("ELM253",5,"lab",4,42)
	check(not game.school._public_project(project).has("reference_ac"),"AC solver answer key excluded from unmarked public worksheet")
	game.queue_free();await process_frame
	print("LIVE FACILITIES failures=%d"%failures);quit(1 if failures else 0)
