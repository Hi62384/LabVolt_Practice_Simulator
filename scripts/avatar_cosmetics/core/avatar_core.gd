extends RefCounted
## JSON-only shared appearance validation. No save writes, purchases or scene loading.
const VERSION := 1
const BODY_MIN := .65
const BODY_MAX := 1.4
const BODY_FIELDS := ["height","width","head","head_width","head_height","neck_length","neck_width","shoulders","torso_length","torso_width","waist","hips","arm_length","arm_width","hands","leg_length","leg_width","feet"]
const SLOTS := ["face","hair","facial_hair","top_inner","top_outer","bottom","footwear","head","eyewear","ears","neck","hands","wrist_left","wrist_right","back"]
const CATEGORIES := ["faces","hair","facial_hair","tops","bottoms","shoes","accessories"]
const STARTER_LOOK := {
	"faces": "faces.friendly", "hair": "hair.crop", "facial_hair": "facial_hair.clean",
	"tops": "tops.harbor_fitted_tee", "bottoms": "bottoms.indigo_straight_jeans",
	"shoes": "shoes.velocity_runner",
}
const TOP_SLOTS := ["top_inner", "top_outer"]

static func sanitize_body(raw: Dictionary) -> Dictionary:
	var result := {}
	for key in BODY_FIELDS:
		var value = raw.get(key,1.0)
		result[key]=clampf(float(value),BODY_MIN,BODY_MAX) if (value is float or value is int) and is_finite(float(value)) else 1.0
	result.build=raw.get("build","average") if raw.get("build","average") in ["slim","average","heavy","muscular"] else "average"
	result.skin=_color(raw.get("skin","deb08c"),"deb08c")
	return result

static func _color(value: Variant,fallback: String) -> String:
	if value is String and value.length()==6 and Color.html_is_valid(value):return value.to_lower()
	return fallback

static func validate_definition(item: Dictionary) -> Array:
	var errors: Array=[]
	for key in ["id","name","scene","thumbnail"]:
		if not item.get(key) is String or str(item.get(key,"")).is_empty():errors.append("Missing "+key)
	if not item.get("category") in CATEGORIES:errors.append("Invalid category")
	if not item.get("slot") in SLOTS:errors.append("Invalid slot")
	var allowed := {"faces":["face"],"hair":["hair"],"facial_hair":["facial_hair"],"tops":["top_inner","top_outer"],"bottoms":["bottom"],"shoes":["footwear"],"accessories":["head","eyewear","ears","neck","hands","wrist_left","wrist_right","back"]}
	if allowed.has(item.get("category")) and not item.get("slot") in allowed[item.category]:errors.append("Category does not match slot")
	for key in ["tags","conflicts"]:
		var values = item.get(key,[])
		if not values is Array:errors.append("Invalid "+key)
		else:
			for value in values:
				if not value is String or value.length()>128:errors.append("Invalid "+key+" value")
	if item.get("rig")!="labvolt_toon_v1":errors.append("Unsupported rig")
	if not item.get("price",0) is int or int(item.get("price",0))<0:errors.append("Invalid price")
	for key in ["scene","thumbnail"]:
		if not str(item.get(key,"")).begins_with("res://") or ".." in str(item.get(key,"")):errors.append("Invalid resource "+key)
	if not item.get("parameters",{}) is Dictionary:errors.append("Invalid parameters");return errors
	for key in item.get("parameters",{}):
		var spec = item.parameters[key]
		if not spec is Dictionary:errors.append("Invalid parameter "+str(key));continue
		if not spec.get("type") in ["float","int","bool","color","enum"]:errors.append("Invalid parameter type "+str(key))
		if not spec.has("default"):errors.append("Missing parameter default "+str(key))
		if spec.get("type")=="color" and _color(spec.get("default"),"")=="":errors.append("Invalid color default "+str(key))
		if spec.get("type")=="bool" and not spec.get("default") is bool:errors.append("Invalid boolean default "+str(key))
		if spec.get("type") in ["float","int"]:
			for bound in ["min","max","default"]:
				var value = spec.get(bound)
				if not (value is float or value is int) or not is_finite(float(value)):errors.append("Invalid numeric parameter "+str(key))
			if (spec.get("min") is float or spec.get("min") is int) and (spec.get("max") is float or spec.get("max") is int):
				if spec.min>spec.max:errors.append("Reversed range "+str(key))
		if spec.get("type")=="enum" and (not spec.get("values") is Array or not spec.get("default") in spec.get("values",[])):errors.append("Invalid enum "+str(key))
	return errors

