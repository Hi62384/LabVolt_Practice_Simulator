extends RefCounted
## Versioned document validator and compiler. Coordinates use logical pixels
## in a shared 960 × 520 canvas. Rejected documents never replace live state.
const Formula=preload("res://scripts/procedural_animation/formula.gd")
const MathParser=preload("res://scripts/mth147/parser.gd")
const SIZE:=Vector2(960.,520.)
const MAX_BYTES:=12000
const OBJECTS:=36
const KINDS:=["rectangle","ellipse","circle","polygon","path","line","arrow","text","equation","graph","particles","group","camera"]
const PROPERTIES:={"x":0.,"y":0.,"width":120.,"height":72.,"rotation":0.,"scale":1.,"alpha":1.,"stroke":3.,"progress":1.,"font":30.,"radius":18.,"x_min":-6.28,"x_max":6.28,"y_min":-1.5,"y_max":1.5,"u_min":0.,"u_max":TAU}
const COLORS:=["071a28","102a39","e2edf4","82c8dc","46dfc1","ffc671","ff8184","b4adff"]
const LAYOUTS:=["right","left","full"]
const ROOT_FIELDS:=["version","title","subtitle","duration","loop","parameters","objects","layout","cues"]
const META_FIELDS:=["id","type","parent","text","notation","color","fill","points","function","x_function","x_label","y_label","plot_style","equal_axes","data_series","count","bindings","tracks","dash","easing","layer","start","end"]
static var id_pattern:=RegEx.create_from_string("^[a-z][a-z0-9_]{0,23}$")

