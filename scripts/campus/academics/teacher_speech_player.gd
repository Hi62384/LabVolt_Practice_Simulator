extends Node
## Ordered utterance playback. Generation, hearing and lecture progress are separate.
signal utterance_started(channel: String, serial: int)
signal playback_started(room: String, serial: int, at_ms: int)
signal utterance_finished(channel: String, serial: int, delivered: bool)
signal channel_paused(channel: String)
signal channel_resumed(channel: String)
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
const Face=preload("res://scripts/campus/academics/character_face.gd")
const Mixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
const MAX_QUEUED:=24
const MAX_TEXT:=Speech.MAX_TEXT
const MAX_CACHED:=32
const MAX_CACHE_BYTES:=64_000_000
const MAX_WAV_BYTES:=16_000_000
const WAIT_MS:=120000
const GAIN_META:="teacher_speech_gain"
var last_serial: Dictionary={}
var cancel_revisions: Dictionary={}
var cancelled_serials: Dictionary={}
var active: Dictionary={}
var queued: Dictionary={}
var awaiting: Dictionary={}
var suspended: Dictionary={}
var subtitles: Dictionary={}
var presentations: Dictionary={}
var cached: Dictionary={}
var cache_order: Array[String]=[]
var cache_bytes:=0
var subtitle_layer: CanvasLayer
var speech_enabled:=true
var subtitles_enabled:=true

func configure(speech: bool,captions: bool) -> void:
	var disabling:=speech_enabled and not speech
	speech_enabled=speech;subtitles_enabled=captions
	if disabling:
		for channel in active.keys():
			var item: Dictionary=active[channel].item
			item.resume_seconds=active[channel].player.get_playback_position()
			_stop(channel)
			if not bool(item.options.get("authoritative_audio",false)):item.stream=null
			item.expect_audio=false
			_start(channel,item)
		for channel in suspended:
			for snapshot in suspended[channel]:
				if not snapshot.active.is_empty():
					var paused_player: AudioStreamPlayer3D=snapshot.active.get("player")
					if is_instance_valid(paused_player):paused_player.stop();paused_player.queue_free()
					snapshot.active={}
				if not snapshot.presentation.is_empty():
					var item: Dictionary=snapshot.presentation.item
					if not bool(item.options.get("authoritative_audio",false)):item.stream=null
					else:snapshot.presentation.virtual_audio=item.stream!=null
					item.expect_audio=false
		for channel in awaiting.keys():
			var pending_items: Dictionary=awaiting[channel].items
			for serial in pending_items.keys():
				if not bool(pending_items[serial].options.get("authoritative_audio",false)):fail_stream(channel,int(serial),"disabled")
	if speech and not disabling:
		for channel in presentations.keys():
			var presentation: Dictionary=presentations[channel]
			var item: Dictionary=presentation.get("item",{})
			if bool(presentation.get("virtual_audio",false)) and not bool(item.get("options",{}).get("muted",false)):
				item.resume_seconds=maxf(0.,float(Time.get_ticks_msec()-int(presentation.started))*.001*float(item.pitch))
				_start(channel,item)
	if not captions:
		for channel in subtitles.keys():_clear_subtitle(channel)

func _ready() -> void:
	Mixer.ensure_buses()
	subtitle_layer=CanvasLayer.new();subtitle_layer.layer=32;add_child(subtitle_layer)

func _exit_tree() -> void:clear_session()

func cache_stream(key: String,stream: AudioStreamWAV) -> bool:
	if key.is_empty() or key.length()>128 or not valid_stream(stream):return false
	if cached.has(key):
		cache_bytes-=cached[key].data.size();cache_order.erase(key)
	cached[key]=stream;cache_order.append(key);cache_bytes+=stream.data.size()
	while cached.size()>MAX_CACHED or cache_bytes>MAX_CACHE_BYTES:
		var oldest: String=cache_order.pop_front()
		cache_bytes-=cached[oldest].data.size();cached.erase(oldest)
	return cached.has(key)

static func valid_stream(stream: AudioStreamWAV) -> bool:
	if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.mix_rate<8000 or stream.mix_rate>48000:return false
	var frame_bytes:=4 if stream.stereo else 2
	return stream.data.size()>0 and stream.data.size()<=MAX_WAV_BYTES and stream.data.size()%frame_bytes==0 and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED

