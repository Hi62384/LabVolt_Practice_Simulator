extends SceneTree
## Actual Main-scene faculty models, viewed by a diagnostic camera. The fixture
## selects emotion/blink/audio inputs; production geometry and compositors run.
## No live AI, live synthesized voice, or gameplay-emotion decision is claimed.
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const CASES:=[
	{"name":"neutral","mood":"steady","affect":{}},
	{"name":"happy","mood":"happy","affect":{"happiness":.95}},
	{"name":"angry","mood":"angry","affect":{"anger":.95}},
	{"name":"sad","mood":"sad","affect":{"sadness":.95}},
	{"name":"tired","mood":"tired","affect":{"tiredness":.95}},
	{"name":"excited","mood":"excited","affect":{"happiness":.7,"excitement":.95}},
	{"name":"blinking_angry","mood":"angry","affect":{"anger":.95},"blink":true},
	{"name":"speaking_sad","mood":"sad","affect":{"sadness":.95},"speech":true},
	{"name":"after_speech_angry","mood":"angry","affect":{"anger":.95},"stop_speech":true},
]

func _initialize()->void:call_deferred("run")

func run()->void:
	if DisplayServer.get_name()=="headless":printerr("IN_GAME_FACES requires a native renderer");quit(2);return
	create_timer(150.).timeout.connect(func():printerr("IN_GAME_FACES timeout");quit(3))
	root.size=Vector2i(640,480)
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	game.host_openai.enabled=false
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false);game.school_world.set_process(false);game.player.set_physics_process(false)
	for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.84;camera.near=.02
	root.add_child(camera);camera.current=true
	var overlay:=CanvasLayer.new();overlay.layer=120;root.add_child(overlay)
	var title:=Label.new();title.position=Vector2(16,12);title.add_theme_font_size_override("font_size",22)
	title.add_theme_constant_override("outline_size",6);title.add_theme_color_override("font_outline_color",Color.BLACK);overlay.add_child(title)
	var output:=OS.get_environment("LABVOLT_STARTUP_CAPTURE")
	assert(not output.is_empty())
	var evidence: Array[Dictionary]=[]
	var audio_serial:=0
	for id: String in ["mr_bro","dr_volts"]:
		game.faculty.current.ac_lab=id
		game.faculty._sync_lab_teachers()
		var model: Node3D=game.faculty._model_for_room("ac_lab",id)
		assert(is_instance_valid(model) and model.get_meta("faculty_id","")==id)
		var head:=model.get_node("Body/Head") as Node3D
		var direction:=model.global_basis.z.normalized()
		game.player.global_position=model.global_position+direction*1.3
		var person:=Profiles.teacher(id)
		var animation:=model.get_node("AnimationPlayer") as AnimationPlayer
		for state: Dictionary in CASES:
			animation.play("Idle");animation.seek(2.78 if state.get("blink",false) else .4,true);animation.pause()
			if state.get("blink",false):
				assert(head.get_node("EyeL/Blink").scale.y<.07 and head.get_node("EyeR/Blink").scale.y<.07)
			if state.get("speech",false):
				game.faculty.speech_player.configure(true,false)
				audio_serial+=1
				assert(game.faculty.speech_player.accept("face_probe",person.name,audio_serial,"A fixture audio signal exercises the actual mouth compositor.",1,model,_audio()))
			if state.get("stop_speech",false):game.faculty.speech_player.cancel("face_probe")
			for frame in 2:
				Motion.express(model,state.mood,.5,"",0.,Vector3.INF,state.affect,person.traits)
				camera.global_position=head.global_position+direction*1.1+Vector3.UP*.015
				camera.look_at(head.global_position+Vector3.UP*.015)
				await process_frame
			title.text=person.name+" · "+str(state.name).replace("_"," ")
			await process_frame
			if state.get("blink",false):
				assert(head.get_node("EyeL/Blink").scale.y<.07 and head.get_node("EyeR/Blink").scale.y<.07)
			for layer in root.find_children("*","CanvasLayer",true,false):
				if layer!=overlay:layer.hide()
			await RenderingServer.frame_post_draw
			var capture:=root.get_texture().get_image()
			assert(capture!=null and not capture.is_empty())
			var filename:=id+"-"+str(state.name)+".png"
			assert(capture.save_png(output.path_join(filename))==OK)
			evidence.append({"character":id,"state":state.name,"file":filename,"actual_main_model":true,"model_path":str(model.get_path()),"faculty_id":str(model.get_meta("faculty_id",""))})
		game.faculty.speech_player.cancel("face_probe")
	var file:=FileAccess.open(output.path_join("in-game-faces.json"),FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"source":"Main.tscn actual faculty models; diagnostic camera and emotion/blink/fixture-audio inputs; no live AI or synthesized voice","captures":evidence},"  "));file.close()
	game.queue_free();await process_frame
	print("IN_GAME_FACES PASS")
	quit(0)

func _audio()->AudioStreamWAV:
	var stream:=AudioStreamWAV.new();stream.mix_rate=16000;stream.format=AudioStreamWAV.FORMAT_16_BITS
	var bytes:=PackedByteArray();bytes.resize(16000*20*2)
	for index in 16000*20:bytes.encode_s16(index*2,roundi(sin(float(index)*TAU*180./16000.)*10000.))
	stream.data=bytes
	return stream
