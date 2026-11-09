extends RefCounted
const VERSION := 2
const CHANNELS := 2
const AC_CUTOFF_HZ := 0.5
static func defaults() -> Dictionary:
	return {"schema":VERSION,"channels":[{"enabled":true,"position":0.0,"scale":2.0,"coupling":"DC","attenuation":1.0},{"enabled":true,"position":0.0,"scale":2.0,"coupling":"DC","attenuation":1.0}],"running":true,"single":false,"armed":false,"trigger":0.0,"edge":"Rising","source":0,"trigger_mode":"Auto","timebase":0.01,"pretrigger":0.25,"scale":2.0,"coupling":"DC","attenuation":1.0}
static func finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
static func normalize(raw: Dictionary) -> Dictionary:
	var result := defaults()
	for key in ["running","single","armed"]:
		if raw.get(key) is bool: result[key]=raw[key]
	for key in ["edge","trigger_mode"]:
		var choices: Array=["Rising","Falling"] if key=="edge" else ["Auto","Normal"]
		if raw.get(key) in choices: result[key]=raw[key]
	for key in ["timebase","trigger","pretrigger","source"]:
		if finite_number(raw.get(key)):
			var bounds: Array={"timebase":[0.0001,2.0],"trigger":[-10000.0,10000.0],"pretrigger":[0.0,0.75],"source":[0.0,1.0]}[key]
			result[key]=clampf(float(raw[key]),bounds[0],bounds[1])
	result.source=int(result.source)
	var supplied: Variant=raw.get("channels",[])
	for index in CHANNELS:
		var channel: Dictionary=result.channels[index]
		var candidate: Dictionary=supplied[index] if supplied is Array and supplied.size()>index and supplied[index] is Dictionary else raw
		if candidate.get("enabled") is bool: channel.enabled=candidate.enabled
		if candidate.get("coupling") in ["AC","DC"]: channel.coupling=candidate.coupling
		for key in ["position","scale","attenuation"]:
			if not finite_number(candidate.get(key)): continue
			var bounds: Array={"position":[-4.0,4.0],"scale":[0.001,1000.0],"attenuation":[1.0,100.0]}[key]
			channel[key]=clampf(float(candidate[key]),bounds[0],bounds[1])
	if not result.running: result.single=false; result.armed=false
	return mirror(result)
static func mirror(settings: Dictionary) -> Dictionary:
	for key in ["scale","coupling","attenuation"]: settings[key]=settings.channels[0][key]
	return settings
static func change(raw: Dictionary, action: Dictionary) -> Dictionary:
	var settings := normalize(raw)
	var key := str(action.get("key","")); var value: Variant=action.get("value")
	var indexed := action.has("channel")
	if indexed:
		if not action.channel is int or int(action.channel)<0 or int(action.channel)>=CHANNELS: return {"ok":false,"error":"Invalid scope channel."}
		if key not in ["enabled","position","scale","coupling","attenuation"]: return {"ok":false,"error":"Unknown channel control."}
	if key in ["enabled","running","single"]:
		if not value is bool: return {"ok":false,"error":"Scope switch requires true or false."}
	elif key in ["position","scale","attenuation","timebase","trigger","source","pretrigger"]:
		if not finite_number(value): return {"ok":false,"error":"Scope value must be finite."}
		if key=="source" and (float(value)!=floorf(float(value)) or int(value) not in [0,1]): return {"ok":false,"error":"Invalid trigger source."}
	elif key=="coupling":
		if value not in ["AC","DC"]: return {"ok":false,"error":"Invalid coupling."}
	elif key=="edge":
		if value not in ["Rising","Falling"]: return {"ok":false,"error":"Invalid trigger edge."}
	elif key=="trigger_mode":
		if value not in ["Auto","Normal"]: return {"ok":false,"error":"Invalid trigger mode."}
	else: return {"ok":false,"error":"Unknown scope control."}
	if indexed: settings.channels[int(action.channel)][key]=value
	elif key in ["scale","coupling","attenuation"]:
		# Legacy global controls retain their historical effect on both traces.
		for channel in settings.channels: channel[key]=value
	elif key in ["position","enabled"]: return {"ok":false,"error":"Choose a channel for this control."}
	elif key=="single":
		settings.running=true; settings.single=value; settings.armed=value
	elif key=="running":
		settings.running=value; settings.single=false; settings.armed=false
	else: settings[key]=value
	return {"ok":true,"settings":normalize(settings),"error":""}