static func parse(source: String) -> Dictionary:
	if source.to_utf8_buffer().size()>MAX_BYTES:return _fail("Scene is too large.")
	var json:=JSON.new()
	if json.parse(source)!=OK:return _fail("Invalid scene JSON.")
	return compile(json.data)

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _known(raw,ROOT_FIELDS):return _fail("Unknown scene fields.")
	if raw.get("version")!=1:return _fail("Unsupported scene version.")
	if raw.get("layout","right") not in LAYOUTS:return _fail("Unknown presentation layout.")
	if not _text(raw.get("title"),80) or str(raw.title).is_empty() or not _text(raw.get("subtitle",""),120):return _fail("Invalid scene title.")
	if not _number(raw.get("duration"),1.,180.) or not raw.get("loop",false) is bool:return _fail("Invalid playback settings.")
	var cues: Variant=raw.get("cues",[])
	if not cues is Array or cues.size()>12:return _fail("Too many or invalid timeline cues.")
	var cue_ids: Dictionary={}
	var previous_cue:=0.
	for cue in cues:
		if not cue is Dictionary or not _known(cue,["id","at","label","pause","pause_when"]):return _fail("Invalid timeline cue.")
		if not _id(cue.get("id")) or cue_ids.has(cue.id) or not _text(cue.get("label"),54):return _fail("Invalid cue name or label.")
		if not _number(cue.get("at"),.001,raw.duration) or float(cue.at)<=previous_cue or not cue.get("pause",false) is bool:
			return _fail("Timeline cues must be sorted by time.")
		cue_ids[cue.id]=true
		previous_cue=float(cue.at)
	var params: Variant=raw.get("parameters",{})
	if not params is Dictionary or params.size()>12:return _fail("Too many or invalid parameters.")
	var names:=PackedStringArray(["t","u","pi","tau"])
	for id in params:
		var p: Variant=params[id]
		if not _id(id) or id in names or id in Formula.FUNCTIONS or not p is Array or p.size()!=3:return _fail("Invalid parameter.")
		if not _number(p[1],-10000.,10000.) or not _number(p[2],float(p[1]),10000.) or not _number(p[0],float(p[1]),float(p[2])):return _fail("Invalid parameter range.")
		names.append(id)
	var cue_conditions: Dictionary={}
	for cue in cues:
		if not cue.has("pause_when"):continue
		var condition:=Formula.compile(cue.pause_when,names)
		if condition==null or not cue.get("pause",false):return _fail("Invalid cue pause condition.")
		cue_conditions[cue.id]=condition
	var value: Variant=raw.get("objects")
	if not value is Array or value.is_empty() or value.size()>OBJECTS:return _fail("Invalid object count.")
	var objects: Dictionary={}
	var programs: Dictionary={}
	var animated_plots: Dictionary={}
	var series: Dictionary={}
	var notation: Dictionary={}
	var camera_id:=""
	var complexity:=0
	for object in value:
		if not object is Dictionary or not _known(object,META_FIELDS+PROPERTIES.keys()):return _fail("Unknown object fields.")
		var id: Variant=object.get("id")
		var kind: Variant=object.get("type")
		if not _id(id) or objects.has(id) or not kind in KINDS:return _fail("Invalid object identity or type.")
		if kind=="camera":
			if not camera_id.is_empty() or not _known(object,["id","type","x","y","scale","easing","tracks","bindings"]):
				return _fail("Only one independent camera is supported.")
			camera_id=id
		if not _text(object.get("text",""),160) or not _text(object.get("parent",""),24):return _fail("Invalid object text or parent.")
		if object.has("notation"):
			if kind!="equation":return _fail("Mathematical notation requires an equation object.")
			var parsed:=_notation(object.notation)
			if parsed.is_empty():return _fail("Invalid mathematical notation.")
			notation[id]=parsed
			complexity+=4
		if not _number(object.get("start",0.),0.,raw.duration) or not _number(object.get("end",raw.duration),float(object.get("start",0.)),raw.duration):
			return _fail("Invalid object visibility interval.")
		for field in ["x_label","y_label"]:
			if object.has(field) and (kind!="graph" or not _text(object[field],36)):return _fail("Invalid graph axis label.")
		if object.has("plot_style") and (kind!="graph" or object.plot_style not in ["line","scatter"]):return _fail("Invalid plot style.")
		if object.has("equal_axes") and (kind!="graph" or not object.equal_axes is bool):return _fail("Invalid graph scale.")
		if object.has("x_function") and (kind!="graph" or not object.has("function")):return _fail("A parametric graph needs both coordinate functions.")
		for field in ["color","fill"]:
			if object.has(field) and not _color(object[field]):return _fail("Invalid color.")
		if not _number(object.get("layer",0.),-32.,32.) or not object.get("dash",false) is bool or object.get("easing","smooth") not in ["linear","smooth"]:return _fail("Invalid object styles.")
		var points: Variant=object.get("points",[])
		if not points is Array or points.size()>64:return _fail("Invalid points.")
		for point in points:
			if not point is Array or point.size()!=2 or not _number(point[0],-1920.,1920.) or not _number(point[1],-1920.,1920.):return _fail("Invalid point coordinates.")
		if kind=="particles" and not _number(object.get("count",12),1.,48.):return _fail("Invalid particle count.")
		if kind in ["polygon","path"] and points.size()<(3 if kind=="polygon" else 2):return _fail("Too few path points.")
		if object.has("data_series"):
			if kind!="graph" or object.has("function") or not points.is_empty() or not _id(object.data_series):return _fail("Invalid graph data source.")
			series[object.data_series]=true
			if series.size()>4:return _fail("Too many graph data sources.")
			complexity+=4
		elif kind=="graph":
			if points.is_empty():
				var plot:=Formula.compile(object.get("function"),names)
				if plot==null:return _fail("Invalid plot formula on "+id)
				programs[id+":plot"]=plot
				var expressions: String=object.function
				if object.has("x_function"):
					var x_plot:=Formula.compile(object.x_function,names)
					if x_plot==null:return _fail("Invalid horizontal plot formula on "+id)
					programs[id+":plot_x"]=x_plot
					expressions+=" "+object.x_function
					complexity+=3
				animated_plots[id]=Formula.token.search_all(expressions).any(func(word: RegExMatch):return word.get_string()=="t")
			elif object.has("function"):return _fail("A graph must choose points or formulas.")
			complexity+=4
		var bindings: Variant=object.get("bindings",{})
		var tracks: Variant=object.get("tracks",{})
		if not bindings is Dictionary or not tracks is Dictionary or bindings.size()+tracks.size()>12:return _fail("Invalid animation channels.")
		if kind=="camera" and not _known(bindings,["x","y","scale"]):return _fail("Invalid camera binding.")
		if kind=="camera" and not _known(tracks,["x","y","scale"]):return _fail("Invalid camera track.")
		for field in PROPERTIES:
			if object.has(field) and not _number(object[field],-5000.,5000.):return _fail("Invalid property value.")
		for field in bindings:
			if not PROPERTIES.has(field) or tracks.has(field):return _fail("Invalid bound property.")
			var program:=Formula.compile(bindings[field],names)
			if program==null:return _fail("Invalid formula on "+id+"."+field)
			programs[id+":"+field]=program
		for field in tracks:
			var frames: Variant=tracks[field]
			if not PROPERTIES.has(field) or not frames is Array or frames.is_empty() or frames.size()>24:return _fail("Invalid keyframes.")
			var last:=-1.
			for frame in frames:
				if not frame is Array or frame.size()!=2 or not _number(frame[0],0.,raw.duration) or not _number(frame[1],-5000.,5000.) or float(frame[0])<=last:return _fail("Unsorted or invalid keyframes.")
				last=float(frame[0])
		objects[id]=object
		complexity+=1+bindings.size()
	if complexity>90:return _fail("Scene exceeds the rendering budget.")
	for object in value:
		var parent: String=object.get("parent","")
		var visited: Array=[object.id]
		while not parent.is_empty():
			if visited.size()>4 or parent in visited or not objects.has(parent) or objects[parent].type!="group":return _fail("Invalid or cyclic object hierarchy.")
			visited.append(parent)
			parent=objects[parent].get("parent","")
	if JSON.stringify(raw).to_utf8_buffer().size()>MAX_BYTES:return _fail("Scene is too large.")
	return {"ok":true,"scene":raw.duplicate(true),"programs":programs,"names":names,"animated_plots":animated_plots,"series":series,"camera_id":camera_id,"notation":notation,"cue_conditions":cue_conditions}

