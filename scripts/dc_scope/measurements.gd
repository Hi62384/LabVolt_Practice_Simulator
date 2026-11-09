extends RefCounted
const Settings = preload("res://scripts/dc_scope/settings.gd")
# Instrument math only: never evaluates circuit connectivity or generates waveforms.
static func voltage(row: Array, channel: int, setting: Dictionary) -> float:
	var column := channel+1
	if setting.get("coupling","DC")=="AC" and row.size()>=7: column=channel+5
	return float(row[column])*float(setting.get("attenuation",1.0))
static func window(samples: Array, start: float, span: float) -> Array:
	var result: Array=[]
	for row in samples:
		if row is Array and row.size()>=3 and float(row[0])>=start and float(row[0])<=start+span: result.append(row)
	return result
static func raw_mean(samples: Array, channel: int) -> float:
	if samples.is_empty(): return 0.0
	var total := 0.0; var duration := 0.0
	for i in range(1,samples.size()):
		var dt := float(samples[i][0])-float(samples[i-1][0])
		if dt<=0: continue
		total+=(float(samples[i][channel+1])+float(samples[i-1][channel+1]))*.5*dt; duration+=dt
	return total/duration if duration>0 else float(samples[0][channel+1])
static func statistics(samples: Array, channel: int, raw_setting: Dictionary) -> Dictionary:
	var result := {"count":0,"average":0.0,"rms":0.0,"ac_rms":0.0,"dc_offset":0.0,"vpp":0.0,"frequency":0.0,"frequency_valid":false,"sample_rate":0.0,"max_gap":0.0,"warning":"","minimum":0.0,"maximum":0.0}
	if channel<0 or channel>=2: result.warning="Invalid channel"; return result
	var usable: Array=[]
	for row in samples:
		if not row is Array or row.size()<3: continue
		if not Settings.finite_number(row[0]) or not Settings.finite_number(row[channel+1]): continue
		if row.size()>=7 and not Settings.finite_number(row[channel+5]): continue
		if not usable.is_empty() and float(row[0])<=float(usable[-1][0]): continue
		usable.append(row)
	result.count=usable.size()
	if usable.is_empty(): result.warning="No acquired samples"; return result
	if raw_setting.get("coupling","DC")=="AC" and usable[0].size()<7:
		result.warning="Legacy record: AC coupling uses captured-window DC removal"
	var fallback_mean := 0.0
	if raw_setting.get("coupling","DC")=="AC" and usable[0].size()<7:
		fallback_mean=raw_mean(usable,channel)
	var values: Array=[]
	for row in usable:
		values.append(voltage(row,channel,raw_setting)-fallback_mean*float(raw_setting.get("attenuation",1.0)))
	var low: float=values.min(); var high: float=values.max()
	result.minimum=low; result.maximum=high; result.vpp=high-low
	if usable.size()==1:
		result.average=values[0]; result.rms=absf(values[0]); result.dc_offset=float(usable[0][channel+1])*float(raw_setting.get("attenuation",1.0)); result.warning="Insufficient time samples"; return result
	var integral := 0.0; var square := 0.0; var raw_integral := 0.0
	var duration: float=float(usable[-1][0])-float(usable[0][0])
	for i in range(1,usable.size()):
		var dt := float(usable[i][0])-float(usable[i-1][0]); result.max_gap=maxf(result.max_gap,dt)
		integral+=(float(values[i])+float(values[i-1]))*.5*dt
		square+=(float(values[i])*float(values[i])+float(values[i-1])*float(values[i-1]))*.5*dt
		raw_integral+=(float(usable[i][channel+1])+float(usable[i-1][channel+1]))*.5*dt
	result.average=integral/duration; result.rms=sqrt(maxf(0.0,square/duration)); result.ac_rms=sqrt(maxf(0.0,square/duration-result.average*result.average))
	result.dc_offset=raw_integral/duration*float(raw_setting.get("attenuation",1.0)); result.sample_rate=(usable.size()-1)/duration
	var crossings: Array=[]
	for i in range(1,usable.size()):
		var a := float(values[i-1]); var b := float(values[i]); var level: float=result.average
		if a<level and b>=level and b>a:
			crossings.append(lerpf(float(usable[i-1][0]),float(usable[i][0]),(level-a)/(b-a)))
	if crossings.size()>=2 and high-low>1e-8:
		result.frequency=(crossings.size()-1)/(float(crossings[-1])-float(crossings[0]))
		result.frequency_valid=result.frequency*result.max_gap<=0.25
		if not result.frequency_valid: result.warning="Under-resolved: fewer than 4 samples per measured cycle"; result.frequency=0.0
	elif result.warning.is_empty(): result.warning="Need two rising crossings for frequency"
	return result
static func point(row: Array, index: int, channel: Dictionary, start: float, span: float, dimensions: Vector2, legacy_offset := 0.0) -> Vector2:
	var volts := voltage(row,index,channel)-legacy_offset*float(channel.attenuation)
	return Vector2((float(row[0])-start)/span*dimensions.x,dimensions.y*.5-(volts/float(channel.scale)+float(channel.position))*dimensions.y/8.0)
