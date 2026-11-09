extends SceneTree
## Short rendered QA harness. Run only in the coordinator's reserved rendered window.
const Room=preload("res://scripts/campus/facilities/facility_room.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
const FacilityPanel=preload("res://scripts/campus/facilities/facility_panel.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("25343e");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=0.75
	environment.environment=env;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-35,0);world.add_child(light)
	var gym:=Room.new();world.add_child(gym);gym.build({"id":"gym","kind":"gym","anchor":[-8,0,0]},Rules.new().menu)
	var food:=Room.new();world.add_child(food);food.build({"id":"tim_hortons","kind":"restaurant","anchor":[13,0,0]},Rules.new().menu)
	food.box(Vector3(0,-0.12,0),Vector3(20,0.2,12),Color("b9b8b1"))
	gym.box(Vector3(0,-0.12,0),Vector3(20,0.2,12),Color("777f86"))
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(29,25,34);camera.look_at(Vector3(2,0,0));camera.current=true
	var panel=FacilityPanel.new();root.add_child(panel);panel.position=Vector2(20,20)
	panel.station_kind="counter:tim_hortons";panel.station_id="tim_hortons/counter"
	panel.state={"level":2,"profile":Rules.empty_profile(),"menu":Rules.new().menu,"active":{}}
	panel.state.profile.xp=100;panel.redraw()
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	var result:=get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/facilities-preview.png"))
	print("VISUAL capture=",result)
	world.queue_free();panel.queue_free()
	await process_frame;await process_frame
	quit(0 if result==OK else 1)
