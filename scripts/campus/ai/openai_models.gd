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

const DIRECTORY := "https://developers.openai.com/api/docs/models"
const DEPRECATIONS := "https://developers.openai.com/api/docs/deprecations"
const LEGACY_CHAT := ["gpt-3.5-turbo","gpt-4","gpt-4-0613"]
const IMAGE_GENERATORS := ["gpt-image-1-mini","gpt-image-1.5","gpt-image-2","gpt-image-2.5-flare","gpt-image-2.5-sunburst","gpt-image-2.6-flare","gpt-image-2.6-sunburst","chatgpt-image-latest"]
const TTS := ["tts-1","tts-1-hd","gpt-4o-mini-tts"]
const REALTIME := ["gpt-realtime-2.1-mini","gpt-realtime-2.1","gpt-realtime-2","gpt-realtime-1.5","gpt-realtime","gpt-realtime-mini"]
const LIVE := ["gpt-live-1.1","gpt-live-1"]
const AUDIO_VERIFIED_AT := "2026-11-27"
const REALTIME_VOICES := ["alloy","ash","ballad","coral","echo","sage","shimmer","verse","marin","cedar"]
const LIVE_VOICES := ["alloy","ash","ballad","beacon","bossa","brise","calandria","cedar","cinder","compas","coral","delta","destello","echo","flitz","gleam","halo","harema","hornero","juni","luciernaga","marin","meridian","nira","noeul","nuri","pearl","quartz","ripple","sage","shida","shimmer","sillage","stone","tempo","verse","vesper","willow"]
const STREAMING_STT := ["gpt-live-transcribe","gpt-realtime-whisper"]
const AUDIO_CHAT := ["gpt-audio-1.5","gpt-audio","gpt-audio-mini"]
const EMBEDDINGS := ["text-embedding-3-small","text-embedding-3-large"]
const MODERATION := ["omni-moderation-latest"]
const STT := ["gpt-transcribe","gpt-4o-transcribe","gpt-4o-mini-transcribe","gpt-4o-transcribe-diarize","whisper-1"]
const TEXT_ONLY := ["gpt-5.3-codex","gpt-5.2-codex","gpt-5.1-codex-mini","gpt-5-codex","o3-mini"]
const EXPLICIT_ALIASES := {"gpt-5.6":"gpt-5.6-sol"}
const DOCUMENTED_SNAPSHOTS := [
	"gpt-4o-2024-05-13","gpt-4o-2024-08-06","gpt-4o-2024-11-20","gpt-4o-mini-2024-07-18","gpt-4.1-2025-04-14","gpt-4.1-mini-2025-04-14","gpt-4.1-nano-2025-04-14",
	"gpt-5-2025-08-07","gpt-5-mini-2025-08-07","gpt-5-nano-2025-08-07","gpt-5.1-2025-11-13","gpt-5.2-2025-12-11","gpt-5.4-2026-03-05","gpt-5.4-mini-2026-03-17","gpt-5.4-nano-2026-03-17",
	"gpt-image-1.5-2025-12-16","gpt-image-2-2026-04-21","gpt-image-2.5-flare-2026-09-08","gpt-image-2.5-sunburst-2026-09-08",
	"gpt-4o-mini-tts-2025-03-20","gpt-4o-mini-tts-2025-12-15","gpt-4o-mini-transcribe-2025-03-20","gpt-4o-mini-transcribe-2025-12-15",
	"gpt-realtime-2025-08-28","gpt-realtime-mini-2025-12-15","gpt-audio-2025-08-28","gpt-audio-mini-2025-12-15","gpt-5-pro-2025-10-06",
	"o3-2025-04-16","o3-pro-2025-06-10","o4-mini-2025-04-16"
]
const DEFAULT_EFFORT := {
	"gpt-6.1-sol":"medium","gpt-6-sol":"medium","gpt-6-luna":"medium",
	"gpt-5.6-sol":"medium","gpt-5.6-terra":"medium","gpt-5.6-luna":"medium","gpt-5.5":"medium",
	"gpt-5.4":"none","gpt-5.2":"none","gpt-5.1":"none"
}
const LIMITS := {
	"gpt-6.2-astra":[1050000,128000],"gpt-6.2-sol":[1050000,128000],"gpt-6.1-terra":[1050000,128000],"gpt-6-luna":[1050000,128000],
	"gpt-6-sol":[1050000,128000],"gpt-5.6-terra":[1050000,128000],"gpt-5.6-luna":[1050000,128000],
	"gpt-audio-1.5":[128000,16384],"gpt-realtime-2":[128000,32000],"gpt-realtime-whisper":[16000,2000],
	"gpt-5.4":[1050000,128000],"gpt-5.4-mini":[400000,128000],"gpt-5.4-nano":[400000,128000],
	"gpt-5-mini":[400000,128000],"gpt-5-nano":[400000,128000],"gpt-4.1":[1047576,32768],"gpt-4.1-mini":[1047576,32768]
}
const LIFECYCLE := {
	"gpt-5":["2026-12-11","gpt-6.1-sol"],
	"gpt-5-mini":["2026-12-11","gpt-6.1-terra"],
	"gpt-5-nano":["2026-12-11","gpt-6-luna"],
	"gpt-5-pro":["2026-12-11","gpt-6.1-sol in Pro mode"],
	"gpt-realtime":["2027-01-20","gpt-realtime-2.1"],
	"gpt-realtime-mini":["2027-01-20","gpt-realtime-2.1-mini"],
	"gpt-audio":["2027-01-20","gpt-audio-1.5"],
	"gpt-audio-mini":["2027-01-20","gpt-audio-1.5"],
	"gpt-4o-audio":["2027-01-20","gpt-audio-1.5"],
	"gpt-4o-mini-audio":["2027-01-20","gpt-audio-1.5"],
	"gpt-4o-realtime":["2027-01-20","gpt-realtime-2.1"],
	"gpt-4o-mini-realtime":["2027-01-20","gpt-realtime-2.1-mini"],
	"gpt-image-1-mini":["2026-12-01","gpt-image-2.6-sunburst / flare"],
	"gpt-image-1.5":["2026-12-01","gpt-image-2.6-sunburst / flare"],
	"chatgpt-image-latest":["2026-12-01","gpt-image-2.6-sunburst / flare"],
	"o3":["2026-12-11","gpt-6.1-sol"],
	"o3-pro":["2026-12-11","gpt-6.1-sol in Pro mode"],
	"tts-1":["2027-01-06","gpt-realtime-2.1-mini (Realtime API)"],
	"tts-1-hd":["2027-01-06","gpt-realtime-2.1-mini (Realtime API)"],
	"gpt-4o-mini-tts":["2027-01-06","gpt-realtime-2.1-mini (Realtime API)"],
	"gpt-4o-2024-05-13":["2026-10-23","gpt-5.6-sol"],
	"gpt-4o-2024-08-06":["2027-01-14","gpt-6-luna"],
	"gpt-4o-2024-11-20":["2027-01-14","gpt-6-luna"],
	"gpt-4o-mini-2024-07-18":["2027-01-14","gpt-6-luna"],
	"gpt-4.1-2025-04-14":["2027-01-14","gpt-6-luna"],
	"gpt-4.1-mini-2025-04-14":["2027-01-14","gpt-6-luna"],
	"gpt-4o-mini-transcribe-2025-03-20":["2027-01-20","gpt-4o-mini-transcribe-2025-12-15"],
	"gpt-image-2":["2027-02-10","gpt-image-2.6-sunburst / flare"],
	"whisper-1":["2027-02-26","gpt-transcribe"],
	"gpt-4o-transcribe":["2027-02-26","gpt-transcribe"],
	"gpt-4o-mini-transcribe":["2027-02-26","gpt-transcribe"],
	"gpt-4o-transcribe-diarize":["2027-02-26","gpt-transcribe"],
	"gpt-5.3-codex":["2027-04-01","gpt-6-sol"],
	"gpt-5.4-nano":["2027-04-01","gpt-6-luna"],
	"gpt-5.1":["2027-04-01","gpt-6-sol"],
	"o1":["2026-10-23","gpt-5.6-sol"],
	"o1-pro":["2026-10-23","gpt-5.6-sol in Pro mode"],
	"o3-mini":["2026-10-23","gpt-5.6-sol"],
	"o4-mini":["2026-10-23","gpt-5.6-terra"],
	"gpt-4.1-nano":["2026-10-23","gpt-5.6-luna"],
	"gpt-5.1-codex":["2026-07-23","gpt-5.6-sol"],
	"gpt-5.1-codex-max":["2026-07-23","gpt-5.6-sol"],
	"gpt-5.1-codex-mini":["2026-07-23","gpt-5.6-terra"],
	"gpt-5.2-codex":["2026-07-23","gpt-5.6-sol"]
}

