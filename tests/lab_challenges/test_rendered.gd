extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("run")
func artifact(name: String) -> String:
	var folder := OS.get_environment("LAB_CHALLENGE_ARTIFACTS")
	if folder.is_empty():folder=OS.get_user_data_dir().path_join("lab-challenge-tests")
	DirAccess.make_dir_recursive_absolute(folder);return folder.path_join(name)
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Graphical correctness test requires coordinator lease");quit(1);return
	root.size=Vector2i(1280,720)
	var ledger := preload("res://scripts/inventory_authority/ledger.gd").new();var profile := preload("res://scripts/electronics_profile.gd").new();profile.open("challenge-render-fixture")
	if ledger.open("user://render_"+Crypto.new().generate_random_bytes(5).hex_encode())!=OK:quit(1);return
	ledger.bind(1,"1".repeat(48),"3".repeat(64),profile.data);ledger.bind(2,"2".repeat(48),"4".repeat(64),profile.data)
	var state := preload("res://scripts/lab_state.gd").new();state.initialize(preload("res://tests/fixture.gd").ids(),preload("res://tests/fixture.gd").locations())
	var host := preload("res://scripts/lab_challenges/host.gd").new();host.store.ledger=ledger;host.labs=[state]
	host.store.authority=func():return true
	host.allowed=func(_peer,_bench,_command):return true
	host.names=func(peer):return "Repair student" if peer==1 else "Measurement student"
	var started: Dictionary=host.act(1,0,{"command":"start","kind":"unbalanced_load","seed":12})
	if not started.ok:push_error(str(started));quit(1);return
	var panel := preload("res://scripts/lab_challenges/panel.gd").new();root.add_child(panel);panel.build();panel.show_at(0);panel.update_frame(host.view(1,0),"Real host-generated challenge · physical evidence required")
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifact("challenge-panel.png"))
	panel.queue_free();await process_frame
	var world := Node3D.new();root.add_child(world)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("101b2b");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.0;world.add_child(environment)
	var wall := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(8,4,.2);wall.mesh=box;wall.position=Vector3(0,2,-3.3);var material := StandardMaterial3D.new();material.albedo_color=Color("263b42");wall.material_override=material;world.add_child(wall)
	var camera := Camera3D.new();camera.position=Vector3(0,2.9,1.0);world.add_child(camera);camera.look_at(Vector3(0,3.75,-3.17))
	var decorations := preload("res://scripts/lab_challenges/decorations.gd").render(world,0,{"left_award":{"id":"phasor_print"},"right_award":{"id":"team_plaque"}})
	for node in decorations.get_children():
		if node is CollisionObject3D:failures+=1
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifact("fixed-lab-honours.png"))
	world.queue_free();await process_frame
	print("BASE_RENDERED_RESULT failures=",failures," captures=2 display=",DisplayServer.get_name())
	quit(1 if failures else 0)
