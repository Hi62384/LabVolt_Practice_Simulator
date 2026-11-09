extends RefCounted
## Call ONLY at Session's successful host act boundary, using real before/after state.
## Returns empty for rejected/no-op/unsupported operations. Never infers an actor.
static func project(peer: int, station: int, action: Dictionary, before: Dictionary, after: Dictionary, positions: Dictionary, sequence: int) -> Dictionary:
	var op = str(action.get("op",""))
	var result = {"peer":peer,"station":station,"sequence":sequence,"revision":int(after.get("revision",0)),"kind":"","target":Vector3.ZERO,"turn":0.0,"cable":-1,"end":-1}
	var key = ""
	if op in ["plug","unplug","undo"]:
		for old in before.get("cables",[]):
			var fresh = cable(after,int(old["id"]))
			if fresh.is_empty():
				continue
			for end in [0,1]:
				var field = "a" if end == 0 else "b"
				var was = str(old[field])
				var now = str(fresh[field])
				if was == now:
					continue
				if op == "plug" and was == "" and now != "" and int(old["owner"]) == peer:
					result["kind"] = "insert"
					key = now
				elif op in ["unplug","undo"] and was != "" and now == "" and int(fresh["owner"]) == peer:
					result["kind"] = "remove"
					key = was
				else:
					continue
				result["cable"] = int(old["id"])
				result["end"] = end
	elif op == "switch":
		var kind = str(action.get("kind",""))
		var index = int(action.get("index",-1))
		var old = before.get("switches",{}).get(kind,[])
		var fresh = after.get("switches",{}).get(kind,[])
		if index < 0 or index >= old.size() or index >= fresh.size() or old[index] == fresh[index]:
			return {}
		key = "%s_%d" % [kind,index]
		result["kind"] = "switch"
		result["turn"] = 1.0 if fresh[index] else -1.0
	elif op in ["voltage","frequency","dyn_load","supply_meter"]:
		var field = "level" if op == "voltage" else op
		if float(before.get(field,0.0)) == float(after.get(field,0.0)):
			return {}
		key = "variable" if op in ["voltage","frequency"] else op
		result["kind"] = "knob"
		result["turn"] = clampf(sign(float(after[field])-float(before[field]))*0.45,-0.45,0.45)
	elif op in ["power","dyn_measure","igbt_damping"]:
		var field = "powered" if op == "power" else op
		if before.get(field,false) == after.get(field,false):
			return {}
		key = op
		result["kind"] = "switch"
		result["turn"] = 1.0 if after[field] else -1.0
	elif op in ["pickup","unstash","grab"]:
		for fresh in after.get("cables",[]):
			if int(fresh["owner"]) == peer:
				var old = cable(before,int(fresh["id"]))
				if not old.is_empty() and int(old["owner"]) == peer:
					continue
				result["kind"] = "grasp"
				result["cable"] = int(fresh["id"])
				result["end"] = 0 if fresh["a"] == "" else 1
				# Grasp remains at the carried anchor, not an invented storage target.
				return result
	if result["kind"] == "" or not positions.has(key):
		return {}
	var target = positions[key]
	if not target is Vector3 or not target.is_finite():
		return {}
	result["port"] = key
	result["target"] = target
	return result

static func cable(snapshot: Dictionary, id: int) -> Dictionary:
	for item in snapshot.get("cables",[]):
		if int(item["id"]) == id:
			return item
	return {}
