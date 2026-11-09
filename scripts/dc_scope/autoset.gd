extends RefCounted
const Settings = preload("res://scripts/dc_scope/settings.gd")
const Measure = preload("res://scripts/dc_scope/measurements.gd")
static func actions(samples: Array, raw_settings: Dictionary) -> Array:
	var settings := Settings.normalize(raw_settings); var result: Array=[]
	var source: int=settings.source
	if not settings.channels[source].enabled:
		for i in 2:
			if settings.channels[i].enabled: source=i; break
	if not settings.channels[source].enabled:
		result.append({"op":"scope","channel":source,"key":"enabled","value":true})
	result.append({"op":"scope","key":"source","value":source})
	for index in 2:
		if not settings.channels[index].enabled and index!=source: continue
		var stats := Measure.statistics(samples,index,settings.channels[index])
		if stats.count<2: continue
		var scale := clampf(maxf(float(stats.vpp)/6.0,absf(float(stats.average))/3.5),0.001,1000.0)
		result.append({"op":"scope","channel":index,"key":"scale","value":scale})
		result.append({"op":"scope","channel":index,"key":"position","value":clampf(-float(stats.average)/scale,-4,4)})
		if index==source:
			result.append({"op":"scope","key":"trigger","value":float(stats.average)})
			if stats.frequency_valid: result.append({"op":"scope","key":"timebase","value":clampf(0.2/float(stats.frequency),0.0001,2.0)})
	result.append({"op":"scope","key":"running","value":true})
	return result