static func verified_family(id: String) -> String:
	if id.begins_with("ft:"):return ""
	if EXPLICIT_ALIASES.has(id):return EXPLICIT_ALIASES[id]
	if id in DOCUMENTED_SNAPSHOTS:return family(id)
	return id if MODELS.has(id) or id in LEGACY_CHAT or id in IMAGE_GENERATORS or id in TTS or id in STT or id in REALTIME or id in LIVE or id in STREAMING_STT or id in AUDIO_CHAT or id in EMBEDDINGS or id in MODERATION or LIFECYCLE.has(id) or id=="chat-latest" else ""

static func lifecycle(id: String,date := "") -> Dictionary:
	var base:=verified_family(id)
	if id.begins_with("ft:"):base=verified_family(id.get_slice(":",1))
	var record: Array=LIFECYCLE.get(id,LIFECYCLE.get(base,[]))
	if record.is_empty():return {"status":"unknown" if base.is_empty() else "active","verified_at":AUDIO_VERIFIED_AT,"source_url":DIRECTORY+"/"+base if not base.is_empty() else DIRECTORY}
	if date.is_empty():date=Time.get_date_string_from_system(true)
	return {"status":"retired" if date>=str(record[0]) else "deprecated","shutdown":record[0],"replacement":record[1],"source_url":DEPRECATIONS,"verified_at":AUDIO_VERIFIED_AT,"announced":_deprecation_announcement(base)}

