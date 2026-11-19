extends SceneTree

const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
const PORT:=26375
const HOST_POSITION:=Vector3(13,0,4)
const NEAR_POSITION:=Vector3(13,0,7)
const FAR_POSITION:=Vector3(13,0,25)
const OUT_POSITION:=Vector3(13,0,33)
var game: Node
var packet := PackedByteArray()
var deadline: int

func _initialize() -> void: call_deferred("run")

func wait_for(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("Voice fixture timed out: "+label)
	quit(1)
	return false

func pose(position: Vector3) -> void:
	game.player.global_position=position
	game.session.send_pose({"position":position})

func run() -> void:
	var host: bool=OS.get_cmdline_user_args()[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	deadline=Time.get_ticks_msec()+95000
	packet.resize(int(Voice.SAMPLE_RATE*Voice.PACKET_SECONDS)*2)
	for i in packet.size()/2:packet.encode_s16(i*2,int(sin(TAU*440.0*i/Voice.SAMPLE_RATE)*4200))
	var voice: Node=game.voice_chat
	if not is_instance_valid(voice):
		push_error("Main did not initialize voice chat")
		quit(1)
		return
	if host:
		assert(game.session.host_game("Voice Host",PORT)==OK)
		pose(HOST_POSITION)
		print("VOICE_HOST_READY")
		if not await wait_for(func():return game.session.roster.size()==2,"guest connect"):return
		var peer: int=game.session.roster.keys().filter(func(id):return id!=1)[0]
		if not await wait_for(func():
			pose(HOST_POSITION)
			return voice.remotes.has(peer)
		,"client PCM received"):return
		if not await wait_for(func():
			pose(HOST_POSITION)
			voice._relay(1,packet,false)
			return voice._position(peer).distance_to(OUT_POSITION)<.6
		,"remote moves beyond hearing range"):return
		for i in 10:
			voice._relay(1,packet,false)
			await create_timer(.05).timeout
		print("LIVE_VOICE_HOST PASS")
		await create_timer(2.0).timeout
	else:
		assert(game.session.join_game("127.0.0.1","Voice Client",PORT)==OK)
		if not await wait_for(func():
			pose(NEAR_POSITION)
			if game.session.roster.size()!=2:return false
			voice._submit.rpc_id(1,packet,false)
			return voice.remotes.has(1)
		,"host PCM received"):return
		var speaker: AudioStreamPlayer3D=voice.remotes[1].player
		if not await wait_for(func():return speaker.volume_db>-5.0,"near playback"):return
		var close_volume:=speaker.volume_db
		if not await wait_for(func():
			pose(FAR_POSITION)
			return speaker.volume_db<close_volume-9.0 and speaker.volume_db>-45.0
		,"distance attenuation"):return
		if not await wait_for(func():
			pose(OUT_POSITION)
			var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
			var accepted: Vector3=own.get("position",Vector3.INF)
			return accepted.distance_to(OUT_POSITION)<.6
		,"host accepts out-of-range pose"):return
		await create_timer(.35).timeout
		var arrival: int=voice.remotes[1].last
		await create_timer(.7).timeout
		assert(voice.remotes[1].last==arrival and speaker.volume_db<=-60.0)
		print("LIVE_VOICE_CLIENT PASS")
		await create_timer(.5).timeout
	game.session.leave()
	game.queue_free()
	await process_frame
	quit()
