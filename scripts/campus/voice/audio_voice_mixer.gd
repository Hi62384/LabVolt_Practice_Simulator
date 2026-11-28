extends RefCounted
## Shared routing and a single distance attenuation stage for every voice source.
const NPC_BUS:="NPCSpeech"
const HUMAN_BUS:="HumanVoice"
const PHONE_BUS:="PhoneCalls"
const DSP_PATH:="res://scripts/campus/computers/VoiceAudioDsp.cs"
static var _dsp: RefCounted

static func ensure_buses() -> void:
	for bus_name in [NPC_BUS,HUMAN_BUS,PHONE_BUS]:
		if AudioServer.get_bus_index(bus_name)>=0:continue
		AudioServer.add_bus()
		var index:=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus_name);AudioServer.set_bus_send(index,"Master")
		var compressor:=AudioEffectCompressor.new()
		compressor.threshold=-12.;compressor.ratio=2.;compressor.gain=0.
		compressor.attack_us=5000.;compressor.release_ms=120.;compressor.mix=.65
		AudioServer.add_bus_effect(index,compressor)
		var limiter:=AudioEffectLimiter.new()
		limiter.ceiling_db=-1.;limiter.threshold_db=-1.;limiter.soft_clip_db=0.
		AudioServer.add_bus_effect(index,limiter)

static func normalise(stream: AudioStreamWAV,delivery: Dictionary={}) -> AudioStreamWAV:
	if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS:return stream
	if bool(stream.get_meta("voice_normalized",false)):return stream
	var projection:=str(delivery.get("projection","normal"))
	stream.set_meta("voice_projection",projection)
	stream.set_meta("voice_intensity",clampf(float(delivery.get("intensity",.5)),0.,1.))
	var dsp:=processor()
	if dsp==null:
		# Exported gameplay uses .NET. Native-only inspection still uses mixer
		# compression and limiting; never claim integrated loudness measurement.
		stream.set_meta("voice_normalization_status","native DSP unavailable")
		return stream
	var mood:=str(delivery.get("mood",""))
	var result: Dictionary
	if not mood.is_empty() and dsp.has_method("NormalizeExpressivePcm16"):
		result=dsp.call("NormalizeExpressivePcm16",stream.data,stream.mix_rate,stream.stereo,projection,mood,float(stream.get_meta("voice_intensity",.5)))
	else:result=dsp.call("NormalizePcm16",stream.data,stream.mix_rate,stream.stereo,projection)
	if not bool(result.get("ok",false)):
		stream.set_meta("voice_normalization_status",str(result.get("error","invalid audio")))
		return stream
	var adjusted:=stream.duplicate() as AudioStreamWAV
	adjusted.data=result.data
	adjusted.set_meta("voice_normalized",true)
	adjusted.set_meta("voice_normalization_status","speech-gated RMS with peak headroom")
	adjusted.set_meta("voice_source_rms_db",result.rms_db)
	adjusted.set_meta("voice_source_peak_db",result.peak_db)
	adjusted.set_meta("voice_gain_db",result.gain_db)
	adjusted.set_meta("voice_projection",projection)
	adjusted.set_meta("voice_intensity",stream.get_meta("voice_intensity",.5))
	return adjusted

static func processor() -> RefCounted:
	if is_instance_valid(_dsp):return _dsp
	if not ClassDB.class_exists("CSharpScript"):return null
	var script: Script=load(DSP_PATH)
	if script!=null and script.can_instantiate():_dsp=script.new()
	return _dsp

static func configure_spatial(player: AudioStreamPlayer3D,delivery: Dictionary={}) -> void:
	var projection:=str(delivery.get("projection",player.stream.get_meta("voice_projection","normal") if player.stream else "normal"))
	player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.max_db=0.;player.emission_angle_enabled=false
	match projection:
		"whisper":player.unit_size=1.3;player.max_distance=5.
		"quiet":player.unit_size=2.5;player.max_distance=10.
		"lecture":player.unit_size=10.;player.max_distance=36.
		"shout":player.unit_size=8.;player.max_distance=40.
		_:player.unit_size=4.;player.max_distance=18.

static func is_occluded(source: Vector3,anchor: Node3D,listener: Camera3D) -> bool:
	if not is_instance_valid(anchor) or not is_instance_valid(listener) or not anchor.is_inside_tree():return true
	if source.distance_squared_to(listener.global_position)<.25:return false
	var space:=anchor.get_world_3d().direct_space_state
	if space==null:return false
	var query:=PhysicsRayQueryParameters3D.create(source,listener.global_position,1)
	var excluded: Array[RID]=[]
	for origin in [anchor,listener]:
		var node: Node=origin
		while node!=null:
			if node is CollisionObject3D:excluded.append(node.get_rid())
			node=node.get_parent()
	for collider in anchor.find_children("*","CollisionObject3D",true,false):excluded.append(collider.get_rid())
	query.exclude=excluded
	return not space.intersect_ray(query).is_empty()

static func update_occlusion(player: AudioStreamPlayer3D,anchor: Node3D,listener: Camera3D,base_db: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(anchor) or not is_instance_valid(listener):return
	var obstructed:=is_occluded(player.global_position,anchor,listener)
	# This is wall occlusion only. Distance is handled once by Player3D.
	player.volume_db=base_db+(-12. if obstructed else 0.)
	player.attenuation_filter_cutoff_hz=1400. if obstructed else 7000.


# Estimated listener gain using the configured inverse-distance source and bus
# routing. Do not apply this gain to playback: Godot already does that.
static func distance_db(distance: float,unit_size: float,max_distance: float,max_db: float) -> float:
	if max_distance>0. and distance>=max_distance:return -INF
	var gain:=minf(max_db,linear_to_db(maxf(.001,unit_size)/maxf(.001,distance)))
	if max_distance>0.:gain+=linear_to_db(maxf(.00001,1.-distance/max_distance))
	return gain

static func bus_gain_db(bus_name: String) -> float:
	var gain:=0.
	var seen: Dictionary={}
	var index:=AudioServer.get_bus_index(bus_name)
	while index>=0 and not seen.has(index):
		seen[index]=true
		if AudioServer.is_bus_mute(index):return -INF
		gain+=AudioServer.get_bus_volume_db(index)
		if index==0:break
		index=AudioServer.get_bus_index(AudioServer.get_bus_send(index))
	return gain

static func perceived_db(player: AudioStreamPlayer3D,listener: Camera3D,level: float) -> float:
	if not is_instance_valid(player) or not is_instance_valid(listener) or not player.playing or player.stream_paused:return -INF
	if level<=.00001:return -INF
	var distance:=player.global_position.distance_to(listener.global_position)
	return linear_to_db(level)+player.volume_db+distance_db(distance,player.unit_size,player.max_distance,player.max_db)+bus_gain_db(player.bus)
