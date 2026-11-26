extends RefCounted

const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
const MAX_ROWS:=2048
const COUNT_FIELDS:=["input","output","cached","reasoning","write_30m","write_12h","text_input","image_input","image_output","text_cached","image_cached","characters"]
var rows: Dictionary={}

static func _measure(source: Dictionary, names: Array) -> Dictionary:
	var result:={}
	for name in names:
		var value: Variant=source.get(name)
		if (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=2000000000:
			result[name]=int(value)
	return result

static func usage_from(response: Dictionary,seconds := -1.0,characters := -1) -> Dictionary:
	var raw: Variant=response.get("usage",{})
	var usage: Dictionary=raw if raw is Dictionary else {}
	var result:={}
	var primary:={"input_tokens":"input","prompt_tokens":"input","output_tokens":"output","completion_tokens":"output"}
	for key in _measure(usage,primary.keys()):result[primary[key]]=int(usage[key])
	var input: Variant=usage.get("input_tokens_details",usage.get("prompt_tokens_details",{}))
	var output: Variant=usage.get("output_tokens_details",usage.get("completion_tokens_details",{}))
	var detail:={"cached_tokens":"cached","text_tokens":"text_input","image_tokens":"image_input","cached_text_tokens":"text_cached","cached_image_tokens":"image_cached","cache_write_30m_tokens":"write_30m","cache_write_12h_tokens":"write_12h"}
	if input is Dictionary:
		for key in _measure(input,detail.keys()):result[detail[key]]=int(input[key])
	if output is Dictionary:
		if _measure(output,["reasoning_tokens"]).has("reasoning_tokens"):result.reasoning=int(output.reasoning_tokens)
		if _measure(output,["image_tokens"]).has("image_tokens"):result.image_output=int(output.image_tokens)
	var duration: Variant=usage.get("seconds",seconds)
	if (duration is int or duration is float) and is_finite(float(duration)) and duration>=0:result.seconds=float(duration)
	if characters>=0:result.characters=characters
	return result

func record(context: Dictionary, measurement: Dictionary, successful: bool, latency_ms: int) -> Dictionary:
	var signature:=JSON.stringify([context.profile,context.model,context.get("snapshot",""),context.purpose,context.effort,context.mode,context.tier,context.date,context.type])
	if not rows.has(signature) and rows.size()>=MAX_ROWS:rows.erase(rows.keys()[0])
	var row: Dictionary=rows.get_or_add(signature,context.duplicate())
	row.requests=int(row.get("requests",0))+1
	row.success=int(row.get("success",0))+int(successful)
	row.latency_ms=int(row.get("latency_ms",0))+latency_ms
	for key in COUNT_FIELDS+["seconds"]:
		if measurement.has(key):row[key]=row.get(key,0)+measurement[key]
	var rate:=Pricing.pricing(context.model,context.purpose,context.tier,int(measurement.get("input",0)),context.date)
	var cost:=-1
	match str(rate.get("basis","")):
		"tokens":cost=Pricing.token_cost(rate,measurement)
		"image_tokens":cost=Pricing.image_cost(rate,measurement)
		"characters":
			if measurement.has("characters") and successful:cost=int(measurement.characters)*roundi(float(rate.rate)*1000.)
		"minute","minute_estimate":
			if measurement.has("seconds") and successful:cost=roundi(float(measurement.seconds)*float(rate.rate)*1000000000./60.)
	if cost>=0:
		row.estimate_nano=int(row.get("estimate_nano",0))+cost
		row.priced=int(row.get("priced",0))+1
	return {"usage":measurement,"cost":cost,"latency_ms":latency_ms,"model":context.get("snapshot","")}

func summary(model: String,profile: String) -> Dictionary:
	var total:={}
	for row in rows.values():
		if row.model!=model or row.profile!=profile:continue
		for key in COUNT_FIELDS+["requests","success","latency_ms","seconds","estimate_nano","priced"]:
			if row.has(key):total[key]=total.get(key,0)+row[key]
	return total

func load_rows(raw: Variant) -> void:
	if not raw is Dictionary:return
	for key in raw.keys().slice(-MAX_ROWS):
		var row: Variant=raw[key]
		if key is String and key.length()<600 and row is Dictionary and row.has_all(["profile","model","purpose","effort","mode","tier","date","type"]):rows[key]=row
