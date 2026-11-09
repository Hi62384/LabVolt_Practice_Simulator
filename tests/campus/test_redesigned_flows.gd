extends SceneTree
## Use a disposable APPDATA directory. Exercises the normal Main.tscn entry points.
var errors := 0

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: errors += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var catalog: Dictionary = game.school.menu_catalog()
	for code in ["ELM253","ETY155","MTH147","MTH255"]:
		check(str(catalog).contains(code), "gradebook lists " + code)
	game.front.settings_page()
	check(is_instance_valid(game.front.menu_page), "settings mounts")
	game.front.singleplayer_page()
	check(is_instance_valid(game.front.menu_page), "Singleplayer setup mounts")
	game.front.entered()
	game.school.start("Freeplay", 2)
	var room = game.dorm_interactions.locate_room(1)
	check(not str(room.room_id).is_empty() and not str(room.entrance).is_empty(), "local dorm assigned")
	var station = game.shop_room.workshop
	check(station.stations.size() == 3, "M102 routes Circuit Maker, IC and PCB")
	var washrooms: Dictionary = game.washroom_finish.roots
	check(washrooms.has("washroom_1") and washrooms.has("washroom_2"), "both washrooms built")
	for key in ["clothing_store","circuit_studio"]:
		var entry: Dictionary = game.campus.registry.get_room(key)
		var doorway: Vector3 = game.campus.registry.vector(entry.door)
		await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(doorway + Vector3(-1.2,1.65,0),doorway+Vector3(1.2,1.65,0),1)
		check(game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "clear " + str(entry.number) + " doorway")
	var practice = preload("res://scripts/campus/academics/open_lab/practice/practice_service.gd")
	for key in ["ac_lab", "dc_lab"]:
		var result: Dictionary = practice.issue_for_room(key, game.school.course_bridge, 51094, 2, 4)
		check(result.get("week",0) == 2 and result.get("difficulty",0) == 4 and result.get("practice_scope") == "ungraded", "requested practice week and difficulty for " + key)
	check(practice.issue_for_room("dc_lab", game.school.course_bridge, 1, 55, 4).has("error"), "unsupported week rejected")
	game.player.global_position = Vector3(0,0,20.6)
	var dc = game.dc_lab
	dc.accept(1, 1, {"op":"lead_drawer"})
	check(dc.drawer_open[1], "DC drawer opens")
	dc.accept(1, 1, {"op":"take_lead","color":1})
	check(dc.carried_leads.get(1) == 1, "DC blue lead picked up")
	var terminals: Array = dc.ports[1].keys()
	dc.accept(1, 1, {"op":"begin_external","port":terminals[0],"physical":true})
	dc.accept(1, 1, {"op":"wire","a":terminals[0],"b":terminals[1],"physical":true})
	check(dc.benches[1].wires.size()==1 and dc.benches[1].lead_colors.values().has(1), "DC lead attaches and retains color")
	dc.accept(1, 1, {"op":"unwire","index":0})
	check(dc.benches[1].wires.is_empty(), "DC lead disconnects")
	var instructor: Node3D = game.school_world.dc_instructor
	game.player.global_position = instructor.global_position
	game.session.poses[1].position = instructor.global_position
	game.school.apply(1, {"op":"practice_lesson","week":2,"difficulty":4})
	var practice_id: int = game.school.held(1)
	check(practice_id > 0 and game.school.papers[practice_id].project.get("course_id") == "ETY155", "M103 instructor issues its actual practice sheet")
	if practice_id > 0:
		game.school.apply(1, {"op":"stroke","id":practice_id,"page":0,"points":[Vector2(.1,.1),Vector2(.2,.2)],"color":"222222","width":3})
		game.school.apply(1, {"op":"undo_stroke","id":practice_id,"page":0})
		check(game.school.papers[practice_id].strokes.get("0", []).is_empty(), "worksheet stroke undo")
		game.school.apply(1, {"op":"redo_stroke","id":practice_id,"page":0})
		check(game.school.papers[practice_id].strokes.get("0", []).size() == 1, "worksheet stroke redo")
		game.school.start("Freeplay", 2)
		check(game.school.papers.values().any(func(sheet):return sheet.project.get("course_id") == "ETY155" and sheet.strokes.get("0", []).size() == 1), "practice annotations survive mode reload")
	game.electronics.open("shop")
	var store: Control = game.electronics.shop_adapter.panel
	check(store.product_buttons.values().any(func(card):return card.visible), "Component Counter shows products with an empty search")
	game.electronics.close()
	var guide: Dictionary = preload("res://scripts/equipment_guide.gd").project()
	var paper: int = game.school._give(1,guide,true,false)
	game.school.papers[paper].guide = true
	game.paper_ui.open_sheet(paper)
	check(is_instance_valid(game.paper_ui.tool_case) and is_instance_valid(game.paper_ui.calculator_drawer), "worksheet pencil case and upright calculator mount")
	game.queue_free()
	await process_frame
	quit(errors)

