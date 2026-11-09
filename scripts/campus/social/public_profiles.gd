extends RefCounted
# Host-side projection only. Never serialize the source dictionary.
const FIELDS := {"appearance": ["hair", "outfit", "top", "pants", "skin", "hair_color", "eye_color", "accent", "shoes", "hat", "glasses", "expression", "earrings", "beard", "watch", "gloves"], "kit": ["name", "capacity", "equipped"], "parts": ["count", "items"], "money": ["dollars"], "course": ["course_id", "lecture", "lab", "overall"], "gym": ["level", "xp", "record"], "emotes": ["equipped", "unlocked"]}
static func clean_name(value: String) -> String:
	var result := ""
	for ch in value.strip_edges():
		if ch.unicode_at(0)>=32 and ch.unicode_at(0)!=127 and ch not in ["[", "]", "<", ">"]: result+=ch
	return result.substr(0,24).strip_edges() if not result.is_empty() else "Student"
static func project(identity: String, display_name: String, source: Dictionary, visibility: Dictionary) -> Dictionary:
	var output := {"id": identity.substr(0,128), "name": clean_name(display_name)}
	for section in FIELDS:
		if not bool(visibility.get(section,false)): continue
		var data: Variant=source.get(section,{})
		if not data is Dictionary: continue
		var safe := {}
		for key in FIELDS[section]:
			var value: Variant=data.get(key)
			if value is String: safe[key]=value.substr(0,96)
			elif value is int: safe[key]=clampi(value,-1000000000,1000000000)
			elif value is float and is_finite(value): safe[key]=clampf(value,-1e9,1e9)
			elif value is bool: safe[key]=value
			elif section=="parts" and key=="items" and value is Array:
				var items: Array=[]
				for item in value.slice(0,64):
					if item is Dictionary and item.get("id","") is String and item.get("name","") is String and item.get("count",0) is int: items.append({"id":item.get("id","").substr(0,64),"name":item.get("name","").substr(0,64),"count":clampi(item.get("count",0),0,1000000)})
				safe[key]=items
			elif section=="emotes" and key=="unlocked" and value is Array:
				var emotes: Array=[]
				for item in value.slice(0,32):
					if item is String: emotes.append(item.substr(0,48))
				safe[key]=emotes
		output[section]=safe
	return output
static func delta(previous: Dictionary, current: Dictionary, revision: int) -> Dictionary:
	var set_fields := {}
	var removed: Array=[]
	for key in current:
		if previous.get(key)!=current[key]: set_fields[key]=current[key]
	for key in previous:
		if not current.has(key): removed.append(key)
	return {"id":current.get("id",""),"revision":revision,"set":set_fields,"remove":removed}
static func apply_delta(previous: Dictionary, update: Dictionary) -> Dictionary:
	if str(previous.get("id",update.get("id","")))!=str(update.get("id","")): return previous.duplicate(true)
	if int(update.get("revision",0))<=int(previous.get("revision",-1)): return previous.duplicate(true)
	var merged := previous.duplicate(true)
	for key in update.get("remove",[]): merged.erase(key)
	for key in update.get("set",{}): merged[key]=update["set"][key]
	# Re-project received data: even malformed transport cannot inject hidden fields.
	var visibility := {}
	for key in FIELDS: visibility[key]=merged.has(key)
	var safe := project(str(update.get("id","")),str(merged.get("name","Student")),merged,visibility)
	safe["revision"]=int(update.get("revision",0))
	return safe
