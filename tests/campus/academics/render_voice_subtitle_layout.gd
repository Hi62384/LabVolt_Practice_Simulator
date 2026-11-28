extends SceneTree
## Native framebuffer QA using the real Main HUD and speech player. PCM is
## synthetic and the runner uses Dummy audio; no audible hardware claim.
var failures: Array[String]=[]
var observations: Array=[]
var output:=""

func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)

func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	output=OS.get_environment("LABVOLT_SUBTITLE_CAPTURE")
	if output.is_empty():quit(2);return
	create_timer(75.).timeout.connect(func():push_error("subtitle render timeout");quit(3))
	root.size=Vector2i(1280,720)
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	game.host_openai.enabled=false
	game.set_process(false);game.set_physics_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	var speech: Node=game.faculty.speech_player
	speech.set_process(false);speech.configure(true,true)
	var actor: Node3D=game.school_world.teacher
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	camera.global_position=actor.global_position+Vector3(2.8,1.6,2.8)
	camera.look_at(actor.global_position+Vector3.UP*1.)
	game.hotbar.show();game.health.overlay.show();game.held_hint.show();game.held_hint.text="E: Talk to Mr Bro"
	game.ui.prompt.show();game.ui.prompt.text="E: Talk to Mr Bro"
	var other:=Node3D.new();root.add_child(other);other.global_position=actor.global_position+Vector3(1.5,0,0)
	var first:="The first thought can play while the next part is being prepared. This caption follows only the part you are currently hearing."
	var second:="Now the second thought continues with the same character voice. Subtitles advance with the audio, while the interaction prompt stays visible."
	var clip:=AudioStreamWAV.new();clip.format=AudioStreamWAV.FORMAT_16_BITS;clip.mix_rate=16000
	var bytes:=PackedByteArray();bytes.resize(16000*2*60);bytes.fill(12);clip.data=bytes
	var serial:=0
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		serial+=1
		speech.cancel("render-caption");speech.cancel("render-other")
		check(speech.accept("render-caption","Mr Bro",serial,first+" "+second,3,actor,null,1.,{"expect_audio":true,"character_id":"mr_bro"}),"Main caption accepted")
		check(speech.deliver_segment("render-caption",serial,clip,0,2,first),"First segment delivered")
		check(speech.deliver_segment("render-caption",serial,clip,1,2,second),"Second segment prefetched")
		check(speech.accept("render-other","Nearby student",serial,"I will wait until you finish talking.",1,other,null,1.,{"expect_audio":false,"character_id":"student"}),"Second caption accepted")
		await capture(game,speech,"subtitles-"+str(size.x)+"-first",first)
		speech._finished("render-caption",serial)
		await capture(game,speech,"subtitles-"+str(size.x)+"-second",second)
	speech.clear_session()
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"audio_driver":"Dummy selected by runner","live_api":false,"physical_audio":false,"failures":failures,"observations":observations},"  "));file.close()
	game.queue_free();camera.queue_free();other.queue_free();await process_frame;await create_timer(.15).timeout
	print("VOICE_SUBTITLE_RENDER ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func capture(game: Node,speech: Node,name: String,expected: String) -> void:
	for frame in 5:await process_frame
	speech._layout_subtitles()
	for frame in 2:await process_frame
	var caption: Label=speech.subtitles["render-caption"].label
	check(caption.visible and caption.text=="Mr Bro: "+expected,"Visible caption matches the current audio segment")
	check(caption.get_viewport_rect().encloses(caption.get_global_rect()),"Caption fits viewport "+name)
	check(game.held_hint.is_visible_in_tree() and game.ui.prompt.is_visible_in_tree(),"Actual interaction prompts remain visible during caption playback")
	for obstacle: Control in [game.hotbar.bar,game.health.bar,game.held_hint,game.ui.prompt]:
		if obstacle.is_visible_in_tree():check(not caption.get_global_rect().intersects(obstacle.get_global_rect()),"Caption clears HUD "+name)
	var second: Label=speech.subtitles["render-other"].label
	check(not second.visible,"Only the audible winning speaker is captioned")
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image!=null and not image.is_empty() and image.save_png(output.path_join(name+".png"))==OK,"Saved actual native framebuffer "+name)
	check(image.get_size()==root.size,"Native framebuffer has requested physical dimensions "+name)
	observations.append({"name":name,"window":str(root.size),"framebuffer":str(image.get_size()),"logical_viewport":str(caption.get_viewport_rect()),"canvas_stretch":ProjectSettings.get_setting("display/window/stretch/mode"),"caption":str(caption.get_global_rect()),"held_prompt":str(game.held_hint.get_global_rect()),"central_prompt":str(game.ui.prompt.get_global_rect()),"prompts_visible":game.held_hint.is_visible_in_tree() and game.ui.prompt.is_visible_in_tree(),"secondary_visible":second.visible,"text":caption.text})
