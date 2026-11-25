extends RefCounted
static func path(identity: String, document_uid := "") -> String:
	var identity_key := identity.sha256_text().left(24)
	return "user://notebook_"+identity_key+("_"+document_uid.sha256_text().left(32) if not document_uid.is_empty() else "")+".cfg"

static func read(identity: String, document_uid := "") -> Dictionary:
	var file_path := path(identity,document_uid)
	for file in [file_path,file_path+".bak"]:
		var cfg := ConfigFile.new()
		if cfg.load(file)==OK:
			var data=cfg.get_value("notebook","content",{})
			if valid(data):
				if not data.has("document_uid"):
					data.document_uid = (identity + ":legacy notebook").sha256_text().left(32) if document_uid.is_empty() else document_uid
				if document_uid.is_empty() or data.document_uid==document_uid:return data
	return {}
static func write(identity: String,data: Dictionary,document_uid := "") -> bool:
	if not valid(data) or (not document_uid.is_empty() and data.get("document_uid","")!=document_uid):return false
	var file := path(identity,document_uid);var cfg := ConfigFile.new();cfg.set_value("notebook","content",data)
	if cfg.save(file+".tmp")!=OK:return false
	if FileAccess.file_exists(file):
		if DirAccess.copy_absolute(file,file+".bak")!=OK:return false
	return DirAccess.rename_absolute(file+".tmp",file)==OK
static func valid(data: Variant) -> bool:
	if not data is Dictionary or var_to_bytes(data).size()>2000000:return false
	if data.has("document_uid") and (not data.document_uid is String or data.document_uid.length() != 32 or not data.document_uid.is_valid_hex_number(false)):return false
	for key in ["strokes","annotations"]:
		if not data.get(key,{}) is Dictionary:return false
		for page in data.get(key,{}):
			if not str(page).is_valid_int() or int(page) not in range(100):return false
			var entries=data[key][page]
			if not entries is Array or (key=="annotations" and entries.size()>40):return false
			for entry in entries:
				if not entry is Dictionary or not Color.html_is_valid(str(entry.get("color",""))):return false
				if key=="strokes":
					if not entry.get("points") is Array or entry.points.size()>1024:return false
					if not is_finite(float(entry.get("width",0))) or float(entry.get("width",0))<1 or float(entry.get("width",0))>32:return false
					for point in entry.points:
						if not valid_point(point):return false
				else:
					if not valid_annotation_position(entry.get("position")):return false
					if entry.get("kind") not in ["text","equation"] or entry.get("font") not in ["Sans","Serif","Mono"]:return false
					if str(entry.get("text","")).length()>256 or str(entry.get("id","")).length()>40:return false
					if not is_finite(float(entry.get("font_size",0))) or int(entry.get("font_size",0)) not in range(10,97):return false
					if not is_finite(float(entry.get("angle",0))) or absf(float(entry.get("angle",0)))>PI:return false
					if str(entry.get("align","left")) not in ["left","center","right"]:return false
					if not is_finite(float(entry.get("opacity",1.0))) or float(entry.get("opacity",1.0))<0.05 or float(entry.get("opacity",1.0))>1:return false
					if not is_finite(float(entry.get("box_width",280.0))) or float(entry.get("box_width",280.0))<40 or float(entry.get("box_width",280.0))>720:return false
					var box_height := float(entry.get("box_height",0.0))
					if not is_finite(box_height) or box_height<0.0 or box_height>720.0:return false
	return true
static func valid_annotation_position(point: Variant) -> bool:
	# Rotation about the handle can move the text origin across the page edge.
	return point is Vector2 and point.is_finite() and Rect2(-4,-4,9,9).has_point(point)
static func valid_point(point: Variant) -> bool:
	return point is Vector2 and point.is_finite() and point.x>=0 and point.y>=0 and point.x<=1 and point.y<=1