func stream_for(key: String) -> AudioStreamWAV:
	if cached.has(key):cache_order.erase(key);cache_order.append(key)
	return cached.get(key)

func accept(channel: String,teacher: String,serial: int,text: String,priority: int,anchor: Node3D,stream: AudioStream=null,pitch:=1.0,options: Dictionary={}) -> bool:
	if channel.is_empty() or channel.length()>160 or teacher.is_empty() or serial<=int(last_serial.get(channel,0)) or serial<1 or serial>2147483647:return false
	if text.is_empty() or text.length()>MAX_TEXT or priority<0 or priority>4 or not is_instance_valid(anchor):return false
	if not is_finite(pitch) or pitch<.5 or pitch>2.:return false
	if stream!=null and not stream is AudioStreamWAV:return false
	if stream is AudioStreamWAV and not valid_stream(stream):return false
	if queued.get(channel,[]).size()>=MAX_QUEUED:return false
	last_serial[channel]=serial
	if not speech_enabled and not bool(options.get("authoritative_audio",false)):stream=null
	var item:={"teacher":teacher,"serial":serial,"text":text,"priority":priority,"anchor":anchor,"stream":stream,"pitch":pitch,
		"options":options.duplicate(true),"expect_audio":(speech_enabled or bool(options.get("authoritative_audio",false))) and bool(options.get("expect_audio",false)),"accepted":Time.get_ticks_msec()}
	if stream==null and (speech_enabled or bool(options.get("authoritative_audio",false))):
		if not awaiting.has(channel):awaiting[channel]={"items":{}}
		awaiting[channel].items[serial]=item
		awaiting[channel].item=item
		awaiting[channel].until=Time.get_ticks_msec()+WAIT_MS
	var current: Dictionary=presentations.get(channel,{})
	if not current.is_empty() and priority>int(current.get("priority",0)):
		pause_for_interruption(channel)
		if has_suspended(channel):suspended[channel].back().resume_requested=true
		_start(channel,item)
	elif active.has(channel) or presentations.has(channel):
		var pending: Array=queued.get(channel,[])
		pending.append(item);queued[channel]=pending
	else:_start(channel,item)
	return true

func has_pending(channel: String,serial: int) -> bool:
	return awaiting.get(channel,{}).get("items",{}).has(serial)

func has_utterance(channel: String,serial: int) -> bool:
	if int(presentations.get(channel,{}).get("serial",-1))==serial:return true
	if int(active.get(channel,{}).get("serial",-1))==serial:return true
	if has_pending(channel,serial):return true
	for item in queued.get(channel,[]):
		if int(item.serial)==serial:return true
	return _is_suspended(channel,serial)

func cancellation_revision(channel: String) -> int:return int(cancel_revisions.get(channel,0))

func was_cancelled(channel: String,serial: int) -> bool:return cancelled_serials.has(channel+"|"+str(serial))

func cancel_utterance(channel: String,serial: int) -> void:
	cancelled_serials[channel+"|"+str(serial)]=true
	while cancelled_serials.size()>512:cancelled_serials.erase(cancelled_serials.keys()[0])
	_erase_pending(channel,serial)
	var current:=int(presentations.get(channel,{}).get("serial",-1))==serial
	if int(active.get(channel,{}).get("serial",-1))==serial:_stop(channel);current=true
	if current:presentations.erase(channel);_clear_subtitle(channel)
	if queued.has(channel):
		queued[channel]=queued[channel].filter(func(item):return int(item.serial)!=serial)
		if queued[channel].is_empty():queued.erase(channel)
	for snapshot in suspended.get(channel,[]):
		if int(snapshot.presentation.get("serial",-1))==serial:
			_discard_snapshot(snapshot)
			snapshot.active={};snapshot.presentation={};snapshot.subtitle={}
		snapshot.queued=snapshot.queued.filter(func(item):return int(item.serial)!=serial)
	if current:_advance_queue(channel)

