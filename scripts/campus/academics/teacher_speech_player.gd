extends Node
## Consumes host-ordered teacher speech events. Only a real supplied stream plays.
signal playback_started(room: String, serial: int, at_ms: int)
const MAX_QUEUED:=6
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
const Face=preload("res://scripts/campus/academics/character_face.gd")
const MAX_TEXT:=Speech.MAX_TEXT
const MAX_CACHED:=32
const MAX_WAV_BYTES:=8_000_000
const GAIN_META:="teacher_speech_gain"
var last_serial: Dictionary={}
var active: Dictionary={}
var queued: Dictionary={}
var awaiting: Dictionary={}
var subtitles: Dictionary={}
var presentations: Dictionary={}
var cached: Dictionary={}
var cache_order: Array[String]=[]
var subtitle_layer: CanvasLayer
var speech_enabled:=true
var subtitles_enabled:=true

func configure(speech: bool,captions: bool) -> void:
	speech_enabled=speech;subtitles_enabled=captions
	if not speech:
		for room in active.keys():
			_reading_clock(room)
			_stop(room)
		queued.clear()
	if not captions:
		for room in subtitles.keys():_clear_subtitle(room)

func _ready() -> void:
	subtitle_layer=CanvasLayer.new();subtitle_layer.layer=32;add_child(subtitle_layer)

func _exit_tree() -> void:
	clear_session()

func cache_stream(key: String,stream: AudioStreamWAV) -> bool:
	if key.is_empty() or key.length()>128 or not valid_stream(stream):return false
	if cached.has(key):cache_order.erase(key)
	elif cached.size()>=MAX_CACHED:
		cached.erase(cache_order.pop_front())
	cached[key]=stream;cache_order.append(key)
	return true

static func valid_stream(stream: AudioStreamWAV) -> bool:
	if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.mix_rate<8000 or stream.mix_rate>48000:return false
	var bytes:=stream.data.size()
	var frame_bytes:=4 if stream.stereo else 2
	return bytes>0 and bytes<=MAX_WAV_BYTES and bytes%frame_bytes==0 and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED

func stream_for(key: String) -> AudioStreamWAV:
	return cached.get(key)

func accept(room: String,teacher: String,serial: int,text: String,priority: int,anchor: Node3D,stream: AudioStream=null,pitch := 1.0) -> bool:
	if room.is_empty() or teacher.is_empty() or serial<=int(last_serial.get(room,0)) or serial<1 or serial>2147483647:return false
	if text.is_empty() or text.length()>MAX_TEXT or priority<0 or priority>4 or not is_instance_valid(anchor):return false
	if not is_finite(pitch) or pitch<.5 or pitch>2.:return false
	if stream is AudioStreamWAV and not valid_stream(stream):return false
	if active.has(room) and priority<=int(active[room].priority) and queued.get(room,[]).size()>=MAX_QUEUED:return false
	last_serial[room]=serial
	if not speech_enabled:stream=null
	var item:={"teacher":teacher,"serial":serial,"text":text,"priority":priority,"anchor":anchor,"stream":stream,"pitch":pitch}
	awaiting[room]={"item":item,"until":Time.get_ticks_msec()+40000}
	if active.has(room) and priority>int(active[room].priority):
		_stop(room)
		_start(room,item)
	elif active.has(room):
		var pending: Array=queued.get(room,[])
		pending.append(item);queued[room]=pending
	else:_start(room,item)
	return true

func cancel(room: String) -> void:
	_stop(room)
	queued.erase(room)
	awaiting.erase(room)
	presentations.erase(room)
	_clear_subtitle(room)

func clear_session() -> void:
	for room in active.keys():_stop(room)
	for room in subtitles.keys():_clear_subtitle(room)
	queued.clear();awaiting.clear();presentations.clear();last_serial.clear()
	cached.clear();cache_order.clear()

