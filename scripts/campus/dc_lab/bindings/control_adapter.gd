extends RefCounted
## Pure action construction. Caller MUST route through dc_lab.request(station, action).
const MODES = ["DC V","AC V","DC A","AC A","Resistance","Continuity","Diode","Capacitance","Frequency","Duty"]
const WAVES = ["Sine","Square","Triangle","Sawtooth","Pulse","DC"]
const RANGES = [0.0,.0002,.002,.02,.2,2.0,20.0,200.0]
const GEN = {"frequency":[.1,100.0,.1],"amplitude":[0.0,10.0,.1],"offset":[-10.0,10.0,.1],"phase":[0.0,360.0,1.0],"duty":[.05,.95,.01],"resistance":[1.0,1000.0,1.0]}

static func action(spec: Dictionary, state: Dictionary, reverse := false) -> Dictionary:
	var direction := -1 if reverse else 1
	var op := str(spec.get("op",""))
	var key := str(spec.get("key",""))
	var index := int(spec.get("index",-1))
	match op:
		"master","fuse":return {"op":op}
		"channel":
			if index<0 or index>=3:return {}
			var channel: Dictionary=state.channels[index]
			if key=="enabled":return {"op":op,"index":index,"key":key,"value":not bool(channel.enabled)}
			if key not in ["voltage","limit"]:return {}
			return {"op":op,"index":index,"key":key,"value":clampf(float(channel[key])+direction*(.1 if key=="voltage" else .01),0.0 if key=="voltage" else .001,30.0 if key=="voltage" else 1.0)}
		"generator":
			var generator: Dictionary=state.generator
			if key=="enabled":return {"op":op,"key":key,"value":not bool(generator.enabled)}
			if key=="wave":return {"op":op,"key":key,"value":_cycle(WAVES,generator.wave,direction)}
			if not GEN.has(key):return {}
			var bounds: Array=GEN[key]
			return {"op":op,"key":key,"value":clampf(float(generator[key])+direction*float(bounds[2]),float(bounds[0]),float(bounds[1]))}
		"meter_mode_next":return {"op":"meter","mode":_cycle(MODES,state.meter_mode,direction)}
		"meter_range_next":return {"op":"meter_range","value":_cycle(RANGES,float(state.get("meter_range",0)),direction)}
		"current_source":
			if index<0 or index>=4:return {}
			var source: Dictionary=state.current_sources[index]
			if key=="enabled":return {"op":op,"index":index,"key":key,"value":not bool(source.enabled)}
			if key not in ["current","compliance"]:return {}
			return {"op":op,"index":index,"key":key,"value":clampf(float(source[key])+direction*(.001 if key=="current" else .1),-1.0 if key=="current" else .1,1.0 if key=="current" else 30.0)}
		"scope":return _scope(spec,state,direction)
	return {}

static func _cycle(values: Array, current: Variant, direction: int) -> Variant:
	return values[posmod(maxi(values.find(current),0)+direction,values.size())]

static func _scope(spec: Dictionary,state: Dictionary,direction: int) -> Dictionary:
	var settings: Dictionary=preload("res://scripts/dc_scope/settings.gd").normalize(state.get("scope",{}))
	var key := str(spec.get("key",""))
	var index := int(spec.get("channel",-1))
	if index < -1 or index > 1:return {}
	if index>=0 and key not in ["enabled","scale","position","coupling","attenuation"]:return {}
	if index<0 and key in ["enabled","position"]:return {}
	var result := {"op":"scope","key":key}
	if index>=0:
		if index>1:return {}
		result.channel=index
	var source: Dictionary=settings.channels[index] if index>=0 else settings
	match key:
		"running","enabled":result.value=not bool(source.get(key,false))
		"single","autoset":result.value=true
		"timebase":result.value=clampf(float(settings.timebase)*pow(2.0,direction),.0001,2.0)
		"scale":result.value=clampf(float(source.scale)*pow(2.0,direction),.001 if index>=0 else .01,1000.0 if index>=0 else 20.0)
		"trigger":result.value=clampf(float(settings.trigger)+direction*.01,-10000,10000)
		"position":
			if index<0:return {}
			result.value=clampf(float(source.position)+direction*.1,-4,4)
		"source":result.value=1-int(settings.source)
		"edge":result.value=_cycle(["Rising","Falling"],settings.edge,direction)
		"trigger_mode":result.value=_cycle(["Auto","Normal"],settings.trigger_mode,direction)
		"coupling":result.value=_cycle(["DC","AC"],source.coupling,direction)
		"attenuation":result.value=_cycle([1.0,10.0,100.0] if index>=0 else [1.0,10.0],float(source.attenuation),direction)
		_:return {}
	return result

static func readings(state: Dictionary) -> Dictionary:
	var values := {"meter":str(state.get("meter","—")),"master":bool(state.get("master",false)),"generator":state.get("generator",{}).duplicate(true),"scope":state.get("scope",{}).duplicate(true),"samples":state.get("samples",[]),"scope_acquisition":state.get("scope_acquisition",{}),"scope_probe":state.get("scope_probe",{})}
	var solved: Dictionary=state.get("result",{})
	values.error="" if solved.get("ok",true) else str(solved.get("error","Solve failed"))
	for i in 3:
		var id := "s%d"%i
		var voltage := float(solved.get("drop",{}).get(id,0))
		var current := -float(solved.get("i",{}).get(id,0))
		values[id]={"voltage":voltage,"current":current,"power":voltage*current,"mode":str(solved.get("mode",{}).get(id,"OFF")),"setpoint":state.channels[i].duplicate(true)}
	return values
