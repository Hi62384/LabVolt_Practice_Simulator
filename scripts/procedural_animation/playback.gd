extends RefCounted
## Playback and editable scene state. Consumers own the clock and authority.
const Document=preload("res://scripts/procedural_animation/document.gd")
const Formula=preload("res://scripts/procedural_animation/formula.gd")
var compiled: Dictionary={}
var scene: Dictionary={}
var objects: Dictionary={}
var ordered: Array=[]
var inputs: Array=[]
var revision:=0
var clock:=0.
var speed:=1.
var playing:=true
var highlight:=""
var history: Array[Dictionary]=[]
var live_parameters: Dictionary={}
var live_series: Dictionary={}

func load_scene(value: Variant) -> bool:
	var checked:=Document.compile(value)
	if not checked.ok:return false
	_install(checked)
	clock=0.
	playing=true
	speed=1.
	highlight=""
	history.clear()
	revision+=1
	return true

func _install(value: Dictionary) -> void:
	compiled=value
	scene=value.scene
	objects.clear()
	ordered=scene.objects.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary):
		var first:=int(a.get("layer",0))
		var second:=int(b.get("layer",0))
		return str(a.id)<str(b.id) if first==second else first<second)
	for item in ordered:objects[item.id]=item
	inputs=[0.,0.,PI,TAU]
	for id in compiled.names.slice(4):inputs.append(float(scene.parameters[id][0]))
	live_parameters.clear()
	live_series.clear()

func set_live_series(values: Dictionary) -> void:
	var next: Dictionary={}
	for id in compiled.get("series",{}):
		var points: Variant=values.get(id)
		if not points is PackedVector2Array or points.size()<2 or points.size()>128:continue
		var last_x:=-INF
		var valid:=true
		for point: Vector2 in points:
			if not point.is_finite() or point.x<=last_x:
				valid=false
				break
			last_x=point.x
		if valid:next[id]=points
	live_series=next

func set_live_parameters(values: Dictionary) -> bool:
	var next: Dictionary={}
	var parameters: Dictionary=scene.get("parameters",{})
	for id in parameters:
		var bounds: Array=parameters[id]
		var value: Variant=values.get(id)
		if Document._number(value,float(bounds[1]),float(bounds[2])):next[id]=float(value)
	if next==live_parameters:return false
	live_parameters=next
	for slot in range(4,inputs.size()):
		var id: String=compiled.names[slot]
		inputs[slot]=float(next.get(id,parameters[id][0]))
	return true

func advance(seconds: float) -> void:
	if playing and not scene.is_empty() and is_finite(seconds) and seconds>=0.:
		seek(clock+seconds*speed)

func seek(at: float) -> void:
	if scene.is_empty() or not is_finite(at):return
	var length:=float(scene.duration)
	clock=fposmod(at,length) if scene.get("loop",false) and at>length else clampf(at,0.,length)
	inputs[0]=clock

func command(action: Variant) -> bool:
	if not action is Dictionary or action.size()>5:return false
	var op: String=str(action.get("op",""))
	if op=="create":
		var checkpoint:=snapshot()
		var previous:=history.duplicate()
		if not load_scene(action.get("scene")):return false
		history.assign(previous)
		if not checkpoint.scene.is_empty():_remember(checkpoint)
		return true
	if op=="restore":
		if history.is_empty():return false
		if not restore_checkpoint(history.back()):return false
		history.pop_back()
		return true
	if scene.is_empty():return false
	match op:
		"play","pause","restart":
			playing=op!="pause"
			if op=="restart":seek(0.)
		"seek","step","speed":
			var amount: Variant=action.get("value")
			if not Document._number(amount,-180.,180.):return false
			if op=="speed":speed=clampf(float(amount),.25,4.)
			else:seek(float(amount) if op=="seek" else clock+float(amount))
		"highlight":
			if not action.get("id","") is String:return false
			var target: String=action.get("id","")
			if not target.is_empty() and not objects.has(target):return false
			highlight=target
		"parameter","add","remove","update","duplicate":
			return _edit(action,op)
		"layout":
			var value: Variant=action.get("value")
			if value not in Document.LAYOUTS:return false
			if value==scene.get("layout","right"):return true
			_remember(snapshot())
			scene=scene.duplicate(false)
			scene.layout=value
			compiled.scene=scene
		"clear":
			_remember(snapshot())
			playing=false
			scene={}
			compiled={}
			ordered.clear()
			objects.clear()
			live_parameters.clear()
			live_series.clear()
			highlight=""
		_:
			return false
	revision+=1
	return true

