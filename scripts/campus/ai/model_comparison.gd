extends RefCounted

const Models = preload("res://scripts/campus/ai/openai_models.gd")
const PRICING_URL := "https://developers.openai.com/api/docs/pricing"
# Standard short-context USD per million tokens, checked 2026-11-25.
const TEXT_RATES := {
	"gpt-6.2-astra":[8.0,40.0],"gpt-6.2-sol":[2.0,10.0],"gpt-6-astra":[10.0,50.0],"gpt-6.1-sol":[2.0,10.0],
	"gpt-6.1-terra":[1.0,5.0],"gpt-6-luna":[.10,.50],"gpt-5.6-sol":[4.0,20.0],
	"gpt-5.5":[5.0,30.0],"gpt-5.5-pro":[30.0,180.0],"gpt-5.4-pro":[30.0,180.0],"chat-latest":[5.0,30.0],"gpt-5.4":[2.5,15.0],"gpt-5.4-mini":[.75,4.5],"gpt-5.4-nano":[.20,1.25],
	"gpt-5.3-codex":[1.75,14.0],"gpt-5.2":[1.75,14.0],"gpt-5.2-pro":[21.0,168.0],
	"gpt-5.1":[1.25,10.0],"gpt-5":[1.25,10.0],"gpt-5-mini":[.25,2.0],"gpt-5-nano":[.05,.40],
	"gpt-4.1":[2.0,8.0],"gpt-4.1-mini":[.40,1.60],"gpt-4.1-nano":[.10,.40],"gpt-4o":[2.5,10.0],"gpt-4o-mini":[.15,.60],
	"o3":[2.0,8.0],"o4-mini":[1.10,4.40]
}
const IMAGE_RATES := {
	"gpt-image-2.6-sunburst":[8.0,30.0],"gpt-image-2.6-flare":[8.0,30.0],
	"gpt-image-2.5-sunburst":[4.0,15.0],"gpt-image-2.5-flare":[4.0,15.0],"gpt-image-2":[4.0,15.0],
	"gpt-image-1.5":[8.0,32.0],"gpt-image-1-mini":[2.5,8.0]
}
const SPEECH_RATES := {"gpt-4o-mini-tts":.015,"tts-1":15.0,"tts-1-hd":30.0}
const STT_RATES := {"gpt-4o-transcribe":.006,"gpt-4o-mini-transcribe":.003,"gpt-4o-transcribe-diarize":.006,"gpt-transcribe":.0045,"whisper-1":.006}

# Publisher evaluations differ by task and effort. Keep the two benchmarks separate.
# https://openai.com/index/introducing-gpt-5-4-mini-and-nano/
# https://openai.com/index/introducing-gpt-5-4/
# https://openai.com/index/introducing-gpt-5-2/
# https://openai.com/index/introducing-gpt-5-for-developers/
# https://openai.com/index/introducing-gpt-4-1/
# https://openai.com/index/gpt-6-astra/
# https://openai.com/index/gpt-5-6/
# https://deploymentsafety.openai.com/gpt-6-2-astra-sol/respecting-auto-review
const GPQA := {
	"gpt-6.2-astra":97.0,"gpt-6.2-sol":96.0,"gpt-6-astra":96.0,"gpt-5.6-sol":94.6,"gpt-5.6-terra":92.9,"gpt-5.6-luna":92.3,"gpt-5.5":93.6,
	"gpt-5.4":93.0,"gpt-5.4-pro":94.4,"gpt-5.4-mini":88.0,"gpt-5.4-nano":82.8,"gpt-5.3-codex":92.6,
	"gpt-5.2":92.4,"gpt-5.2-pro":93.2,"gpt-5.1":88.1,"gpt-5":85.7,"gpt-5-mini":81.6,"gpt-5-nano":71.2,
	"gpt-4.1":66.3,"gpt-4.1-mini":65.0,"gpt-4.1-nano":50.3,"gpt-4o":46.0,"gpt-4o-mini":40.2,"o1":75.7,"o3":83.3,"o3-mini":77.2,"o4-mini":81.4
}
const MMMU := {
	"gpt-5.4":81.2,"gpt-5.4-mini":76.6,"gpt-5.4-nano":66.1,"gpt-5.2":79.5,"gpt-5":78.4,"gpt-5-mini":67.5,"gpt-5-nano":62.6,
	"gpt-4.1":60.3,"gpt-4.1-mini":58.9,"gpt-4.1-nano":33.0,"o3":76.4,"o4-mini":73.4
}

static func score(id: String,purpose: String) -> float:
	if id.begins_with("ft:"):return -1.0
	if purpose=="text":return GPQA.get(Models.family(id),-1.0)
	if purpose=="image":return MMMU.get(Models.family(id),-1.0)
	return -1.0

static func pricing(id: String,purpose: String) -> Dictionary:
	if id.begins_with("ft:"):return {}
	var base:=Models.family(id)
	var pairs: Dictionary=IMAGE_RATES if purpose=="image_generation" else TEXT_RATES
	if purpose in ["text","image","image_generation"] and pairs.has(base):
		var cost: Array=pairs[base]
		var unit:="image tokens" if purpose=="image_generation" else "tokens"
		return {"label":"$%s in / $%s out"%[cost[0],cost[1]],"unit":"USD / 1M "+unit,"compare":float(cost[0])+float(cost[1]),"basis":unit}
	var rates: Dictionary=SPEECH_RATES if purpose=="tts" else STT_RATES if purpose=="stt" else {}
	if rates.has(base):
		var per_minute:=not base.begins_with("tts-")
		return {"label":"%s$%s / %s"%["~" if per_minute else "",rates[base],"min" if per_minute else "1M chars"],
			"unit":"Estimated USD / audio minute" if per_minute else "USD / 1M characters","compare":rates[base],"basis":"minute" if per_minute else "characters"}
	return {}