static func sanitize_parameters(item: Dictionary,raw: Dictionary) -> Dictionary:
	var result := {}
	if not validate_definition(item).is_empty():return result
	for key in item.get("parameters",{}):
		var spec: Dictionary=item.parameters[key]
		var value = raw.get(key,spec.default)
		match spec.type:
			"float","int":
				if not (value is float or value is int) or not is_finite(float(value)):value=spec.default
				value=clampf(float(value),float(spec.min),float(spec.max))
				result[key]=int(value) if spec.type=="int" else value
			"bool":result[key]=value==true
			"color":result[key]=_color(value,str(spec.default))
			"enum":result[key]=value if value in spec.values else spec.default
	return result

static func resolve(catalog: Dictionary,raw: Dictionary,owned: Array) -> Dictionary:
	var body = raw.get("body",{})
	var equipped = raw.get("equipped",{})
	var state := {"version":VERSION,"body":sanitize_body(body if body is Dictionary else {}),"equipped":{}}
	var errors: Array=[]
	var accepted: Array=[]
	if not equipped is Dictionary:return {"state":state,"errors":["Invalid equipment state"]}
	for slot in equipped:
		if not slot in SLOTS:errors.append("Unknown equipment slot: "+str(slot))
	for slot in SLOTS:
		# Existing dual-top saves keep the outer garment they previously wore.
		if slot == "top_inner" and equipped.get("top_outer") is Dictionary:
			var outer: Variant = catalog.get(equipped.top_outer.get("id", ""))
			if outer is Dictionary and outer.get("slot") == "top_outer" and outer.id in owned:
				continue
		var entry = equipped.get(slot)
		if not entry is Dictionary:continue
		var id: String=str(entry.get("id",""))
		if not catalog.has(id) or not id in owned:errors.append("Unknown or unowned item: "+id);continue
		var item = catalog[id]
		if not item is Dictionary or not validate_definition(item).is_empty() or item.slot!=slot:errors.append("Invalid item slot: "+id);continue
		var conflict := false
		for other in accepted:
			for tag in item.get("tags",[]):
				if tag in other.get("conflicts",[]):conflict=true
			for tag in other.get("tags",[]):
				if tag in item.get("conflicts",[]):conflict=true
		if conflict:errors.append("Incompatible item: "+id);continue
		var parameters = entry.get("parameters",{})
		state.equipped[slot]={"id":id,"parameters":sanitize_parameters(item,parameters if parameters is Dictionary else {})}
		accepted.append(item)
	return {"state":state,"errors":errors}

static func equip(state: Dictionary, item: Dictionary, parameters: Dictionary) -> void:
	if item.slot in TOP_SLOTS:
		for slot in TOP_SLOTS:
			if slot != item.slot:
				state.equipped.erase(slot)
	state.equipped[item.slot] = {"id": item.id, "parameters": parameters.duplicate(true)}

static func seed_equipment(catalog: Dictionary, state: Dictionary, owned: Array, legacy: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	if not next.get("equipped", {}) is Dictionary:
		return next
	next.equipped = next.get("equipped", {})
	if next.get("body", {}).is_empty() and not legacy.is_empty():
		var body := {}
		for field in BODY_FIELDS:
			var old: String = {"width":"build", "head_width":"face_width", "head_height":"face_height", "hands":"hand_size", "feet":"shoe_size"}.get(field, field)
			body[field] = legacy.get(old, 1.0)
		body.skin = legacy.get("skin", "deb08c")
		next.body = sanitize_body(body)
	if next.equipped.get("top_inner") is Dictionary and next.equipped.get("top_outer") is Dictionary:
		var outer: Variant = catalog.get(next.equipped.top_outer.get("id", ""))
		if outer is Dictionary and outer.get("slot") == "top_outer" and outer.id in owned:
			next.equipped.erase("top_inner")
	for category in STARTER_LOOK:
		var id: String = STARTER_LOOK[category]
		if not catalog.has(id) or id not in owned:
			continue
		var item: Dictionary = catalog[id]
		var present: bool = next.equipped.values().any(func(entry):
			return entry is Dictionary and catalog.get(entry.get("id", ""), {}).get("category") == category)
		if not present and not next.equipped.has(item.slot):
			equip(next, item, sanitize_parameters(item, {}))
	return next

static func starter_ids(catalog: Dictionary) -> Array:
	var result: Array=[]
	for id in catalog:
		if catalog[id] is Dictionary and catalog[id].get("starter",false) and validate_definition(catalog[id]).is_empty():result.append(id)
	result.sort()
	return result
