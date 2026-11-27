extends RefCounted

const Models=preload("res://scripts/campus/ai/openai_models.gd")
const PRICING_URL:="https://developers.openai.com/api/docs/pricing"
const IMAGE_CALCULATOR:="https://developers.openai.com/api/docs/guides/image-generation#calculating-costs"
const VERIFIED:="2026-11-26"

# USD per million tokens: input, output, cached read, 30m write, 12h write.
# Missing entries are deliberately omitted. -1 means the category has no verified rate.
const TEXT := {
	"gpt-6.2-astra":[8.,40.,.4,10.,20.], "gpt-6.2-sol":[2.,10.,.1,2.5,5.],
	"gpt-6-astra":[10.,50.,1.,12.5,25.], "gpt-6.1-sol":[2.,10.,.1,2.5,5.],
	"gpt-6.1-terra":[1.,5.,.05,1.25,2.5], "gpt-6-luna":[.1,.5,.01,.125,.25],
	"gpt-5.6-sol":[4.,20.,.4,5.,-1.], "chat-latest":[5.,30.,.5,-1.,-1.],
	"gpt-5.5":[5.,30.,.5,-1.,-1.], "gpt-5.5-pro":[30.,180.,-1.,-1.,-1.],
	"gpt-5.4":[2.5,15.,.25,-1.,-1.], "gpt-5.4-pro":[30.,180.,-1.,-1.,-1.],
	"gpt-5.4-mini":[.75,4.5,.075,-1.,-1.], "gpt-5.4-nano":[.2,1.25,.02,-1.,-1.],
	"gpt-5.3-codex":[1.75,14.,.175,-1.,-1.], "gpt-5.2":[1.75,14.,.175,-1.,-1.],
	"gpt-5.2-pro":[21.,168.,-1.,-1.,-1.], "gpt-5.1":[1.25,10.,.125,-1.,-1.],
	"gpt-5":[1.25,10.,.125,-1.,-1.], "gpt-5-mini":[.25,2.,.025,-1.,-1.],
	"gpt-5-nano":[.05,.4,.005,-1.,-1.], "gpt-4.1":[2.,8.,.5,-1.,-1.],
	"gpt-4.1-mini":[.4,1.6,.1,-1.,-1.], "gpt-4.1-nano":[.1,.4,.025,-1.,-1.],
	"gpt-4o":[2.5,10.,1.25,-1.,-1.], "gpt-4o-mini":[.15,.6,.075,-1.,-1.],
	"o3":[2.,8.,.5,-1.,-1.], "o4-mini":[1.1,4.4,.275,-1.,-1.],
}
const NEW_IMAGE := [5.,1.25,8.,2.,30.]
const IMAGES := {
	"gpt-image-2.6-sunburst":NEW_IMAGE, "gpt-image-2.6-flare":NEW_IMAGE,
	"gpt-image-2.5-sunburst":NEW_IMAGE, "gpt-image-2.5-flare":NEW_IMAGE, "gpt-image-2":NEW_IMAGE,
	"gpt-image-1.5":[5.,1.25,8.,2.,32.], "gpt-image-1-mini":[2.,.2,2.5,.25,8.],
}
const SPEECH := {"tts-1":[15.,"characters"],"tts-1-hd":[30.,"characters"],"gpt-4o-mini-tts":[.015,"minute_estimate"]}
const TRANSCRIBE := {"gpt-transcribe":[.0045,"minute"],"whisper-1":[.006,"minute"],"gpt-4o-mini-transcribe":[.003,"minute_estimate"],"gpt-4o-transcribe":[.006,"minute_estimate"],"gpt-4o-transcribe-diarize":[.006,"minute_estimate"]}
const REALTIME_AUDIO:={"gpt-realtime-2.1-mini":[.6,.06,2.4,10.,.3,20.],"gpt-realtime-2.1":[4.,.4,24.,32.,.4,64.]}
const LONG_CONTEXT := ["gpt-6.2-astra","gpt-6.2-sol","gpt-6-astra","gpt-6.1-sol","gpt-6.1-terra","gpt-6-luna","gpt-5.6-sol","gpt-5.4","gpt-5.4-pro","gpt-5.5","gpt-5.5-pro"]
const FAST := ["gpt-6.2-astra","gpt-6.2-sol","gpt-6-astra","gpt-6.1-sol","gpt-6.1-terra","gpt-6-luna"]
const FLEX := ["gpt-6-astra","gpt-6.1-sol","gpt-6.1-terra","gpt-6-luna"]
const BACKGROUND:=["gpt-6.2-astra","gpt-6.2-sol","gpt-6.1-terra","gpt-6-luna"]

