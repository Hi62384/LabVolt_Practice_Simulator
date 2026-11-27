extends Node
## Run on a real display (a software Xorg display also works):
## godot --path . --rendering-method gl_compatibility \
##   res://docs/verification/character-overhaul/character_motion.tscn
## Optional user argument: -- /absolute/output.png
## This renders production Toon geometry and production Motion/prop helpers.
const Toon=preload("res://scripts/toon_character.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const OUTPUT:="res://docs/verification/character-overhaul/character_motion.png"
const CASES:=[
	{"title":"Happy","note":"joy / relaxed posture","mood":"happy","pose":"","affect":{"happiness":.95,"amusement":.7}},
	{"title":"Angry","note":"narrow eyes / lowered brows","mood":"angry","pose":"","affect":{"anger":.95,"irritation":.9}},
	{"title":"Hurt","note":"sadness / lowered gaze","mood":"sad","pose":"","affect":{"sadness":.95,"disappointment":.8,"anxiety":.25}},
	{"title":"Tired","note":"heavy eyelids / slumped torso","mood":"tired","pose":"","affect":{"tiredness":.95,"boredom":.65}},
	{"title":"Defensive","note":"hurt / guarded arms","mood":"sad","pose":"defensive","affect":{"sadness":.75,"anxiety":.75}},
	{"title":"Arguing","note":"anger / two-arm gesture","mood":"angry","pose":"argue","affect":{"anger":.9,"irritation":.85}},
	{"title":"Turning away","note":"withdrawal / averted face","mood":"sad","pose":"turn_away","affect":{"sadness":.7,"disappointment":.8}},
	{"title":"Using a phone","note":"lowered gaze / actual phone prop","mood":"interested","pose":"phone","affect":{"interest":.8}},
]
var models: Array[Node3D]=[]
var root: Window

func _ready() -> void:
	root=get_tree().root
	call_deferred("render")

func render() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This visual probe needs a rendering display; headless dummy output is not evidence.")
		get_tree().quit(2);return
	root.size=Vector2i(1500,1120)
	root.title="LabVolt — production character expression comparison"
	var background:=ColorRect.new();background.color=Color("111d2a");background.size=Vector2(1500,1120);root.add_child(background)
	_label("LabVolt · actual character rig",Vector2(30,22),30,Color("edf5ff"))
	_label("Same authored character, production emotion and pose code. Native OpenGL render; no generated artwork.",Vector2(32,64),17,Color("afc0d4"))
	for index in CASES.size():_panel(index,CASES[index])
	for frame in 6:
		for index in models.size():
			var state: Dictionary=CASES[index]
			Motion.express(models[index],state.mood,1.,state.pose,.65,Vector3.INF,state.affect,{"expressiveness":.85,"confidence":.55})
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture:=root.get_texture().get_image()
	if capture==null or capture.is_empty():push_error("Native renderer returned no image");get_tree().quit(3);return
	var output:=str(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else OUTPUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var error:=capture.save_png(output)
	print("CHARACTER_MOTION_RENDER ","PASS" if error==OK else "FAIL", " display=",DisplayServer.get_name()," adapter=",RenderingServer.get_video_adapter_name()," output=",output)
	get_tree().quit(0 if error==OK else 4)

func _panel(index: int,state: Dictionary) -> void:
	var origin:=Vector2(24+(index%4)*370,108+(index/4)*494)
	var panel:=ColorRect.new();panel.position=origin;panel.size=Vector2(348,474);panel.color=Color("1c2c3e");root.add_child(panel)
	_label(state.title,origin+Vector2(16,13),23,Color("f2f6fc"))
	_label(state.note,origin+Vector2(16,43),13,Color("aabbd0"))
	var container:=SubViewportContainer.new();container.position=origin+Vector2(6,74);container.size=Vector2(336,390);container.stretch=true;root.add_child(container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(336,390);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("1c2c3e")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d6e5fa");env.environment.ambient_light_energy=.3
	world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=.7;light.shadow_enabled=true;world.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-15,140,0);fill.light_energy=.2;world.add_child(fill)
	var appearance:=Toon.defaults();appearance.hair="Crop"
	var model:=Toon.build(appearance);world.add_child(model);models.append(model)
	var animation:=model.get_node("AnimationPlayer") as AnimationPlayer;animation.stop();animation.active=false
	if state.pose=="phone":Students._render_activity_items(model,"using phone")
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.65;camera.position=Vector3(0,1.55,3.8);world.add_child(camera);camera.look_at(Vector3(0,1.12,0));camera.current=true

func _label(text: String,at: Vector2,size: int,color: Color) -> void:
	var label:=Label.new();label.text=text;label.position=at;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color);root.add_child(label)