func cancel(channel: String) -> void:
	cancel_revisions[channel]=cancellation_revision(channel)+1
	_stop(channel)
	queued.erase(channel);awaiting.erase(channel);presentations.erase(channel)
	_clear_subtitle(channel)
	for snapshot in suspended.get(channel,[]):_discard_snapshot(snapshot)
	suspended.erase(channel)

func clear_session() -> void:
	var channels: Dictionary={}
	for source in [active,queued,awaiting,suspended,subtitles,presentations]:
		for channel in source.keys():channels[channel]=true
	for channel in channels:cancel(channel)
	last_serial.clear();cancel_revisions.clear();cancelled_serials.clear();cached.clear();cache_order.clear();cache_bytes=0

func pause_for_interruption(channel: String) -> bool:
	if not active.has(channel) and not presentations.has(channel):return false
	if suspended.get(channel,[]).size()>=4:return false
	var snapshot:={"active":active.get(channel,{}),"presentation":presentations.get(channel,{}),"queued":queued.get(channel,[]),
		"subtitle":subtitles.get(channel,{}),"paused_at":Time.get_ticks_msec(),"resume_requested":false}
	if bool(snapshot.presentation.get("virtual_audio",false)):
		snapshot.playback_position=maxf(0.,float(Time.get_ticks_msec()-int(snapshot.presentation.started))*.001*float(snapshot.presentation.item.pitch))
	if not snapshot.active.is_empty():
		var player: AudioStreamPlayer3D=snapshot.active.get("player")
		if is_instance_valid(player):
			snapshot.playback_position=player.get_playback_position()
			# stop() also cancels a play scheduled for the next physics frame.
			# stream_paused alone cannot pause that not-yet-started playback.
			player.stop()
		_rest_mouth(snapshot.active)
	if not snapshot.subtitle.is_empty() and is_instance_valid(snapshot.subtitle.get("label")):snapshot.subtitle.label.hide()
	var stack: Array=suspended.get(channel,[]);stack.append(snapshot);suspended[channel]=stack
	active.erase(channel);presentations.erase(channel);queued.erase(channel);subtitles.erase(channel)
	_layout_subtitles();channel_paused.emit(channel)
	return true

func pause_channel(channel: String) -> bool:return pause_for_interruption(channel)
func resume_channel(channel: String) -> bool:return resume_suspended(channel)
func has_suspended(channel: String) -> bool:return not suspended.get(channel,[]).is_empty()

func resume_suspended(channel: String) -> bool:
	if not has_suspended(channel):return false
	var snapshot: Dictionary=suspended[channel].back()
	snapshot.resume_requested=true
	if active.has(channel) or presentations.has(channel) or not queued.get(channel,[]).is_empty():return false
	suspended[channel].pop_back()
	if suspended[channel].is_empty():suspended.erase(channel)
	var elapsed:=Time.get_ticks_msec()-int(snapshot.paused_at)
	queued[channel]=snapshot.queued
	for item in snapshot.queued:item.accepted=int(item.accepted)+elapsed
	if not snapshot.presentation.is_empty():
		presentations[channel]=snapshot.presentation
		presentations[channel].item.accepted=int(presentations[channel].item.accepted)+elapsed
		presentations[channel].until=int(presentations[channel].until)+elapsed
		presentations[channel].started=int(presentations[channel].get("started",Time.get_ticks_msec()))+elapsed
	if not snapshot.active.is_empty():
		var player: AudioStreamPlayer3D=snapshot.active.get("player")
		if is_instance_valid(player):
			active[channel]=snapshot.active;player.stream_paused=false
			player.play(float(snapshot.get("playback_position",0.)))
			active[channel].mouth=_mouth(active[channel].item.anchor)
		else:presentations.erase(channel)
	if not snapshot.subtitle.is_empty() and is_instance_valid(snapshot.subtitle.get("label")):
		if subtitles_enabled:
			subtitles[channel]=snapshot.subtitle
			subtitles[channel].until=int(subtitles[channel].until)+elapsed
			subtitles[channel].started=int(subtitles[channel].started)+elapsed
			subtitles[channel].label.show()
		else:snapshot.subtitle.label.queue_free()
	if not active.has(channel) and presentations.has(channel):
		var item: Dictionary=presentations[channel].item
		if item.stream!=null:
			item.resume_seconds=float(snapshot.get("playback_position",0.))
			if not bool(presentations[channel].get("virtual_audio",false)) or (speech_enabled and not bool(item.options.get("muted",false))):_start(channel,item)
		elif not item.expect_audio and not subtitles.has(channel):_start(channel,item)
	_layout_subtitles();channel_resumed.emit(channel)
	if not active.has(channel) and not presentations.has(channel):_advance_queue(channel)
	return true

