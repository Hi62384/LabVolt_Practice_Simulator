extends SceneTree
## Native renderer probe of production geometry, Motion and SpeechPlayer.
## godot --path . --rendering-method gl_compatibility --audio-driver Dummy \
##   --script res://tests/campus/academics/render_character_faces.gd -- /absolute/output.png
## A real DisplayServer is required. No headless dummy images are accepted.
const Toon=preload("res://scripts/toon_character.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Speech=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const CASES:=[
	{"title":"Neutral","mood":"steady"},
	{"title":"Happy","mood":"happy","affect":{"happiness":.95}},
	{"title":"Angry","mood":"angry","affect":{"anger":.95}},
	{"title":"Sad","mood":"sad","affect":{"sadness":.95}},
	{"title":"Tired","mood":"tired","affect":{"tiredness":.95}},
	{"title":"Excited","mood":"excited","affect":{"happiness":.7,"excitement":.95}},
	{"title":"Grin → angry","mood":"angry","expression":"Grin","affect":{"anger":.95}},
	{"title":"Square glasses / angry","mood":"angry","glasses":"Square","affect":{"anger":.95}},
	{"title":"Round glasses / sad","mood":"sad","glasses":"Round","affect":{"sadness":.95}},
	{"title":"Blink + angry","mood":"angry","blink":true,"affect":{"anger":.95}},
	{"title":"Speaking + sad","mood":"sad","expression":"Grin","speech":true,"affect":{"sadness":.95}},
	{"title":"After speech / angry","mood":"angry","expression":"Grin","stopped":true,"affect":{"anger":.95}},
]
var models: Array[Node3D]=[]
var speech: Node

func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("FACIAL_RENDER requires an actual rendering display, not the dummy renderer")
		quit(2);return
	root.size=Vector2i(1280,1060)
	root.title="LabVolt actual facial animation probe"
	var background:=ColorRect.new();background.color=Color("102032");background.size=Vector2(1280,1060);root.add_child(background)
	_label("LabVolt · facial animation",Vector2(24,15),27)
	_label("Production Toon / Motion / SpeechPlayer — native rendering, same proportions in every panel",Vector2(26,52),16)
	speech=Speech.new();root.add_child(speech);speech.configure(true,false)
	var audio:=_audio()
	for index in CASES.size():
		_panel(index,CASES[index])
		var model:=models[index]
		var animation:=model.get_node("AnimationPlayer") as AnimationPlayer
		animation.play("Idle");animation.advance(2.78 if CASES[index].get("blink",false) else .4)
		animation.pause()
		if CASES[index].get("speech",false) or CASES[index].get("stopped",false):
			speech.accept(str(index),"Probe",1,"A voiced fixture exercises the real speech mouth.",1,model,audio)
			_campus_materials(model)
			if CASES[index].get("stopped",false):speech.cancel(str(index))
	for frame in 10:
		for index in models.size():
			var state: Dictionary=CASES[index]
			Motion.express(models[index],state.mood,.5,"",0.,Vector3.INF,state.get("affect",{}),{"expressiveness":.85})
		await process_frame
	await RenderingServer.frame_post_draw
	var capture:=root.get_texture().get_image()
	if capture==null or capture.is_empty():printerr("FACIAL_RENDER empty image");quit(3);return
	var args:=OS.get_cmdline_user_args()
	var output:=str(args[0]) if not args.is_empty() else "user://character_faces.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var error:=capture.save_png(output)
	print("FACIAL_RENDER %s display=%s adapter=%s size=%s cases=%d output=%s"%["PASS" if error==OK else "FAIL",DisplayServer.get_name(),RenderingServer.get_video_adapter_name(),capture.get_size(),CASES.size(),output])
	speech.clear_session()
	quit(0 if error==OK else 4)

func _panel(index: int,state: Dictionary) -> void:
	var origin:=Vector2(16+(index%4)*316,88+(index/4)*320)
	var panel:=ColorRect.new();panel.position=origin;panel.size=Vector2(300,304);panel.color=Color("203449");root.add_child(panel)
	_label(str(state.title),origin+Vector2(12,10),18)
	var container:=SubViewportContainer.new();container.position=origin+Vector2(2,42);container.size=Vector2(296,260);container.stretch=true;root.add_child(container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(296,260);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("203449")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e0e9f7");environment.environment.ambient_light_energy=.5;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-28,-20,0);light.light_energy=.65;world.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-10,155,0);fill.light_energy=.2;world.add_child(fill)
	var appearance:=Toon.defaults();appearance.hair="Crop";appearance.expression=state.get("expression","Smile");appearance.glasses=state.get("glasses","None")
	var model:=Toon.build(appearance);world.add_child(model);models.append(model)
	_campus_materials(model)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.58;camera.position=Vector3(0,1.56,3.8);world.add_child(camera);camera.look_at(Vector3(0,1.54,0));camera.current=true

func _campus_materials(model: Node3D) -> void:
	# Match the real campus graphics policy, including the filter that exposed
	# UV-less procedural surfaces as black in the compatibility renderer.
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _label(text: String,at: Vector2,size: int) -> void:
	var label:=Label.new();label.text=text;label.position=at;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",Color("ecf4ff"));root.add_child(label)

func _audio() -> AudioStreamWAV:
	var result:=AudioStreamWAV.new();result.mix_rate=16000;result.format=AudioStreamWAV.FORMAT_16_BITS
	var bytes:=PackedByteArray();bytes.resize(16000*30*2)
	for i in 16000*30:bytes.encode_s16(i*2,roundi(sin(float(i)*TAU*180./16000.)*10000.))
	result.data=bytes
	return result