static func _notation(source: Variant) -> Dictionary:
	var parser:=MathParser.new()
	if _text(source,128):
		var sides: PackedStringArray=source.split("=")
		if sides.size()>2:return {}
		var args: Array[Dictionary]=[]
		for side in sides:
			var parsed:=parser.parse(side)
			if not parsed.ok:return {}
			args.append(parsed.ast)
		return args[0] if args.size()==1 else {"op":"equation","args":args}
	if not source is Array or source.is_empty() or source.size()>4:return {}
	var rows: Array=[]
	var cols:=0
	for row in source:
		if not row is Array or row.is_empty() or row.size()>4:return {}
		if cols==0:cols=row.size()
		if cols!=row.size():return {}
		var cells: Array[Dictionary]=[]
		for expression in row:
			if not _text(expression,32):return {}
			var parsed:=parser.parse(expression)
			if not parsed.ok:return {}
			cells.append(parsed.ast)
		rows.append(cells)
	return {"op":"matrix","rows":rows}

static func _known(value: Dictionary, allowed: Array) -> bool:
	for field in value:
		if field not in allowed:return false
	return true

static func _text(value: Variant,count: int) -> bool:
	return value is String and value.length()<=count

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _id(value: Variant) -> bool:
	return value is String and value.length()<=24 and id_pattern.search(value)!=null

static func _color(value: Variant) -> bool:
	return value is String and value.length() in [6,7,8,9] and Color.html_is_valid(value)

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}