func _discard_snapshot(snapshot: Dictionary) -> void:
	var state: Dictionary=snapshot.get("active",{})
	var player: AudioStreamPlayer3D=state.get("player")
	if is_instance_valid(player):player.stop();player.queue_free()
	_rest_mouth(state)
	var label: Label=snapshot.get("subtitle",{}).get("label")
	if is_instance_valid(label):label.queue_free()

func _start(channel: String,item: Dictionary) -> void:
	var anchor: Node3D=item.anchor
	if not is_instance_valid(anchor):
		_erase_pending(channel,int(item.serial));_advance_queue.call_deferred(channel);return
	_clear_subtitle(channel)
	var now:=Time.get_ticks_msec()
	var duration:=maxi(2000,str(item.text).length()*65)
	var can_play: bool=speech_enabled and not bool(item.options.get("muted",false))
	var stream: AudioStreamWAV=item.stream if can_play else null
	var virtual_audio: bool=item.stream!=null and not can_play and bool(item.options.get("authoritative_audio",false))
	var waiting: bool=item.stream==null and bool(item.expect_audio) and (can_play or bool(item.options.get("authoritative_audio",false)))
	var caption: bool=subtitles_enabled and bool(item.options.get("show_subtitles",true))
	presentations[channel]={"serial":item.serial,"priority":item.priority,"until":now+(WAIT_MS if waiting else duration),"started":now,"item":item,"waiting":waiting,"virtual_audio":virtual_audio}
	if virtual_audio:
		var offset_ms:=int(float(item.get("resume_seconds",0.))*1000./float(item.pitch))
		duration=maxi(1,int(ceil(item.stream.get_length()*1000./float(item.pitch))))
		presentations[channel].started=now-offset_ms;presentations[channel].until=now+maxi(1,duration-offset_ms)
		if caption:
			_show_subtitle(channel,item,now-offset_ms,duration)
			subtitles[channel].until=presentations[channel].until
		_erase_pending(channel,int(item.serial))
		return
	if stream==null:
		if waiting:return
		if caption:_show_subtitle(channel,item,now,duration)
		else:presentations[channel].until=now
		return
	var identity:=str(item.options.get("character_id",item.teacher))
	for other in active:
		if other==channel:continue
		var other_item: Dictionary=active[other].item
		if str(other_item.options.get("character_id",other_item.teacher))!=identity:continue
		presentations[channel].blocked_speaker=true
		presentations[channel].until=now+WAIT_MS
		return
	var player:=AudioStreamPlayer3D.new();player.name="NpcSpeech"
	player.stream=stream;player.pitch_scale=item.pitch;player.bus=Mixer.NPC_BUS
	var delivery: Dictionary=item.options.get("delivery",{})
	Mixer.configure_spatial(player,delivery)
	var gain:=float(stream.get_meta(GAIN_META,1.))
	if not is_finite(gain):gain=1.
	player.volume_db=linear_to_db(clampf(gain,.0001,2.))
	anchor.add_child(player)
	var head:=anchor.find_child("Head",true,false) as Node3D
	if is_instance_valid(head):player.global_position=head.global_position
	var mouth:=_mouth(anchor)
	active[channel]={"serial":item.serial,"priority":item.priority,"teacher":item.teacher,"player":player,"mouth":mouth,"item":item,"base_db":player.volume_db,"occlusion_clock":0.0}
	duration=int(ceil(stream.get_length()*1000./float(item.pitch)))
	var offset_seconds:=clampf(float(item.get("resume_seconds",0.)),0.,maxf(0.,stream.get_length()-.001))
	presentations[channel].until=now+duration-int(offset_seconds*1000./float(item.pitch))+750
	presentations[channel].started=now-int(offset_seconds*1000./float(item.pitch))
	presentations[channel].waiting=false
	if caption:
		_show_subtitle(channel,item,now,maxi(1,duration))
		subtitles[channel].until=presentations[channel].until
	_erase_pending(channel,int(item.serial))
	player.finished.connect(func():_finished(channel,int(item.serial)))
	player.play(offset_seconds);utterance_started.emit(channel,int(item.serial))
	playback_started.emit(channel,int(item.serial),Time.get_ticks_msec())