static func endpoint(id: String) -> String:
	var base:=verified_family(id)
	if id.begins_with("ft:"):base=verified_family(id.get_slice(":",1))
	if base in LEGACY_CHAT:return "/chat/completions"
	if MODELS.has(base) or base=="chat-latest":return "/responses"
	return ""

static func supports(id: String,purpose: String) -> bool:
	if not valid_id(id):return false
	var base:=verified_family(id)
	match purpose:
		"text":return not endpoint(id).is_empty()
		"image":
			return supports(id,"text") and base not in TEXT_ONLY and base not in LEGACY_CHAT and not base.is_empty()
		"image_generation":return base in IMAGE_GENERATORS
		"tts":return base in TTS or base in REALTIME or base in LIVE or base=="gpt-audio-1.5"
		"live":return base in LIVE
		"realtime":return base in REALTIME
		"stt":return base in STT or base in STREAMING_STT
	return false

# Documented catalog membership is distinct from a working game adapter.
# Advanced models appear only when requested; a saved selection is never hidden.
const RECOMMENDED:={
	"text":["gpt-6.2-astra","gpt-6.2-sol","gpt-6.1-terra","gpt-6-luna","gpt-5.4-mini"],
	"image":["gpt-6.1-terra","gpt-6.2-sol","gpt-6.2-astra","gpt-6-luna","gpt-5.4-mini"],
	"image_generation":["gpt-image-2.6-sunburst","gpt-image-2.6-flare"],
	"tts":["gpt-realtime-2.1-mini","gpt-realtime-2.1","gpt-live-1.1","gpt-audio-1.5"],
	"live":["gpt-live-1.1","gpt-realtime-2.1-mini","gpt-realtime-2.1"],
	"stt":["gpt-transcribe","gpt-live-transcribe","gpt-realtime-whisper"],
	"embeddings":["text-embedding-3-small","text-embedding-3-large"]
}
const DEFAULT_CHOICES:={
	"text":["gpt-6-luna","gpt-6.1-terra","gpt-5.4-mini","gpt-6.2-sol"],
	"image":["gpt-6.1-terra","gpt-6-luna","gpt-5.4-mini"],
	"image_generation":["gpt-image-2.6-flare","gpt-image-2.6-sunburst","gpt-image-2.5-flare"],
	"tts":["gpt-realtime-2.1-mini","gpt-live-1.1","gpt-realtime-2.1"],
	"live":["gpt-live-1.1","gpt-live-1"],"stt":["gpt-transcribe","gpt-live-transcribe"],
	"embeddings":["text-embedding-3-small","text-embedding-3-large"]
}

