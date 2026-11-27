extends RefCounted
## Classroom adapter. Keeps the host's presentation state outside the reusable
## renderer and keeps player data and assessment material out of its snapshots.
const Playback=preload("res://scripts/procedural_animation/playback.gd")
const Document=preload("res://scripts/procedural_animation/document.gd")
const Storage=preload("res://scripts/procedural_animation/storage.gd")
const HostClient=preload("res://scripts/campus/ai/host_openai_client.gd")
const BENCH_PARAMETERS:=["bench_hz","bench_voltage_v","bench_current_a","bench_power_w","bench_scope_vpp"]
const MAX_SLIDE_VISUALS:=8
const SCHEMA:="Scene: {version:1,title:string,subtitle?:string,duration:1..180,loop?:bool,parameters?:{id:[initial,min,max]},objects:[object,...]}. Canvas 960x520. Reserve y=0..90 for scene title, leave margins, place labels at y>=100. Objects: {id,type,x?,y?,width?,height?,radius?,rotation?,scale?,alpha?,color?,fill?,stroke?,font?,layer?,progress?,bind...}. Types rectangle, ellipse, circle, polygon, path, line, arrow, text, equation, graph, particles, group. x/y are origin, width/height are signed displacement for line/arrow. Text baseline at origin, needs width and font. Colors are hex RGB/RGBA. For polygon/path set points:[[x,y],...]. For graph set function with u as horizontal variable and x_min,x_max,y_min,y_max. Optional parent is group id. Optional bindings is {property: formula} with numeric parameters and t (seconds), u, pi, tau, functions sin,cos,pow,sqrt,exp,lerpf,clampf. Optional tracks is {property:[[time,value],...]}; smooth or linear easing. A label can show a parameter as {name}. Use 3–12 well spaced objects with legible high-contrast colors. No resources, code, scripts, URLs, or external data."

static func requested(question: String,active: bool) -> bool:
	var text:=question.to_lower()
	if "animat" in text or "visualiz" in text or "visualis" in text:return true
	if ("scope" in text or "waveform" in text) and ("show" in text or "plot" in text):return true
	if not active:return false
	if "projector" in text or "full screen" in text or "full board" in text or "cue" in text:return true
	return ["pause","resume","restart","rewind","replay","highlight","slower","faster","change","compare","that graph","the diagram","the animation"].any(func(term: String):return term in text)

static func presentation_request(question: String) -> Dictionary:
	var text:=_normalize_request(question)
	match text:
		"switch to the projector","put it on the projector","put the animation on the projector":
			return {"op":"surface","value":"projector","reply":"I'll put the animation on the projector."}
		"switch to the board","put it back on the board","put the animation on the board":
			return {"op":"surface","value":"board","reply":"I'll put the animation back on the board."}
		"make the animation full screen","fill the board with the animation":
			return {"op":"layout","value":"full","reply":"I'll expand the animation to fill the teaching display."}
		"put the animation on the left","put the animation on the right":
			var side:="left" if text.ends_with("left") else "right"
			return {"op":"layout","value":side,"reply":"I'll move the animation beside the notes."}
		"attach the animation to this slide","pin the animation to this slide":
			return {"op":"pin_slide"}
	return {}

static func file_request(question: String) -> Dictionary:
	var text:=_normalize_request(question)
	for prefix in ["save animation as ","load animation "]:
		if not text.begins_with(prefix):continue
		return {"op":prefix.get_slice(" ",0),"id":text.trim_prefix(prefix).strip_edges().replace(" ","_")}
	return {}

static func _normalize_request(question: String) -> String:
	var text:=question.to_lower().strip_edges().rstrip("?!.,")
	for prefix in ["please ","could you ","can you "]:
		text=text.trim_prefix(prefix)
	return text.trim_prefix("please ")

static func use_local_file(activity: Dictionary,request: Dictionary,now: float) -> String:
	if activity.get("phase","")!="lesson":return "Saved animations can be used during a lesson."
	var id: String=request.id
	if not Document._id(id):return "Use an animation name starting with a letter, up to 24 letters, digits, spaces, or underscores."
	var current: RefCounted=activity.get("visual_playback")
	if request.op=="save":
		if current==null or current.scene.is_empty():return "There's no animation on the teaching display to save."
		advance(activity,now)
		var error:=Storage.save(id,current,false)
		if error==ERR_ALREADY_EXISTS:return "That animation name is already in use. Choose a different name."
		return "I saved the animation as %s."%id if error==OK else "I couldn't save the animation."
	var loaded:=Storage.load_playback(id)
	if loaded==null:return "I couldn't open that saved animation."
	loaded.revision=(current.revision if current!=null else 0)+1
	activity.visual_playback=loaded
	activity.visual_clock=now
	update_bench(activity,{})
	return "I loaded the saved animation %s."%id