static func tiers(id: String,purpose: String) -> Array:
	var base:=Models.verified_family(id)
	if purpose=="image_generation":
		return ["standard","batch"] if base in ["gpt-image-2","gpt-image-2.5-sunburst","gpt-image-2.5-flare","gpt-image-2.6-sunburst","gpt-image-2.6-flare"] else ["standard"]
	if purpose not in ["text","image"]:return ["standard"]
	var result:=["standard"]
	if base in FAST:result.append_array(["batch","fast"])
	if base in FLEX:result.append("flex")
	if base in ["gpt-6.2-astra","gpt-6.2-sol","gpt-6-astra","gpt-6.1-sol"]:result.append("ultrafast")
	if base in BACKGROUND:result.append_array(["background_2h","background_8h"])
	return result

static func pricing(id: String,purpose: String,tier := "standard",input_tokens := 0,date := "") -> Dictionary:
	var base:=Models.verified_family(id)
	if base.is_empty() or tier not in tiers(id,purpose):return {}
	if date.is_empty():date=Time.get_date_string_from_system(true)
	if base=="gpt-5.6-sol" and date>"2026-11-30":return {}
	var result:={"source_url":"https://developers.openai.com/api/docs/models/"+base,"verified_at":VERIFIED,"tier":tier,"long_context":false}
	if purpose in ["text","image"] and TEXT.has(base):
		var rates: Array=TEXT[base]
		var factor:=1.0
		match tier:
			"batch","flex":factor=.5
			"fast":factor=2.
			"ultrafast":factor=3. if base.begins_with("gpt-6.2") and date<"2027-03-01" else 6.
			"background_2h":factor=.7
			"background_8h":factor=.6
		var long_context:=input_tokens>272000 and base in LONG_CONTEXT
		result.merge({"input":rates[0]*factor*(2.0 if long_context else 1.0),"output":rates[1]*factor*(1.5 if long_context else 1.0),"unit":"USD / 1M tokens","basis":"tokens","long_context":long_context},true)
		for i in range(2,5):
			if float(rates[i])>=0.0:result[["cached","write_30m","write_12h"][i-2]]=rates[i]*factor*(2.0 if long_context else 1.)
		result.label="$%s in · $%s out"%[money_rate(result.input),money_rate(result.output)]
		if base=="gpt-5.6-sol":result.promotional_until="2026-11-30"
	elif purpose=="image_generation" and IMAGES.has(base):
		var rates: Array=IMAGES[base]
		var scale:=.5 if tier=="batch" else 1.
		result.merge({"text_input":rates[0]*scale,"text_cached":rates[1]*scale,"image_input":rates[2]*scale,"image_cached":rates[3]*scale,"image_output":rates[4]*scale,"unit":"USD / 1M tokens","basis":"image_tokens","estimator":IMAGE_CALCULATOR})
		result.label="$%s text in · $%s image out"%[money_rate(result.text_input),money_rate(result.image_output)]
		if base=="gpt-image-2":result.source_url=PRICING_URL
	elif purpose in ["tts","live"] and base in Models.LIVE:
		result.merge({"rate":.05,"basis":"minute","unit":"USD / active session minute","label":"$0.05 / active min · backend separate","verified_at":"2026-11-27"})
	elif purpose=="tts" and REALTIME_AUDIO.has(base):
		var values: Array=REALTIME_AUDIO[base]
		result.merge({"text_input":values[0],"text_cached":values[1],"text_output":values[2],"audio_input":values[3],"audio_cached":values[4],"audio_output":values[5],"basis":"audio_tokens","unit":"USD / 1M tokens","label":"$%s text in · $%s audio out"%[money_rate(values[0]),money_rate(values[5])],"verified_at":"2026-11-27"})
	else:
		var types: Dictionary=SPEECH if purpose=="tts" else TRANSCRIBE if purpose=="stt" else {}
		if not types.has(base):return {}
		var entry: Array=types[base]
		result.merge({"rate":entry[0],"basis":entry[1],"unit":"USD / 1M characters" if entry[1]=="characters" else "USD / minute"})
		result.label="%s$%s / %s"%["≈ " if entry[1]=="minute_estimate" else "",money_rate(entry[0]),"1M chars" if entry[1]=="characters" else "min"]
	if tier!="standard":result.source_url=PRICING_URL
	return result