static func documented_for(id: String,purpose: String) -> bool:
	var base:=verified_family(id)
	if supports(id,purpose):return true
	match purpose:
		"tts":return base in AUDIO_CHAT or base in ["gpt-4o-audio","gpt-4o-mini-audio","gpt-4o-realtime","gpt-4o-mini-realtime"]
		"live":return base in REALTIME
		"stt":return base in STREAMING_STT
		"embeddings":return base in EMBEDDINGS
	return false

static func catalog_ids(purpose: String) -> Array:
	var result: Array=[]
	for id: String in MODELS.keys()+LEGACY_CHAT+IMAGE_GENERATORS+TTS+REALTIME+LIVE+STT+STREAMING_STT+AUDIO_CHAT+EMBEDDINGS+MODERATION+DOCUMENTED_SNAPSHOTS+LIFECYCLE.keys()+["chat-latest"]:
		if id not in result and documented_for(id,purpose):result.append(id)
	return result

static func recommended(id: String,purpose: String) -> bool:
	return id in RECOMMENDED.get(purpose,[])

static func recommended_choice(ids: Array,purpose: String) -> String:
	for id: String in DEFAULT_CHOICES.get(purpose,[]):
		if id in ids and available_for(id,purpose):return id
	for id: String in ids:
		if id==verified_family(id) and available_for(id,purpose) and lifecycle(id).status=="active":return id
	for id: String in ids:
		if available_for(id,purpose):return id
	return ""

static func display_name(id: String) -> String:
	return id.replace("gpt-","GPT-").replace("text-embedding-","Embedding ").replace("-astra"," Astra").replace("-sol"," Sol").replace("-terra"," Terra").replace("-luna"," Luna").replace("-sunburst"," Sunburst").replace("-flare"," Flare")

static func available_for(id: String,purpose: String) -> bool:
	return supports(id,purpose) and lifecycle(id).status!="retired"

static func metadata(id: String,purpose: String) -> Dictionary:
	var base:=verified_family(id)
	var limits: Array=LIMITS.get(base,[0,0])
	var modes:=["standard","pro"] if has_pro_mode(id) else ["pro"] if base.ends_with("-pro") else ["standard"]
	var route: String={"image_generation":"/images/generations","tts":str(voice_capabilities(id).endpoint),"stt":str(voice_capabilities(id).endpoint),"live":"/live/sessions","realtime":"/realtime"}.get(purpose,endpoint(id))
	return {"id":id,"display_name":display_name(id),"recommended":recommended(id,purpose),"implemented":supports(id,purpose),"documented":documented_for(id,purpose),"family":base,"snapshot":id if id in DOCUMENTED_SNAPSHOTS else "",
		"endpoint":route if supports(id,purpose) else "","efforts":efforts(id),"default_effort":DEFAULT_EFFORT.get(base,""),
		"modes":modes,"context":limits[0],"output":limits[1],"vision":supports(id,"image"),
		"source_url":DIRECTORY+"/"+base if not base.is_empty() else DIRECTORY,"verified_at":AUDIO_VERIFIED_AT,
		"voice":voice_capabilities(id)}

static func has_pro_mode(id: String) -> bool:
	return verified_family(id) in ["gpt-6.2-astra","gpt-6.2-sol","gpt-6.1-sol","gpt-6.1-terra","gpt-6-astra","gpt-6-sol","gpt-6-luna","gpt-5.6-sol","gpt-5.6-terra","gpt-5.6-luna"]

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
			return {"tts-1":1,"tts-1-hd":2,"gpt-4o-mini-tts":3,"gpt-realtime-2.1-mini":3,"gpt-realtime-2.1":3,"gpt-live-1":3,"gpt-live-1.1":3}.get(base,-1)
		"stt":
			return {"whisper-1":1,"gpt-4o-mini-transcribe":2,"gpt-4o-transcribe":3,"gpt-4o-transcribe-diarize":3,"gpt-transcribe":3}.get(base,-1)
	return {"Efficient":1,"Compact":2,"Compact coding":2,"Compact reasoning":2,"General purpose":3,
		"Balanced":4,"Advanced":5,"Advanced coding":5,"Advanced reasoning":5,"Flagship":6,"Pro":7}.get(tier(id),-1)

