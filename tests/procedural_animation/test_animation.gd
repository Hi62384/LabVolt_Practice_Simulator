extends SceneTree
const Document=preload("res://scripts/procedural_animation/document.gd")
const Playback=preload("res://scripts/procedural_animation/playback.gd")
const Store=preload("res://scripts/procedural_animation/storage.gd")
const Visuals=preload("res://scripts/campus/academics/classroom_visuals.gd")
const Board=preload("res://scripts/campus/academics/teaching_board.gd")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	create_timer(24.).timeout.connect(func():quit(1))
	var motion:={"version":1,"title":"Phase follows the angle","subtitle":"One full turn produces one complete cycle","duration":12.,"loop":true,
		"parameters":{"frequency":[1.,.2,3.]},"objects":[
			{"type":"group","id":"dial","x":230,"y":270},
			{"type":"circle","id":"unit_circle","parent":"dial","radius":112,"color":"82c8dc"},
			{"type":"arrow","id":"angle","parent":"dial","width":108,"height":0,"color":"ffc671","bindings":{"rotation":"t * 90 * frequency"}},
			{"type":"circle","id":"marker","parent":"dial","radius":9,"fill":"46dfc1","color":"46dfc1","bindings":{"x":"112 * cos(t * pi / 2 * frequency)","y":"112 * sin(t * pi / 2 * frequency)"}},
			{"type":"graph","id":"wave","x":430,"y":145,"width":470,"height":280,"function":"sin(u * frequency)","color":"46dfc1","tracks":{"progress":[[0,0],[4,1]]}},
			{"type":"equation","id":"formula","x":92,"y":460,"width":400,"text":"y = sin(f · θ)","color":"e2edf4","font":36},
			{"type":"text","id":"frequency_label","x":450,"y":460,"width":420,"text":"Frequency factor  {frequency}","font":30},
		]}
	var validated:=Document.parse(JSON.stringify(motion))
	assert(validated.ok,str(validated.get("error","")))
	var player:=Playback.new()
	assert(player.load_scene(motion))
	player.advance(1.)
	assert(is_equal_approx(player.property(player.objects.angle,"rotation"),90.))
	assert(absf(player.property(player.objects.marker,"x"))<.001)
	assert(is_equal_approx(player.sample("wave",PI/2.),1.))
	var before:=player.snapshot()
	assert(not player.command({"op":"parameter","id":"frequency","value":1000.}))
	assert(player.snapshot()==before)
	assert(player.command({"op":"parameter","id":"frequency","value":2.}))
	assert(is_equal_approx(player.property(player.objects.angle,"rotation"),180.))
	assert(player.command({"op":"pause"}))
	player.advance(8.)
	assert(is_equal_approx(player.clock,1.))
	assert(player.command({"op":"seek","value":4.}))
	assert(player.command({"op":"highlight","id":"wave"}))
	assert(Store.save("motion_fixture",player)==OK)
	var saved:=Store.load_playback("motion_fixture")
	assert(saved!=null and saved.highlight=="wave" and is_equal_approx(saved.clock,4.) and not saved.playing)
	assert(player.command({"op":"restore"}))
	assert(is_equal_approx(float(player.scene.parameters.frequency[0]),1.))
	var corrupt:=motion.duplicate(true)
	corrupt.objects[0].parent="dial"
	assert(not player.load_scene(corrupt))
	corrupt=motion.duplicate(true)
	corrupt.objects[4].function="OS.execute(1)"
	assert(not player.load_scene(corrupt))
	assert(Visuals.decode(JSON.stringify({"speech":"The marker traces the circle.","action":{"op":"create","scene":motion}})).size()>0)
	for function in ["1-exp(-u)","cos(u)","u*u/12","3*u-0.4*u*u","sqrt(absf(u))"]:
		var example:=motion.duplicate(true)
		example.objects[4].function=function
		assert(player.load_scene(example))
		assert(is_finite(player.sample("wave",1.)))
	_distinct_scenes(player)
	var activity:={"phase":"lesson"}
	assert(Visuals.apply(activity,{"op":"create","scene":motion},1.))
	Visuals.advance(activity,5.)
	Visuals.advance(activity,8.,true)
	assert(is_equal_approx(float(Visuals.view(activity).time),4.))
	var board:=Board.new()
	root.add_child(board)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,0,4.8)
	camera.current=true
	board.set_room_active(true)
	board.show_content("ELM253","lesson","Visual explanation",{"title":"Angles and phase","text":"The angle and graph update from the same mathematical parameter."},"Class display")
	board.show_animation("motion",Visuals.view(activity,true))
	assert(board.animation_canvas.visible)
	for i in 4:await process_frame
	if OS.get_environment("LABVOLT_CAPTURE_VISUALS")=="1" and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image:=board.viewport.get_texture().get_image()
		assert(image.get_width()==1600)
		image.save_png("res://.godot/procedural-animation-board.png")
	var scope:={"version":1,"title":"Live oscilloscope","subtitle":"Time (ms) · Voltage (V)","duration":12.,
		"objects":[{"id":"trace","type":"graph","x":50,"y":100,"width":850,"height":345,
			"x_min":0.,"x_max":8.,"y_min":-1.,"y_max":6.,"data_series":"bench_scope_trace"}]}
	assert(Visuals.apply(activity,{"op":"create","scene":scope},10.))
	var captured:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1.1,5),Vector2(3.9,5),
		Vector2(4,0),Vector2(6,0),Vector2(6.1,5),Vector2(8,5)])
	Visuals.update_bench(activity,{"station":2,"series":{"bench_scope_trace":captured}})
	board.show_animation("scope",Visuals.view(activity,true))
	assert(board.animation_canvas.player.live_series.bench_scope_trace==captured)
	if OS.get_environment("LABVOLT_CAPTURE_VISUALS")=="1" and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		board.viewport.get_texture().get_image().save_png("res://.godot/procedural-live-scope-board.png")
	Visuals.update_bench(activity,{})
	board.show_animation("scope",Visuals.view(activity,true,false))
	assert(board.animation_canvas.player.live_series.is_empty())
	var orbit:={"version":1,"title":"Parametric paths and observations","duration":8.,"objects":[
		{"type":"graph","id":"orbit","x":35,"y":100,"width":425,"height":365,
			"x_min":-1.2,"x_max":1.2,"y_min":-1.2,"y_max":1.2,
			"x_label":"Horizontal offset","y_label":"Vertical offset","x_function":"cos(u)","function":"sin(u)"},
		{"type":"graph","id":"observed","x":500,"y":100,"width":425,"height":365,
			"x_min":-1.2,"x_max":1.2,"y_min":-1.2,"y_max":1.2,
			"x_label":"Horizontal offset","y_label":"Vertical offset","plot_style":"scatter","equal_axes":true,"color":"ffc671",
			"points":[[-1.,0.],[-.6,.8],[0.,1.],[.6,.8],[1.,0.]]}]}
	assert(player.load_scene(orbit))
	assert(player.sample_point("orbit",PI/2.).distance_to(Vector2(0.,1.))<.001)
	assert(player.sample_point("orbit",PI).distance_to(Vector2(-1.,0.))<.001)
	var diagram_plan:=Visuals.decode(JSON.stringify({"speech":"Compare the curve and points.","action":{"op":"create","scene":orbit}}))
	assert("Vertical offset" in diagram_plan.moderation)
	assert(Visuals.apply(activity,{"op":"create","scene":orbit},11.))
	board.show_animation("orbit",Visuals.view(activity,true))
	if OS.get_environment("LABVOLT_CAPTURE_VISUALS")=="1" and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		board.viewport.get_texture().get_image().save_png("res://.godot/procedural-plot-board.png")
	var ambiguous:=orbit.duplicate(true)
	ambiguous.objects[1].function="u"
	assert(not Document.compile(ambiguous).ok)
	var camera_scene:={"version":1,"title":"Camera and timed reveal","subtitle":"The title stays fixed during the zoom",
		"duration":8.,"objects":[
			{"id":"cam","type":"camera","easing":"linear","tracks":{"x":[[0.,480.],[4.,640.]],"scale":[[0.,1.],[4.,2.]]}},
			{"id":"overflow","type":"rectangle","x":-40.,"y":-40.,"width":1120.,"height":700.,"fill":"17445b","color":"17445b"},
			{"id":"target","type":"circle","layer":1,"x":640.,"y":278.,"radius":60.,"fill":"46dfc1"},
			{"id":"callout","type":"text","layer":2,"x":544.,"y":365.,"width":300.,"text":"Check this region","start":3.,"end":5.}]}
	assert(player.load_scene(camera_scene))
	assert(player.camera_transform().is_equal_approx(Transform2D.IDENTITY))
	assert(not player.visible_at_time(player.objects.callout))
	player.seek(4.)
	assert(player.camera_transform() * Vector2(640.,278.)==Vector2(480.,278.))
	assert(is_equal_approx(player.camera_transform().get_scale().x,2.))
	assert(player.visible_at_time(player.objects.callout))
	assert(Visuals.apply(activity,{"op":"create","scene":camera_scene},12.))
	assert(Visuals.apply(activity,{"op":"pause"},12.))
	assert(Visuals.apply(activity,{"op":"seek","value":4.},12.))
	board.show_animation("camera",Visuals.view(activity,true))
	if OS.get_environment("LABVOLT_CAPTURE_VISUALS")=="1" and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		board.viewport.get_texture().get_image().save_png("res://.godot/procedural-camera-board.png")
	player.seek(5.)
	assert(not player.visible_at_time(player.objects.callout))
	var duplicate_camera:=camera_scene.duplicate(true)
	duplicate_camera.objects.append({"id":"second_camera","type":"camera"})
	assert(not Document.compile(duplicate_camera).ok)
	print("PROCEDURAL_ANIMATION_ENGINE_AND_BOARD PASS")
	board.queue_free()
	camera.queue_free()
	await process_frame
	quit()

