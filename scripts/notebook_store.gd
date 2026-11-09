extends RefCounted
static func path(identity: String) -> String:return "user://notebook_"+identity.sha256_text().left(24)+".cfg"
static func read(identity: String) -> Dictionary:
	for file in [path(identity),path(identity)+".bak"]:
		var cfg := ConfigFile.new()
		if cfg.load(file)==OK:
			var data=cfg.get_value("notebook","content",{})
			if valid(data):return data
	return {}
static func write(identity: String,data: Dictionary) -> void:
	if not valid(data):return
	var file := path(identity);var cfg := ConfigFile.new();cfg.set_value("notebook","content",data)
	if cfg.save(file+".tmp")!=OK:return
	if FileAccess.file_exists(file):
		if DirAccess.copy_absolute(file,file+".bak")!=OK:return
	DirAccess.rename_absolute(file+".tmp",file)
static func valid(data: Variant) -> bool:
	if not data is Dictionary or var_to_bytes(data).size()>2000000:return false
	for key in ["strokes","annotations"]:
		if not data.get(key,{}) is Dictionary:return false
		for page in data.get(key,{}):
			if not str(page).is_valid_int() or int(page) not in range(100):return false
			var entries=data[key][page]
			if not entries is Array or entries.size()>(100 if key=="strokes" else 40):return false
			for entry in entries:
				if not entry is Dictionary or not Color.html_is_valid(str(entry.get("color",""))):return false
				if key=="strokes":
					if not entry.get("points") is Array or entry.points.size()>256:return false
					if not is_finite(float(entry.get("width",0))) or float(entry.get("width",0))<1 or float(entry.get("width",0))>32:return false
					for point in entry.points:
						if not valid_point(point):return false
				else:
					if not valid_point(entry.get("position")):return false
					if entry.get("kind") not in ["text","equation"] or entry.get("font") not in ["Sans","Serif","Mono"]:return false
					if str(entry.get("text","")).length()>256 or str(entry.get("id","")).length()>40:return false
					if not is_finite(float(entry.get("font_size",0))) or int(entry.get("font_size",0)) not in range(10,97):return false
					if not is_finite(float(entry.get("angle",0))) or absf(float(entry.get("angle",0)))>PI:return false
					if str(entry.get("align","left")) not in ["left","center","right"]:return false
					if not is_finite(float(entry.get("opacity",1.0))) or float(entry.get("opacity",1.0))<0.05 or float(entry.get("opacity",1.0))>1:return false
					if not is_finite(float(entry.get("box_width",280.0))) or float(entry.get("box_width",280.0))<40 or float(entry.get("box_width",280.0))>720:return false
	return true
static func valid_point(point: Variant) -> bool:
	return point is Vector2 and point.is_finite() and point.x>=0 and point.y>=0 and point.x<=1 and point.y<=1