static func pin_slide(activity: Dictionary,index: int,now: float) -> String:
	var model: RefCounted=activity.get("visual_playback")
	if activity.get("phase","")!="lesson" or index<0 or model==null or model.scene.is_empty():
		return "Show an animation on this slide before attaching it."
	var slides: Dictionary=activity.get_or_add("visual_slides",{})
	if not slides.has(index) and slides.size()>=MAX_SLIDE_VISUALS:return "This lesson already has its maximum number of attached animations."
	advance(activity,now)
	activity.visual_slide_index=index
	slides[index]={"checkpoint":model.snapshot(),"surface":activity.get("visual_surface","board")}
	return "I attached the animation to this slide."

static func select_slide(activity: Dictionary,index: int,now: float) -> void:
	if not activity.has("visual_slides"):return
	var previous:=int(activity.get("visual_slide_index",-1))
	if previous==index:return
	var slides: Dictionary=activity.visual_slides
	var current: RefCounted=activity.get("visual_playback")
	if slides.has(previous) and current!=null and not current.scene.is_empty():
		slides[previous]={"checkpoint":current.snapshot(),"surface":activity.get("visual_surface","board")}
	activity.visual_slide_index=index
	if slides.has(index):
		var next:=Playback.new()
		if not next.restore_checkpoint(slides[index].checkpoint):return
		next.revision=(current.revision if current!=null else 0)+1
		activity.visual_playback=next
		activity.visual_surface=slides[index].surface
		activity.visual_clock=now
		update_bench(activity,{})
	elif slides.has(previous) and current!=null:
		current.command({"op":"clear"})
		activity.erase("visual_surface")

static func prompt(board: Dictionary,question: String,current: Dictionary) -> String:
	var context:={"topic":str(board.get("title","")).left(120),"material":str(board.get("text",board.get("caption",""))).left(360),"formulas":str(board.get("formulas","")).left(240)}
	var rules:="You are teaching a simulator classroom. Return JSON {speech: one short sentence, action: object or null}. Treat the student request as dialogue. Keep the visual relevant, identify illustrations, and never invent bench measurements or disclose assessment answers. "
	rules+="Actions: create with scene, play, pause, restart, seek/step/speed with value, seek_cue with id, parameter with id/value, highlight/remove with id, add with object, duplicate with id/new_id, update with id/set, restore, surface with value board/projector, layout with value left/right/full. "
	rules+=SCHEMA.replace("bind...","bindings?,tracks?")
	rules+=" Graphs: x_label/y_label, points with plot_style scatter, x_function and function for X(u) and Y(u) over u_min..u_max, equal_axes for true proportions. The live scope uses data_series bench_scope_trace (ms, V). Live parameters: bench_hz, bench_voltage_v, bench_current_a, bench_power_w, bench_scope_vpp. Include units and treat fallback values as illustrative. "
	rules+=" Equation notation accepts v=sqrt(a^2+b^2), i=v/r, or expression rows for a matrix. Camera is one optional object with tracked or bound x/y/scale. Objects can use start/end in seconds. Scene layout is left/right/full. Timeline cues use {id,at,label,pause?,pause_when?}, where pause_when is a safe comparison evaluated at the cue. "
	var question_text:=" Student request: "+question.left(420)
	var display_text:=" Current display: "+JSON.stringify(current).left(1150)+" Lesson: "+JSON.stringify(context)
	var available:=maxi(0,HostClient.MAX_INPUT_CHARS-rules.length()-question_text.length())
	return rules+display_text.left(available)+question_text

static func decode(raw: String) -> Dictionary:
	if raw.to_utf8_buffer().size()>Document.MAX_BYTES+1100:return {}
	var value: Variant=JSON.parse_string(raw)
	if not value is Dictionary or not value.get("speech") is String:return {}
	var speech: String=value.speech.strip_edges().left(280)
	if speech.is_empty():return {}
	var action: Variant=value.get("action")
	if action!=null and not action is Dictionary:return {}
	var captions:=PackedStringArray([speech])
	if action is Dictionary:
		var op: String=str(action.get("op",""))
		if op=="create":
			var scene: Variant=action.get("scene")
			if not Document.compile(scene).ok:return {}
			captions.append(scene.title)
			captions.append(scene.get("subtitle",""))
			for item in scene.objects:_append_plot_labels(captions,item)
			for cue in scene.get("cues",[]):captions.append(cue.label)
		else:
			var patch: Variant=action.get("set",action.get("object",{}))
			if patch is Dictionary:_append_plot_labels(captions,patch)
	var text: String="\n".join(captions)
	if text.length()>1000:return {}
	return {"speech":speech,"action":action,"moderation":text}