func _start(room: String,item: Dictionary) -> void:
	var anchor: Node3D=item.anchor
	if not is_instance_valid(anchor):return
	var now:=Time.get_ticks_msec()
	var duration:=maxi(7000,str(item.text).length()*65)
	presentations[room]={"serial":item.serial,"until":now+duration}
	if subtitles_enabled:_show_subtitle(room,item,now,duration)
	var stream: AudioStream=item.stream
	if stream==null:
		if not subtitles_enabled:presentations[room].until=now
		return
	for other_room in active.keys():
		if other_room==room or active[other_room].teacher!=item.teacher:continue
		if int(active[other_room].priority)>=int(item.priority):return
		_stop(other_room)
	var player:=AudioStreamPlayer3D.new()
	player.name="TeacherSpeech"
	player.stream=stream
	player.pitch_scale=item.pitch
	# Piper standalone supplies unscaled PCM. Apply its voice gain in the
	# native mixer instead of rewriting millions of samples on the main thread.
	var gain:=float(stream.get_meta(GAIN_META,1.))
	if not is_finite(gain):gain=1.
	player.volume_db=linear_to_db(clampf(gain,.0001,2.))
	player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size=12.0
	player.max_distance=34.0
	player.max_db=0.0
	anchor.add_child(player)
	var head := anchor.find_child("Head", true, false) as Node3D
	if is_instance_valid(head):
		player.global_position = head.global_position
	var mouth:=_mouth(anchor)
	active[room]={"serial":item.serial,"priority":item.priority,"teacher":item.teacher,"player":player,"mouth":mouth}
	presentations[room].until=now+int(ceil(stream.get_length()*1000./float(item.pitch)))+1000
	if subtitles.has(room):subtitles[room].until=presentations[room].until
	player.finished.connect(func():_finished(room,int(item.serial)))
	player.play()
	playback_started.emit(room, int(item.serial), Time.get_ticks_msec())

func deliver_stream(room: String,serial: int,stream: AudioStreamWAV) -> bool:
	if not speech_enabled or not valid_stream(stream) or serial!=int(last_serial.get(room,0)) or not awaiting.has(room):return false
	if Time.get_ticks_msec()>=int(awaiting[room].until):awaiting.erase(room);return false
	var item: Dictionary=awaiting[room].item
	if not is_instance_valid(item.anchor):return false
	awaiting.erase(room)
	item.stream=stream
	# Preserve queue order even while its current entry has captions but no
	# audio. Starting a later queued entry here would play it again on dequeue.
	if queued.get(room,[]).has(item):return true
	if active.has(room):
		return false
	_start(room,item)
	return active.has(room)

func _mouth(anchor: Node3D) -> MeshInstance3D:
	return Face.begin_speech(Face.head_for(anchor))

func _process(delta: float) -> void:
	var now:=Time.get_ticks_msec()
	for room in active.keys():
		var state: Dictionary=active[room]
		var player=state.get("player")
		if not is_instance_valid(player):_finished(room,int(state.serial));continue
		var mouth=state.get("mouth")
		if is_instance_valid(mouth):
			var level:=_pcm_level(player.stream,player.get_playback_position()) if player.stream is AudioStreamWAV else 0.0
			Face.speech_level(mouth,level,delta)
	for room in subtitles.keys():
		var subtitle: Dictionary=subtitles[room]
		var pages: Array=subtitle.get("pages",[])
		var has_audio: bool=active.has(room) and int(active[room].serial)==int(subtitle.item.serial) and is_instance_valid(active[room].get("player"))
		var progress:=clampf(float(now-int(subtitle.started))/float(subtitle.duration),0.,.9999)
		if has_audio:
			var player: AudioStreamPlayer3D=active[room].player
			progress=clampf(player.get_playback_position()/maxf(.1,player.stream.get_length()),0.,.9999)
		if pages.size()>1:
			var page_index:=_page_at(pages,progress)
			if page_index!=int(subtitle.get("page",0)):
				subtitle.page=page_index
				subtitle.label.text=str(subtitle.item.teacher)+": "+str(pages[page_index])
		if not has_audio and now>=int(subtitle.until):_clear_subtitle(room)
	for room in presentations.keys():
		if not active.has(room) and now>=int(presentations[room].until):_advance_queue(room)
	for room in awaiting.keys():
		if now>=int(awaiting[room].until):awaiting.erase(room)

