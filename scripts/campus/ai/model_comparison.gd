extends RefCounted

const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
const PRICING_URL=Pricing.PRICING_URL
const MINI:="https://openai.com/index/introducing-gpt-5-4-mini-and-nano/"
const SYSTEM_CARD:="https://deploymentsafety.openai.com/gpt-6-2-astra-sol#gpqa-diamond-no-tools"
const VERIFIED:="2026-11-26"

# [Model, purpose, accuracy, published effort, mode, source, method].
const PUBLISHED := [
	["gpt-5.4","text",93.0,"xhigh","standard",MINI,"Publisher-reported result"],
	["gpt-5.4-mini","text",88.0,"xhigh","standard",MINI,"Publisher-reported result"],
	["gpt-5.4-nano","text",82.8,"xhigh","standard",MINI,"Publisher-reported result"],
	["gpt-5-mini","text",81.6,"high","standard",MINI,"Publisher-reported result"],
	["gpt-5.4","image",81.2,"xhigh","standard",MINI,"Without Python"],
	["gpt-5.4-mini","image",76.6,"xhigh","standard",MINI,"Without Python"],
	["gpt-5.4-nano","image",66.1,"xhigh","standard",MINI,"Without Python"],
	["gpt-5-mini","image",67.5,"high","standard",MINI,"Without Python"],
	["gpt-6.2-astra","text",97.0,"","",SYSTEM_CARD,"No tools, 198 questions"],
	["gpt-6.2-sol","text",96.0,"","",SYSTEM_CARD,"No tools, 198 questions"],
	["gpt-6-astra","text",96.0,"","",SYSTEM_CARD,"No tools, 198 questions"],
]

static func display_effort(effort: String) -> String:
	return {"":"Default","none":"None","minimal":"Minimal","low":"Low","medium":"Medium","high":"High","xhigh":"Extra High","max":"Maximum"}.get(effort,effort)

static func benchmark_name(purpose: String) -> String:
	return {"text":"GPQA Diamond","image":"MMMU-Pro"}.get(purpose,"Benchmark")

static func benchmark_records(id: String,purpose: String) -> Array[Dictionary]:
	var records: Array[Dictionary]=[]
	for row in PUBLISHED:
		if row[0]==id and row[1]==purpose:
			records.append({"model":id,"benchmark":benchmark_name(purpose),"score_percent":row[2],"reasoning_effort":row[3],"reasoning_mode":row[4],"source_type":"published","source_url":row[5],"methodology":row[6],"verified_at":VERIFIED})
	return records

static func measurement(id: String,purpose: String,preview := "",mode := "standard") -> Dictionary:
	if not preview.is_empty() and preview not in Models.efforts(id):
		return {"status":"unsupported","label":"Not supported at this effort"}
	if mode=="pro" and mode not in Models.metadata(id,purpose).modes:return {"status":"unsupported","label":"Pro mode unsupported"}
	for record in benchmark_records(id,purpose):
		if preview.is_empty() and mode=="standard":return record
		if record.reasoning_effort==preview and record.reasoning_mode==mode:return record
	return {"status":"missing","label":"Not benchmarked" if preview.is_empty() else "Not benchmarked at "+display_effort(preview)}

static func score(id: String,purpose: String,preview := "",mode := "standard") -> float:
	return float(measurement(id,purpose,preview,mode).get("score_percent",-1.0))

static func published_reference(id: String,purpose: String) -> Dictionary:
	var records:=benchmark_records(id,purpose)
	if records.is_empty():return {}
	var record:=records[0]
	record.reference=true
	return record

static func pricing(id: String,purpose: String,tier := "standard",inputs := 0,date := "") -> Dictionary:
	return Pricing.pricing(id,purpose,tier,inputs,date)