static func money_rate(value: float) -> String:
	return ("%0.6f"%value).rstrip("0").rstrip(".")

# Monetary calculations use integer nanodollars. One output token includes any
# billed reasoning tokens already counted by the API.
static func token_cost(rate: Dictionary,usage: Dictionary) -> int:
	if rate.is_empty() or not rate.has("input") or not usage.has("input") or not usage.has("output"):return -1
	var cached:=int(usage.get("cached",0))
	var write_30m:=int(usage.get("write_30m",0))
	var write_12h:=int(usage.get("write_12h",0))
	var uncached:=int(usage.input)-cached-write_30m-write_12h
	if uncached<0 or int(usage.output)<0:return -1
	var total:=uncached*roundi(float(rate.input)*1000.0)+int(usage.output)*roundi(float(rate.output)*1000.0)
	for entry in [["cached",cached],["write_30m",write_30m],["write_12h",write_12h]]:
		if int(entry[1])<0 or (int(entry[1])>0 and not rate.has(entry[0])):return -1
		total+=int(entry[1])*roundi(float(rate.get(entry[0],0))*1000.0)
	return total

static func usd(cost: int) -> String:
	return "Unavailable" if cost<0 else "$%.5f"%(float(cost)/1000000000.0)

static func image_cost(rate: Dictionary,usage: Dictionary) -> int:
	if not rate.has("image_output") or not usage.has_all(["text_input","image_input","image_output"]):return -1
	# A reported cache total without a text/image split cannot be priced exactly.
	var text_cache:=int(usage.get("text_cached",0))
	var image_cache:=int(usage.get("image_cached",0))
	if int(usage.get("cached",text_cache+image_cache))!=text_cache+image_cache:return -1
	return (int(usage.text_input)-text_cache)*roundi(float(rate.text_input)*1000.)+(int(usage.image_input)-image_cache)*roundi(float(rate.image_input)*1000.)+int(usage.image_output)*roundi(float(rate.image_output)*1000.)+text_cache*roundi(float(rate.text_cached)*1000.)+image_cache*roundi(float(rate.image_cached)*1000.)

static func audio_cost(rate: Dictionary,usage: Dictionary) -> int:
	if not rate.has("audio_output") or not usage.has_all(["text_input","audio_input","text_output","audio_output"]):return -1
	var cached_text:=int(usage.get("text_cached",0))
	var cached_audio:=int(usage.get("audio_cached",0))
	if int(usage.get("image_input",0))>0 or int(usage.get("cached",0))!=cached_text+cached_audio:return -1
	if cached_text>int(usage.text_input) or cached_audio>int(usage.audio_input):return -1
	return (int(usage.text_input)-cached_text)*roundi(float(rate.text_input)*1000.)+cached_text*roundi(float(rate.text_cached)*1000.)+int(usage.text_output)*roundi(float(rate.text_output)*1000.)+(int(usage.audio_input)-cached_audio)*roundi(float(rate.audio_input)*1000.)+cached_audio*roundi(float(rate.audio_cached)*1000.)+int(usage.audio_output)*roundi(float(rate.audio_output)*1000.)