func deliver_stream(channel: String,serial: int,stream: AudioStreamWAV) -> bool:
	if not valid_stream(stream) or not has_pending(channel,serial):return false
	var item: Dictionary=awaiting[channel].items[serial]
	if not speech_enabled and not bool(item.options.get("authoritative_audio",false)):return false
	if not is_instance_valid(item.anchor):_erase_pending(channel,serial);return false
	item.stream=stream;item.expect_audio=false
	_erase_pending(channel,serial)
	if int(presentations.get(channel,{}).get("serial",-1))==serial and not active.has(channel):_start(channel,item)
	return true

func fail_stream(channel: String,serial: int,_reason: String="unavailable") -> bool:
	if not has_pending(channel,serial):return false
	var item: Dictionary=awaiting[channel].items[serial]
	item.expect_audio=false
	_erase_pending(channel,serial)
	if int(presentations.get(channel,{}).get("serial",-1))==serial and not active.has(channel):_start(channel,item)
	return true

func _erase_pending(channel: String,serial: int) -> void:
	if not awaiting.has(channel):return
	awaiting[channel].items.erase(serial)
	if awaiting[channel].items.is_empty():awaiting.erase(channel)

func _mouth(anchor: Node3D) -> MeshInstance3D:
	return Face.begin_speech(Face.head_for(anchor))

func _process(delta: float) -> void:
	var now:=Time.get_ticks_msec()
	for channel in active.keys():
		var state: Dictionary=active[channel]
		var player: AudioStreamPlayer3D=state.get("player")
		if not is_instance_valid(player):_finished(channel,int(state.serial));continue
		var mouth=state.get("mouth")
		if is_instance_valid(mouth):
			var level:=_pcm_level(player.stream,player.get_playback_position())
			Face.speech_level(mouth,level,delta)
		state.occlusion_clock=float(state.occlusion_clock)+delta
		if state.occlusion_clock>=.2:
			state.occlusion_clock=0.
			Mixer.update_occlusion(player,state.item.anchor,get_viewport().get_camera_3d(),float(state.base_db))
	for channel in subtitles.keys():
		var subtitle: Dictionary=subtitles[channel]
		var pages: Array=subtitle.get("pages",[])
		var has_audio: bool=active.has(channel) and int(active[channel].serial)==int(subtitle.item.serial)
		var progress:=clampf(float(now-int(subtitle.started))/maxf(1.,float(subtitle.duration)),0.,.9999)
		if has_audio:
			var player: AudioStreamPlayer3D=active[channel].player
			progress=clampf(player.get_playback_position()/maxf(.1,player.stream.get_length()),0.,.9999)
		if pages.size()>1:
			var page_index:=_page_at(pages,progress)
			if page_index!=int(subtitle.get("page",0)):
				subtitle.page=page_index;subtitle.label.text=str(subtitle.item.teacher)+": "+str(pages[page_index])
		if not has_audio and now>=int(subtitle.until):_clear_subtitle(channel)
	for channel in presentations.keys():
		if not presentations.has(channel):continue
		if bool(presentations[channel].get("blocked_speaker",false)):
			var item: Dictionary=presentations[channel].item
			var identity:=str(item.options.get("character_id",item.teacher))
			var blocked:=false
			for state in active.values():
				if str(state.item.options.get("character_id",state.item.teacher))==identity:blocked=true;break
			if not blocked:_start(channel,item)
		if active.has(channel) or now<int(presentations[channel].until):continue
		var presentation: Dictionary=presentations[channel]
		if bool(presentation.get("waiting",false)):
			fail_stream(channel,int(presentation.serial),"timeout")
		else:
			_erase_pending(channel,int(presentation.serial))
			utterance_finished.emit(channel,int(presentation.serial),false)
			_advance_queue(channel)
	for channel in awaiting.keys():
		var pending_items: Dictionary=awaiting[channel].items
		for serial in pending_items.keys():
			var item: Dictionary=pending_items[serial]
			if now-int(item.accepted)>=WAIT_MS and not _is_suspended(channel,int(serial)):fail_stream(channel,int(serial),"timeout")

