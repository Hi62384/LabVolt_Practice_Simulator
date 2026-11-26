extends RefCounted

# /v1/models lists availability. Capability labels and reasoning options come
# from the OpenAI model reference and are shared by aliases and dated snapshots.
const BASIC := ["low","medium","high"]
const EXTENDED := ["low","medium","high","xhigh"]
const OPTIONAL := ["none","low","medium","high","xhigh"]
const MAXIMUM := ["low","medium","high","xhigh","max"]
const OPTIONAL_MAXIMUM := ["none","low","medium","high","xhigh","max"]
const PRO := ["medium","high","xhigh"]
const LEGACY := ["minimal","low","medium","high"]
const MODELS := {
	"gpt-6.2-astra":["Flagship",MAXIMUM],
	"gpt-6.2-sol":["Advanced",MAXIMUM],
	"gpt-6.1-sol":["Advanced",MAXIMUM],
	"gpt-6.1-terra":["Balanced",OPTIONAL_MAXIMUM],
	"gpt-6-astra":["Flagship",MAXIMUM],
	"gpt-6-sol":["Advanced",OPTIONAL_MAXIMUM],
	"gpt-6-luna":["Efficient",OPTIONAL_MAXIMUM],
	"gpt-5.6":["Flagship",OPTIONAL_MAXIMUM],
	"gpt-5.6-sol":["Flagship",OPTIONAL_MAXIMUM],
	"gpt-5.6-terra":["Balanced",OPTIONAL_MAXIMUM],
	"gpt-5.6-luna":["Efficient",OPTIONAL_MAXIMUM],
	"gpt-5.5":["Flagship",OPTIONAL],
	"gpt-5.5-pro":["Pro",PRO],
	"gpt-5.4":["Flagship",OPTIONAL],
	"gpt-5.4-pro":["Pro",PRO],
	"gpt-5.4-mini":["Compact",OPTIONAL],
	"gpt-5.4-nano":["Efficient",OPTIONAL],
	"gpt-5.3-codex":["Advanced coding",EXTENDED],
	"gpt-5.2":["Flagship",OPTIONAL],
	"gpt-5.2-pro":["Pro",PRO],
	"gpt-5.2-codex":["Advanced coding",EXTENDED],
	"gpt-5.1":["Advanced",["none","low","medium","high"]],
	"gpt-5.1-codex":["Advanced coding",BASIC],
	"gpt-5.1-codex-max":["Advanced coding",EXTENDED],
	"gpt-5.1-codex-mini":["Compact coding",["medium","high"]],
	"gpt-5":["Advanced",LEGACY],
	"gpt-5-pro":["Pro",["high"]],
	"gpt-5-codex":["Advanced coding",BASIC],
	"gpt-5-mini":["Compact",LEGACY],
	"gpt-5-nano":["Efficient",LEGACY],
	"o1":["Advanced reasoning",BASIC],
	"o1-pro":["Pro",["high"]],
	"o3":["Advanced reasoning",BASIC],
	"o3-mini":["Compact reasoning",BASIC],
	"o3-pro":["Pro",["high"]],
	"o4-mini":["Compact reasoning",BASIC],
	"gpt-4.1":["Advanced",[]],
	"gpt-4.1-mini":["Compact",[]],
	"gpt-4.1-nano":["Efficient",[]],
	"gpt-4o":["General purpose",[]],
	"gpt-4o-mini":["Compact",[]]
}

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length()>256:return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:":return false
	return true

static func family(id: String) -> String:
	var base:=id.get_slice(":",1) if id.begins_with("ft:") else id
	if base.length()>11 and base.right(11)[0]=="-" and base.right(10).replace("-","").is_valid_int():
		return base.left(-11)
	return base

static func endpoint(id: String) -> String:
	var base:=family(id)
	for marker in ["embedding","moderation","realtime","transcribe","whisper","tts","dall-e","gpt-image","chatgpt-image","sora","deep-research","computer-use","gpt-live","-audio","-search","instruct"]:
		if marker in base:return ""
	if base.begins_with("gpt-3.5-turbo") or base in ["gpt-4","gpt-4-0314","gpt-4-0613","gpt-4-32k"] or "-audio" in base or "-search-preview" in base:
		return "/chat/completions"
	return "/responses"

static func supports(id: String, purpose: String) -> bool:
	if not valid_id(id):return false
	var base:=family(id)
	match purpose:
		"text":
			return not endpoint(id).is_empty() and (base.begins_with("gpt-") or base.begins_with("chat-") or base.begins_with("chatgpt-") or MODELS.has(base) or id.begins_with("ft:"))
		"image":
			# These model families accept image input for the game's screenshot assistant.
			return supports(id,"text") and (base.begins_with("gpt-4o") or base.begins_with("gpt-4.1") or base.begins_with("gpt-5") or base.begins_with("gpt-6") or base in ["o3","o3-pro","o4-mini"])
		"image_generation":
			return base in ["gpt-image-1-mini","gpt-image-1.5","gpt-image-2","gpt-image-2.5-flare","gpt-image-2.5-sunburst","gpt-image-2.6-flare","gpt-image-2.6-sunburst","chatgpt-image-latest"]
		"tts":
			return base in ["tts-1","tts-1-hd","gpt-4o-mini-tts"]
		"stt":
			return base in ["gpt-transcribe","gpt-4o-transcribe","gpt-4o-mini-transcribe","gpt-4o-transcribe-diarize","whisper-1"]
	return false

static func tier(id: String) -> String:
	var base:=family(id)
	if MODELS.has(base):return MODELS[base][0]
	if endpoint(id).is_empty():return "Specialized"
	if id.begins_with("ft:"):return "Fine-tuned"
	return "Unrated"

static func intelligence_rank(id: String, purpose: String) -> int:
	var base:=family(id)
	match purpose:
		"image_generation":
			if base.begins_with("gpt-image-2") or base=="chatgpt-image-latest":return 3
			return {"gpt-image-1-mini":1,"gpt-image-1":2,"gpt-image-1.5":2}.get(base,-1)
		"tts":
			return {"tts-1":1,"tts-1-hd":2,"gpt-4o-mini-tts":3}.get(base,-1)
		"stt":
			return {"whisper-1":1,"gpt-4o-mini-transcribe":2,"gpt-4o-transcribe":3,"gpt-4o-transcribe-diarize":3,"gpt-transcribe":3}.get(base,-1)
	return {"Efficient":1,"Compact":2,"Compact coding":2,"Compact reasoning":2,"General purpose":3,
		"Balanced":4,"Advanced":5,"Advanced coding":5,"Advanced reasoning":5,"Flagship":6,"Pro":7}.get(tier(id),-1)

static func efforts(id: String) -> Array:
	return MODELS.get(family(id),["",[]])[1]

static func normalize_effort(id: String, effort: String) -> String:
	return effort if effort in efforts(id) else ""

static func speech_voices(id: String) -> Array:
	if not supports(id,"tts"):return []
	var voices:=["alloy","ash","coral","echo","fable","nova","onyx","sage","shimmer"]
	if family(id)=="gpt-4o-mini-tts":voices.append_array(["ballad","cedar","marin","verse"])
	voices.sort()
	return voices