func _distinct_scenes(player: RefCounted) -> void:
	var fixtures:={
		"Charging and discharging":[
			{"id":"left","type":"rectangle","x":70,"y":170,"width":23,"height":240,"fill":"82c8dc"},
			{"id":"right","type":"rectangle","x":280,"y":170,"width":23,"height":240,"fill":"82c8dc"},
			{"id":"charge","type":"particles","x":100,"y":180,"width":165,"height":215,"radius":4,"count":18,"color":"46dfc1","bindings":{"alpha":"0.4 + 0.5 * sin(t)"}},
			{"id":"charging","type":"graph","x":400,"y":130,"width":510,"height":310,"function":"1-exp(-u)","x_min":0,"x_max":5},
			{"id":"discharging","type":"graph","x":400,"y":130,"width":510,"height":310,"function":"exp(-u)","x_min":0,"x_max":5,"alpha":0.8}],
		"Transformer flux":[
			{"id":"core","type":"rectangle","x":200,"y":145,"width":570,"height":310,"stroke":16,"color":"b4adff"},
			{"id":"flux","type":"ellipse","x":485,"y":300,"width":460,"height":210,"dash":true,"color":"82c8dc","bindings":{"alpha":"absf(sin(t))"}},
			{"id":"input","type":"path","x":165,"y":195,"points":[[0,0],[70,35],[0,65],[70,100],[0,135],[70,170]],"color":"ffc671","tracks":{"progress":[[0,0],[3,1]]}}],
		"Area strips":[
			{"id":"curve","type":"graph","x":65,"y":120,"width":800,"height":340,"function":"u*u","x_min":0,"x_max":4,"y_min":0,"y_max":16},
			{"id":"strip","type":"rectangle","x":480,"width":65,"layer":2,"fill":"46dfc1","bindings":{"y":"430 - sin(t) * 80","height":"sin(t) * 80"}}],
		"Projectile path":[
			{"id":"floor","type":"line","x":130,"y":430,"width":660,"height":0},
			{"id":"marker","type":"circle","radius":14,"fill":"ff8184","bindings":{"x":"130 + 60 * t","y":"430 - 90 * t + 10 * t * t"}}],
		"Vector rotation":[
			{"id":"basis","type":"group","x":430,"y":275,"bindings":{"rotation":"t * 40"}},
			{"id":"first","type":"arrow","parent":"basis","width":195,"height":0,"color":"46dfc1"},
			{"id":"second","type":"arrow","parent":"basis","width":0,"height":-130,"color":"ffc671"}],
		"Swapping two bars":[
			{"id":"short","type":"rectangle","x":225,"y":285,"width":110,"height":128,"fill":"46dfc1","tracks":{"x":[[0,225],[2,495]]}},
			{"id":"tall","type":"rectangle","x":495,"y":130,"width":110,"height":283,"fill":"ffc671","tracks":{"x":[[0,495],[2,225]]}}],
		"Water cycle":[
			{"id":"ocean","type":"polygon","fill":"137aa0","points":[[80,365],[870,365],[870,465],[80,465]]},
			{"id":"cloud","type":"ellipse","x":490,"y":165,"width":370,"height":107,"fill":"e2edf4","color":"82c8dc"},
			{"id":"rain","type":"particles","x":345,"y":240,"width":260,"height":100,"count":20,"color":"82c8dc","radius":3,"tracks":{"alpha":[[0,0],[2,1]]}}],
	}
	for title in fixtures:
		assert(player.load_scene({"version":1,"title":title,"duration":8.,"objects":fixtures[title]}))
		player.advance(2.)
		var restored:=Playback.new()
		assert(restored.restore_checkpoint(player.snapshot()))
		assert(restored.scene.title==title and is_equal_approx(restored.clock,2.))