static func _page_at(pages: Array,progress: float) -> int:
	# Longer pages need more time than a short final sentence.
	var total:=0
	for page in pages:total+=str(page).length()
	var before:=0
	for index in pages.size():
		before+=str(pages[index]).length()
		if progress*total<float(before):return index
	return maxi(0,pages.size()-1)

func _reading_clock(room: String) -> void:
	if not subtitles.has(room):return
	var subtitle: Dictionary=subtitles[room]
	var before:=0
	var total:=0
	for index in subtitle.pages.size():
		var count:=str(subtitle.pages[index]).length()
		if index<int(subtitle.page):before+=count
		total+=count
	subtitle.started=Time.get_ticks_msec()-int(float(before)/maxi(1,total)*int(subtitle.duration))
	subtitle.until=int(subtitle.started)+int(subtitle.duration)
	if presentations.has(room):presentations[room].until=subtitle.until

static func _pcm_level(stream: AudioStreamWAV,seconds: float) -> float:
	if stream.format!=AudioStreamWAV.FORMAT_16_BITS:return 0.0
	var data: PackedByteArray=stream.data
	var channels:=2 if stream.stereo else 1
	var index:=int(maxf(0.0,seconds)*stream.mix_rate)*channels*2
	if index<0 or index+1>=data.size():return 0.0
	var peak:=0.0
	for sample in 16:
		var at:=index+sample*channels*2
		if at+1>=data.size():break
		var value:=int(data[at])+(int(data[at+1])<<8)
		if value>=32768:value-=65536
		peak=maxf(peak,absf(float(value)/32768.0))
	return peak

func _finished(room: String,serial: int) -> void:
	if not active.has(room) or int(active[room].serial)!=serial:return
	_stop(room)
	if queued.get(room,[]).is_empty():
		var until:=Time.get_ticks_msec()+1000
		if presentations.has(room):presentations[room].until=until
		if subtitles.has(room):
			subtitles[room].until=until
			subtitles[room].started=Time.get_ticks_msec()-int(subtitles[room].duration)
		return
	_advance_queue(room)

func _advance_queue(room: String) -> void:
	presentations.erase(room)
	var pending: Array=queued.get(room,[])
	while not pending.is_empty():
		var next: Dictionary=pending.pop_front()
		queued[room]=pending
		_start(room,next)
		if presentations.has(room):break
	if pending.is_empty():queued.erase(room)

func _stop(room: String) -> void:
	if not active.has(room):return
	var state: Dictionary=active[room]
	var player=state.get("player")
	if is_instance_valid(player):player.stop();player.queue_free()
	var mouth=state.get("mouth")
	if is_instance_valid(mouth):Face.end_speech(mouth)
	active.erase(room)

func _show_subtitle(room: String,item: Dictionary,started: int,duration: int) -> void:
	for previous in subtitles.keys():_clear_subtitle(previous)
	var pages:=Speech.pages(str(item.text))
	var label:=Label.new();label.text=str(item.teacher)+": "+str(pages[0] if not pages.is_empty() else item.text)
	label.add_theme_color_override("font_color",Color("f3faf5"))
	label.add_theme_color_override("font_shadow_color",Color("071923"))
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	subtitle_layer.add_child(label)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var half_width := minf(360.0,get_viewport().get_visible_rect().size.x*.40)
	label.offset_left = -half_width
	label.offset_right = half_width
	label.offset_top = -206
	label.offset_bottom = -150
	subtitles[room]={"label":label,"item":item,"pages":pages,"page":0,"started":started,"duration":duration,"until":started+duration}

func _clear_subtitle(room: String) -> void:
	if not subtitles.has(room):return
	var label: Label=subtitles[room].label
	if is_instance_valid(label):label.queue_free()
	subtitles.erase(room)