func _edit(action: Dictionary,op: String) -> bool:
	var next:=scene.duplicate(true)
	var id:=str(action.get("id",""))
	if op=="parameter":
		if not next.get("parameters",{}).has(id):return false
		next.parameters[id][0]=action.get("value")
	elif op=="add":
		next.objects.append(action.get("object"))
	else:
		var index: int=next.objects.find_custom(func(item):return item.id==id)
		if index<0:return false
		match op:
			"remove":next.objects.remove_at(index)
			"duplicate":
				var copy: Dictionary=next.objects[index].duplicate(true)
				copy.id=action.get("new_id")
				next.objects.append(copy)
			"update":
				var patch: Variant=action.get("set")
				if not patch is Dictionary or patch.has("id"):return false
				next.objects[index].merge(patch,true)
	var compiled_next:=Document.compile(next)
	if not compiled_next.ok:return false
	_remember(snapshot())
	var at:=clock
	_install(compiled_next)
	seek(at)
	if not objects.has(highlight):highlight=""
	revision+=1
	return true

func _remember(checkpoint: Dictionary) -> void:
	if history.size()>=6:history.pop_front()
	history.append(checkpoint)

func snapshot() -> Dictionary:
	return {"scene":scene.duplicate(true),"time":clock,"playing":playing,"speed":speed,"highlight":highlight,"revision":revision}

func restore_checkpoint(value: Dictionary) -> bool:
	if not Document._number(value.get("time"),0.,180.) or not Document._number(value.get("speed"),.25,4.) or not value.get("playing") is bool:return false
	var checked:=Document.compile(value.get("scene"))
	if not checked.ok:return false
	_install(checked)
	seek(float(value.time))
	playing=value.playing
	speed=float(value.speed)
	highlight=str(value.get("highlight",""))
	if not objects.has(highlight):highlight=""
	revision+=1
	return true

func property(item: Dictionary,key: String) -> float:
	var start:=float(item.get(key,Document.PROPERTIES[key]))
	var program: Expression=compiled.programs.get(item.id+":"+key)
	if program!=null:return Formula.value(program,inputs,start)
	var frames: Array=item.get("tracks",{}).get(key,[])
	if frames.is_empty():return start
	if clock<float(frames[0][0]):return float(frames[0][1])
	for i in range(1,frames.size()):
		if clock<=float(frames[i][0]):
			var before: Array=frames[i-1]
			var after: Array=frames[i]
			var weight:=(clock-float(before[0]))/(float(after[0])-float(before[0]))
			if item.get("easing","smooth")=="smooth":weight=smoothstep(0.,1.,weight)
			return lerpf(float(before[1]),float(after[1]),weight)
	return float(frames.back()[1])

func sample(id: String,axis_value: float) -> float:
	var program: Expression=compiled.programs.get(id+":plot")
	if program==null:return NAN
	inputs[1]=axis_value
	var result:=Formula.value(program,inputs,NAN)
	inputs[1]=0.
	return result

func sample_point(id: String,argument: float) -> Vector2:
	var y:=sample(id,argument)
	var x_program: Expression=compiled.programs.get(id+":plot_x")
	if x_program==null:return Vector2(argument,y)
	inputs[1]=argument
	var x:=Formula.value(x_program,inputs,NAN)
	inputs[1]=0.
	return Vector2(x,y)