static func efforts(id: String) -> Array:
	return MODELS.get(verified_family(id),["",[]])[1]

static func normalize_effort(id: String, effort: String) -> String:
	return effort if effort in efforts(id) else ""

static func speech_voices(id: String) -> Array:
	if not supports(id,"tts"):return []
	if verified_family(id) in LIVE:return LIVE_VOICES.duplicate()
	if verified_family(id) in REALTIME:return REALTIME_VOICES.duplicate()
	if verified_family(id)=="gpt-audio-1.5":return REALTIME_VOICES+["fable","nova","onyx"]
	var voices:=["alloy","ash","coral","echo","fable","nova","onyx","sage","shimmer"]
	if verified_family(id)=="gpt-4o-mini-tts":voices.append_array(["ballad","cedar","marin","verse"])
	voices.sort()
	return voices

static func voice_capabilities(id: String) -> Dictionary:
	var base:=verified_family(id)
	var live:=base in LIVE
	var realtime:=base in REALTIME
	var legacy:=base in TTS
	var stt:=base in STT
	var streaming_stt:=base in STREAMING_STT
	var audio_chat:=base=="gpt-audio-1.5"
	var provider:="openai_live" if live else "openai_realtime" if realtime else "openai_speech" if legacy else "openai_audio_chat" if audio_chat else "openai_streaming_transcription" if streaming_stt else "openai_transcription" if stt else ""
	var route:="/live/sessions" if live else "/realtime" if realtime else "/audio/speech" if legacy else "/chat/completions" if audio_chat else "/realtime?intent=transcription" if streaming_stt else "/audio/transcriptions" if stt else ""
	return {"family":base,"endpoint":route,"provider":provider,"presets":speech_voices(id),"supported_voices":speech_voices(id),
		"prompt_voices":live,"recording_voices":live or realtime or audio_chat or base=="gpt-4o-mini-tts",
		"expressive":live or realtime or audio_chat or base=="gpt-4o-mini-tts","streaming":live or realtime or streaming_stt or legacy or base=="gpt-transcribe",
		"conversation":live or realtime,"full_duplex":live,"transcription":stt or streaming_stt or live or realtime,
		"committed_turn_adapter":streaming_stt,"verbatim_requires_validation":live or realtime or audio_chat,
		"formats":["pcm16_16000","pcm16_24000"] if live else ["pcm16_24000"] if realtime or streaming_stt else ["wav"] if audio_chat else ["wav","pcm","mp3","opus","aac","flac"] if legacy else ["wav","flac","mp3","mp4","mpeg","mpga","m4a","ogg","webm"] if stt else [],
		"verified_at":AUDIO_VERIFIED_AT,"source_url":DIRECTORY+"/"+base if not base.is_empty() else DIRECTORY}

static func voice_compatible(id: String,voice: Variant,voice_type: String="preset") -> bool:
	if not available_for(id,"tts"):return false
	if voice is String:return voice_type=="preset" and voice in speech_voices(id)
	if not voice is Dictionary or voice.keys().size()!=1 or not voice.get("id") is String:return false
	var custom_id:=str(voice.id)
	if not custom_id.begins_with("voice_") or not valid_id(custom_id) or custom_id.length()>128:return false
	var capabilities:=voice_capabilities(id)
	return bool(capabilities.prompt_voices) if voice_type=="prompt" else bool(capabilities.recording_voices) if voice_type=="audio_sample" else false

static func _deprecation_announcement(base: String) -> String:
	if base in TTS:return "2026-10-01"
	if base in ["gpt-realtime","gpt-realtime-mini","gpt-audio","gpt-audio-mini","gpt-4o-realtime","gpt-4o-mini-realtime","gpt-4o-audio","gpt-4o-mini-audio"]:return "2026-07-20"
	if base in ["whisper-1","gpt-4o-transcribe","gpt-4o-mini-transcribe","gpt-4o-transcribe-diarize"]:return "2026-08-26"
	return ""

static func lifecycle_description(id: String) -> String:
	var life:=lifecycle(id)
	if life.status=="unknown":return "Unknown — capabilities and lifecycle have not been verified."
	if life.status=="active":return "Active · verified "+str(life.verified_at)
	return ("Retired" if life.status=="retired" else "Deprecated")+" · shutdown "+str(life.shutdown)+". Replacement: "+str(life.replacement)+"."