func _is_suspended(channel: String,serial: int) -> bool:
	for snapshot in suspended.get(channel,[]):
		if int(snapshot.presentation.get("serial",-1))==serial:return true
		for item in snapshot.queued:
			if int(item.serial)==serial:return true
	return false

static func _page_at(pages: Array,progress: float) -> int:
	var total:=0
	for page in pages:total+=str(page).length()
	var before:=0
	for index in pages.size():
		before+=str(pages[index]).length()
		if progress*total<float(before):return index
	return maxi(0,pages.size()-1)

static func _pcm_level(stream: AudioStreamWAV,seconds: float) -> float:
	if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS:return 0.
	var data: PackedByteArray=stream.data
	var channels:=2 if stream.stereo else 1
	var index:=int(maxf(0.,seconds)*stream.mix_rate)*channels*2
	if index<0 or index+1>=data.size():return 0.
	var peak:=0.
	for sample in 16:
		var at:=index+sample*channels*2
		if at+1>=data.size():break
		peak=maxf(peak,absf(float(data.decode_s16(at))/32768.))
	return peak

func _finished(channel: String,serial: int) -> void:
	if not active.has(channel) or int(active[channel].serial)!=serial:return
	_stop(channel);_clear_subtitle(channel)
	_erase_pending(channel,serial)
	utterance_finished.emit(channel,serial,true)
	_advance_queue(channel)

func _advance_queue(channel: String) -> void:
	presentations.erase(channel)
	_clear_subtitle(channel)
	var pending: Array=queued.get(channel,[])
	while not pending.is_empty():
		var next: Dictionary=pending.pop_front();queued[channel]=pending
		if not is_instance_valid(next.anchor):_erase_pending(channel,int(next.serial));continue
		_start(channel,next)
		if presentations.has(channel):break
	if pending.is_empty():queued.erase(channel)
	if not active.has(channel) and not presentations.has(channel) and has_suspended(channel) and bool(suspended[channel].back().resume_requested):resume_suspended(channel)

func _rest_mouth(state: Dictionary) -> void:
	var mouth=state.get("mouth")
	if is_instance_valid(mouth):Face.end_speech(mouth)

func _stop(channel: String) -> void:
	if not active.has(channel):return
	var state: Dictionary=active[channel]
	var player: AudioStreamPlayer3D=state.get("player")
	if is_instance_valid(player):player.stop();player.queue_free()
	_rest_mouth(state);active.erase(channel)

func _show_subtitle(channel: String,item: Dictionary,started: int,duration: int) -> void:
	if not is_instance_valid(subtitle_layer):return
	_clear_subtitle(channel)
	var pages:=Speech.pages(str(item.text))
	var label:=Label.new();label.text=str(item.teacher)+": "+str(pages[0] if not pages.is_empty() else item.text)
	label.add_theme_color_override("font_color",Color("f3faf5"))
	label.add_theme_color_override("font_shadow_color",Color("071923"))
	label.add_theme_constant_override("shadow_outline_size",4)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	subtitle_layer.add_child(label)
	subtitles[channel]={"label":label,"item":item,"pages":pages,"page":0,"started":started,"duration":duration,"until":started+duration}
	_layout_subtitles()

func _layout_subtitles() -> void:
	var index:=0
	for channel in subtitles:
		var label: Label=subtitles[channel].label
		label.visible=index<3
		label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		var half_width:=minf(420.,get_viewport().get_visible_rect().size.x*.43)
		label.offset_left=-half_width;label.offset_right=half_width
		label.offset_top=-150-index*82;label.offset_bottom=-78-index*82
		index+=1

func _clear_subtitle(channel: String) -> void:
	if not subtitles.has(channel):return
	var label: Label=subtitles[channel].label
	if is_instance_valid(label):label.queue_free()
	subtitles.erase(channel);_layout_subtitles()
