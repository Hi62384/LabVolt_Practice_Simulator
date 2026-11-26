extends Node
## Consumes host-ordered teacher speech events. Only a real supplied stream plays.
const MAX_QUEUED:=6
const MAX_TEXT:=350
const MAX_CACHED:=32
const MAX_WAV_BYTES:=2_000_000
var last_serial: Dictionary={}
var active: Dictionary={}
var queued: Dictionary={}
var awaiting: Dictionary={}
var subtitles: Dictionary={}
var cached: Dictionary={}
var cache_order: Array[String]=[]
var subtitle_layer: CanvasLayer
var speech_enabled:=true
var subtitles_enabled:=true

func configure(speech: bool,captions: bool) -> void:
	speech_enabled=speech;subtitles_enabled=captions
	if not speech:
		for room in active.keys():_stop(room)
		queued.clear()
	if not captions:
		for room in subtitles.keys():_clear_subtitle(room)

func _ready() -> void:
	subtitle_layer=CanvasLayer.new();subtitle_layer.layer=32;add_child(subtitle_layer)

func cache_stream(key: String,stream: AudioStreamWAV) -> bool:
	if key.is_empty() or key.length()>128 or stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.mix_rate<8000 or stream.mix_rate>48000:return false
	if stream.data.is_empty() or stream.data.size()>MAX_WAV_BYTES:return false
	if cached.has(key):cache_order.erase(key)
	elif cached.size()>=MAX_CACHED:
		cached.erase(cache_order.pop_front())
	cached[key]=stream;cache_order.append(key)
	return true

func stream_for(key: String) -> AudioStreamWAV:
	return cached.get(key)

func accept(room: String,teacher: String,serial: int,text: String,priority: int,anchor: Node3D,stream: AudioStream=null) -> bool:
	if room.is_empty() or teacher.is_empty() or serial<=int(last_serial.get(room,0)) or serial<1 or serial>2147483647:return false
	if text.is_empty() or text.length()>MAX_TEXT or priority<0 or priority>4 or not is_instance_valid(anchor):return false
	last_serial[room]=serial
	if not speech_enabled:stream=null
	var item:={"teacher":teacher,"serial":serial,"text":text,"priority":priority,"anchor":anchor,"stream":stream}
	awaiting[room]={"item":item,"until":Time.get_ticks_msec()+16000}
	if active.has(room) and priority>int(active[room].priority):
		_stop(room)
		_start(room,item)
	elif active.has(room):
		var pending: Array=queued.get(room,[])
		if pending.size()>=MAX_QUEUED:return true
		pending.append(item);queued[room]=pending
	else:_start(room,item)
	return true

func cancel(room: String) -> void:
	_stop(room)
	queued.erase(room)
	awaiting.erase(room)
	_clear_subtitle(room)

func clear_session() -> void:
	for room in active.keys():_stop(room)
	for room in subtitles.keys():_clear_subtitle(room)
	queued.clear();awaiting.clear();last_serial.clear()
	cached.clear();cache_order.clear()

func _start(room: String,item: Dictionary) -> void:
	var anchor: Node3D=item.anchor
	if not is_instance_valid(anchor):return
	if subtitles_enabled:_show_subtitle(room,item)
	var stream: AudioStream=item.stream
	if stream==null:return
	for other_room in active.keys():
		if other_room==room or active[other_room].teacher!=item.teacher:continue
		if int(active[other_room].priority)>=int(item.priority):return
		_stop(other_room)
	var player:=AudioStreamPlayer3D.new()
	player.name="TeacherSpeech"
	player.stream=stream
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
	player.finished.connect(func():_finished(room,int(item.serial)))
	player.play()

func deliver_stream(room: String,serial: int,stream: AudioStreamWAV) -> bool:
	if not speech_enabled or stream==null or serial!=int(last_serial.get(room,0)) or not awaiting.has(room):return false
	if Time.get_ticks_msec()>=int(awaiting[room].until):awaiting.erase(room);return false
	var item: Dictionary=awaiting[room].item
	if not is_instance_valid(item.anchor):return false
	awaiting.erase(room)
	item.stream=stream
	if active.has(room):
		if int(active[room].serial)==serial:return false
		# A synthesized response can arrive while the previous line is still
		# playing. The queued item shares this dictionary and now owns the stream.
		return queued.get(room,[]).has(item)
	_start(room,item)
	return active.has(room)

func _mouth(anchor: Node3D) -> MeshInstance3D:
	var head:=anchor.find_child("Head",true,false) as Node3D
	if head==null:return null
	var mouth:=head.get_node_or_null("SpeechMouth") as MeshInstance3D
	if mouth==null:
		mouth=MeshInstance3D.new();mouth.name="SpeechMouth"
		var vertices:=PackedVector3Array()
		for sector in 12:
			var a:=TAU*sector/12.0
			var b:=TAU*(sector+1)/12.0
			vertices.append(Vector3.ZERO)
			for angle in [b,a]:
				var x: float=cos(angle)*.044
				vertices.append(Vector3(x,sin(angle)*.020,-absf(x)*.14))
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mouth.mesh=mesh
		var material:=StandardMaterial3D.new();material.albedo_color=Color("352423")
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mouth.material_override=material
		mouth.position=Vector3(0,-.125,.151);head.add_child(mouth)
		mouth.scale.y=.12
	mouth.visible=true
	var neutral:=head.get_node_or_null("NeutralMouth") as Node3D
	if neutral:neutral.hide()
	return mouth

func _process(delta: float) -> void:
	for room in active.keys():
		var state: Dictionary=active[room]
		var player=state.get("player")
		if not is_instance_valid(player):_finished(room,int(state.serial));continue
		var mouth=state.get("mouth")
		if is_instance_valid(mouth):
			var level:=_pcm_level(player.stream,player.get_playback_position()) if player.stream is AudioStreamWAV else 0.0
			mouth.scale.y=lerpf(mouth.scale.y,.12+clampf(level*5.0,0.0,1.25),1.0-exp(-delta*20.0))
	for room in subtitles.keys():
		if Time.get_ticks_msec()>=int(subtitles[room].until):_clear_subtitle(room)
	for room in awaiting.keys():
		if Time.get_ticks_msec()>=int(awaiting[room].until):awaiting.erase(room)

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
	var pending: Array=queued.get(room,[])
	if pending.is_empty():queued.erase(room);return
	var next: Dictionary=pending.pop_front();queued[room]=pending
	_start(room,next)

func _stop(room: String) -> void:
	if not active.has(room):return
	var state: Dictionary=active[room]
	var player=state.get("player")
	if is_instance_valid(player):player.stop();player.queue_free()
	var mouth=state.get("mouth")
	if is_instance_valid(mouth):
		mouth.scale.y=.12
		var neutral:=mouth.get_parent().get_node_or_null("NeutralMouth") as Node3D
		if neutral:
			neutral.show()
			mouth.hide()
	active.erase(room)

func _show_subtitle(room: String,item: Dictionary) -> void:
	for previous in subtitles.keys():_clear_subtitle(previous)
	var label:=Label.new();label.text=str(item.teacher)+": "+str(item.text)
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
	subtitles[room]={"label":label,"item":item,"until":Time.get_ticks_msec()+7000}

func _clear_subtitle(room: String) -> void:
	if not subtitles.has(room):return
	var label: Label=subtitles[room].label
	if is_instance_valid(label):label.queue_free()
	subtitles.erase(room)