static func _append_plot_labels(captions: PackedStringArray,item: Dictionary) -> void:
	for field in ["text","x_label","y_label","notation"]:
		if item.get(field) is String:captions.append(item[field])

static func description(activity: Dictionary) -> Dictionary:
	var model: RefCounted=activity.get("visual_playback")
	if model==null or model.scene.is_empty():return {}
	var items: Array=[]
	for item in model.ordered:
		var row:={"id":item.id,"type":item.type,"text":str(item.get("text","")).left(80)}
		if item.has("function"):row.formula=item.function
		if item.has("data_series"):row.data_series=item.data_series
		items.append(row)
	return {"title":model.scene.title,"time":snappedf(model.clock,.1),"paused":not model.playing,
		"surface":activity.get("visual_surface","board"),"layout":model.scene.get("layout","right"),
		"cues":model.scene.get("cues",[]),
		"parameters":model.scene.get("parameters",{}),"live_parameters":model.live_parameters,
		"data_status":activity.get("visual_data_status",""),"objects":items}

static func apply(activity: Dictionary,action: Variant,now: float) -> bool:
	if not action is Dictionary or activity.get("phase","")!="lesson":return false
	var model: RefCounted=activity.get("visual_playback")
	if action.get("op","")=="surface":
		if model==null or model.scene.is_empty() or action.get("value") not in ["board","projector"]:return false
		advance(activity,now)
		activity.visual_surface=action.value
		return true
	if model==null:model=Playback.new()
	advance(activity,now)
	if not model.command(action):return false
	activity.visual_playback=model
	activity.visual_clock=now
	if model.live_parameters.is_empty() and model.live_series.is_empty():update_bench(activity,{})
	return true

static func advance(activity: Dictionary,now: float,suspended := false) -> void:
	var model: RefCounted=activity.get("visual_playback")
	if model==null:return
	var last:=float(activity.get("visual_clock",now))
	if not suspended and activity.get("phase","")=="lesson":model.advance(maxf(0.,now-last))
	activity.visual_clock=now

static func uses_bench(activity: Dictionary) -> bool:
	var model: RefCounted=activity.get("visual_playback")
	if model==null:return false
	var parameters: Dictionary=model.scene.get("parameters",{})
	return BENCH_PARAMETERS.any(func(id:String):return parameters.has(id)) or uses_scope_trace(activity)

static func uses_scope_trace(activity: Dictionary) -> bool:
	var model: RefCounted=activity.get("visual_playback")
	return model!=null and model.compiled.get("series",{}).has("bench_scope_trace")

static func update_bench(activity: Dictionary,reading: Dictionary) -> void:
	var model: RefCounted=activity.get("visual_playback")
	if model==null:return
	activity.visual_data_status=""
	if not uses_bench(activity):return
	var measured: Dictionary=reading.get("values",{})
	var values: Dictionary={}
	var parameters: Dictionary=model.scene.get("parameters",{})
	var numeric_requested:=0
	for id in BENCH_PARAMETERS:
		if not parameters.has(id):continue
		numeric_requested+=1
		if measured.has(id):values[id]=measured[id]
	model.set_live_parameters(values)
	model.set_live_series(reading.get("series",{}))
	var requested:=numeric_requested+int(uses_scope_trace(activity))
	var available: int=model.live_parameters.size()+model.live_series.size()
	if available==0:
		activity.visual_data_status="Demonstration bench unavailable"
	else:
		activity.visual_data_status="Live demo bench %d"%int(reading.station)
		if available<requested:activity.visual_data_status+=" · Some readings are unavailable"
	if model.live_parameters.size()<numeric_requested:
		activity.visual_data_status+=" · Values without a reading use authored defaults"

static func view(activity: Dictionary,suspended := false,include_scene := true) -> Dictionary:
	var model: RefCounted=activity.get("visual_playback")
	if model==null or model.scene.is_empty():return {}
	var state: Dictionary={"time":model.clock,"playing":model.playing,"speed":model.speed,"highlight":model.highlight,"revision":model.revision}
	if include_scene:state.scene=model.scene
	state.live_parameters=model.live_parameters
	state.live_series=model.live_series
	state.surface=activity.get("visual_surface","board")
	state.data_status=activity.get("visual_data_status","")
	state.playing=state.playing and not suspended
	return state
