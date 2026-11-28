extends Node
## Host-only OpenAI transport. No credential is written to Godot user data.
signal usage_changed

const SETTINGS_PATH := "user://host_openai.cfg"
const API_BASE := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-5.4-mini"
const MAX_INPUT_CHARS := 4000
const MAX_CHARACTER_INPUT_CHARS := 24000
const MAX_CHARACTER_INSTRUCTION_CHARS := 20000
const MAX_RESPONSE_BYTES := 262144
const MAX_IMAGE_RESPONSE_BYTES := 8 * 1024 * 1024
const TRANSCRIPTION_MODEL := "gpt-transcribe"
const SPEECH_MODEL := "gpt-realtime-2.1-mini"
const Models = preload("res://scripts/campus/ai/openai_models.gd")
const VoiceSession=preload("res://scripts/campus/ai/openai_voice_session.gd")
const TranscriptionSession=preload("res://scripts/campus/ai/openai_transcription_session.gd")
const VoiceDelivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const LANE_LIMITS:={"text":2,"background":1,"speech":3,"transcription":2,"management":1,"image":1}
const MAX_WAITERS:=32

var enabled := false
var model := DEFAULT_MODEL
var image_model := ""
var image_generation_model := ""
var image_generation_options: Dictionary={"size":"1024x1024","quality":"low","output_format":"png"}
var stt_model := TRANSCRIPTION_MODEL
var tts_model := SPEECH_MODEL
var stt_enabled := false
var tts_enabled := false
var live_model:="gpt-live-1.1"
var live_enabled:=false
var max_output_tokens := 384
var reasoning_effort := ""
var image_reasoning_effort := ""
const Usage=preload("res://scripts/campus/ai/openai_usage.gd")
var usage_tracker=Usage.new()
var usage_profile:=""
var local_usage_session:=""
var reasoning_mode:="standard"
var image_reasoning_mode:="standard"
var model_usage: Dictionary = {}
var busy := false
var speech_busy:=false
var background_busy:=false
var _background_epoch:=0
var _background_request_id:=""
var _session_key := ""
var _environment_key_disconnected := false
var _model_cache_key := ""
var _model_cache: Array[String] = []
var _test_base := ""
var _verified_signature := ""
var verification_error := ""
var _lane_active: Dictionary={}
var _lane_waiting: Dictionary={}
var _voice_requests: Dictionary={}
var _cancelled_requests: Dictionary={}
var _http_requests: Dictionary={}
var _access_failures: Dictionary={}
var _connection_epoch:=0
var _test_voice_base:=""

func _ready() -> void:
	local_usage_session="Session "+Crypto.new().generate_random_bytes(5).hex_encode()
	_load()

func host_allowed() -> bool:
	return multiplayer.is_server()

func credential_source() -> String:
	if not _session_key.is_empty():return "Session key"
	if not _credential().is_empty():return "Host environment"
	return "Not connected"

func configured() -> bool:
	return not _credential().is_empty()

func set_session_key(value: String) -> bool:
	var clean := value.strip_edges()
	if not host_allowed() or not _valid_key(clean):return false
	cancel_background_generation()
	_session_key=clean
	_connection_epoch+=1
	for session: Node in _voice_requests.values():
		if is_instance_valid(session):session.cancel()
	return true

func _valid_key(clean: String) -> bool:
	if clean.length()<20 or clean.length()>256 or not clean.begins_with("sk-"):
		return false
	for character in clean:
		if character in " \t\r\n":return false
	return true

func clear_session_key() -> void:
	if host_allowed():
		cancel_background_generation()
		_session_key=""
		_verified_signature=""
		_connection_epoch+=1
		for session: Node in _voice_requests.values():
			if is_instance_valid(session):session.cancel()

func disconnect_key() -> void:
	if not host_allowed():return
	clear_session_key()
	_environment_key_disconnected=true
	_model_cache_key=""
	_model_cache.clear()
	verification_error=""

func configure(next_model: String, output_limit: int, next_effort: String, next_enabled: bool) -> Error:
	if not host_allowed() or not Models.available_for(next_model,"text"):return ERR_INVALID_PARAMETER
	if next_effort!=Models.normalize_effort(next_model,next_effort):return ERR_INVALID_PARAMETER
	if next_model!=model or next_effort!=reasoning_effort or not next_enabled:cancel_background_generation()
	var previous: Array=[model,max_output_tokens,reasoning_effort,enabled]
	model=next_model
	max_output_tokens=clampi(output_limit,16,32768)
	reasoning_effort=next_effort
	enabled=next_enabled
	var error:=_save()
	if error!=OK:
		model=previous[0];max_output_tokens=previous[1];reasoning_effort=previous[2];enabled=previous[3]
	return error

func test_connection() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET,"/models/"+model.uri_encode(),{},false)

func list_models(key: String="", refresh:=false) -> Dictionary:
	key=key.strip_edges()
	if not host_allowed():return {"ok":false,"error":"Only the host can use the OpenAI connection."}
	if not key.is_empty() and not _valid_key(key):return {"ok":false,"error":"Enter a valid OpenAI API key."}
	if key.is_empty():key=_credential()
	var cache_key: String=(key+"\n"+_test_base).sha256_text()
	if not refresh and cache_key==_model_cache_key:return {"ok":true,"models":_model_cache.duplicate()}
	var result:=await _call(HTTPClient.METHOD_GET,"/models",{},false,{"key":key})
	if result.get("ok",false):
		_model_cache_key=cache_key
		_model_cache.assign(result.models)
	return result

func preview_setup_prompt(prompt: String, draft: Dictionary) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Enter a prompt of 1 to 4,000 characters."}
	var choice:=str(draft.model)
	var key:=str(draft.key) if not str(draft.key).is_empty() else _credential()
	var effort:=str(draft.get("effort",""))
	var output:=int(draft.output)
	var signature:=_signature(key,choice,effort,output,str(draft.get("mode","standard")))
	var result:=await _request_text(prompt,choice,output,effort,false,draft)
	if result.get("ok",false):result.signature=signature
	return result

func accept_setup(draft: Dictionary, signature: String) -> Error:
	var key:=str(draft.key)
	if not host_allowed() or (key.is_empty() and not configured()) or (not key.is_empty() and not _valid_key(key)):
		return ERR_INVALID_PARAMETER
	var choices: Dictionary=draft.get("modalities",{})
	for purpose in ["image","image_generation","stt","tts"]:
		var id:=str(choices.get(purpose,""))
		if not id.is_empty() and not Models.available_for(id,purpose):
			var previous_selection: String={"image":image_model,"image_generation":image_generation_model,"stt":stt_model,"tts":tts_model,"live":live_model}.get(purpose,"")
			if id!=previous_selection or purpose in ["image","image_generation"] or bool(draft.get(purpose+"_enabled",false)):return ERR_INVALID_PARAMETER
	var next_image:=str(choices.get("image",image_model))
	var next_image_effort:=str(draft.get("image_effort",image_reasoning_effort))
	if next_image_effort!=Models.normalize_effort(next_image,next_image_effort):return ERR_INVALID_PARAMETER
	var selected_mode:=str(draft.get("mode","standard"))
	var selected_image_mode:=str(draft.get("image_mode","standard"))
	if not _mode_allowed(str(draft.model),selected_mode) or not _mode_allowed(next_image,selected_image_mode):return ERR_INVALID_PARAMETER
	var next_generation:=str(choices.get("image_generation",image_generation_model))
	var generation_options: Variant=draft.get("image_generation_options",image_generation_options)
	if not generation_options is Dictionary:return ERR_INVALID_PARAMETER
	if not next_generation.is_empty() and not Models.valid_image_generation_options(next_generation,generation_options):return ERR_INVALID_PARAMETER
	var previous: Array=[image_model,stt_model,tts_model,stt_enabled,tts_enabled,image_generation_model,image_reasoning_effort,reasoning_mode,image_reasoning_mode,usage_profile,live_model,live_enabled,image_generation_options.duplicate()]
	reasoning_mode=selected_mode
	image_reasoning_mode=selected_image_mode
	usage_profile=_clean_profile(str(draft.get("usage_profile",usage_profile)))
	image_model=next_image
	image_reasoning_effort=next_image_effort
	image_generation_model=next_generation
	image_generation_options={"size":str(generation_options.get("size","1024x1024")),"quality":str(generation_options.get("quality","low")),"output_format":"png"}
	stt_model=str(choices.get("stt",stt_model))
	tts_model=str(choices.get("tts",tts_model))
	stt_enabled=bool(draft.get("stt_enabled",stt_enabled)) and not stt_model.is_empty()
	tts_enabled=bool(draft.get("tts_enabled",tts_enabled)) and not tts_model.is_empty()
	live_model=str(choices.get("live",live_model))
	live_enabled=false # Retired setting cannot enable continuous microphone sessions.
	var error:=configure(str(draft.model),int(draft.output),str(draft.get("effort","")),true)
	if error!=OK:
		image_model=previous[0];stt_model=previous[1];tts_model=previous[2];stt_enabled=previous[3];tts_enabled=previous[4]
		image_generation_model=previous[5]
		image_generation_options=previous[12]
		image_reasoning_effort=previous[6]
		reasoning_mode=previous[7];image_reasoning_mode=previous[8];usage_profile=previous[9]
		live_model=previous[10];live_enabled=previous[11]
		return error
	if not key.is_empty():set_session_key(key)
	if signature==_connection_signature():
		_verified_signature=signature
		verification_error=""
	return OK

func _connection_signature() -> String:
	return _signature(_credential(),model,reasoning_effort,max_output_tokens,reasoning_mode)

func _signature(key: String, choice: String, effort: String, output: int, mode: String) -> String:
	return JSON.stringify([key,choice,effort,output,mode,_test_base]).sha256_text()

func verified_for_class() -> bool:
	return enabled and configured() and _verified_signature==_connection_signature()

func ready_for_class() -> bool:
	return enabled and configured()

func class_connection_status() -> String:
	if verified_for_class():return "Connected. AI teaching available."
	if not enabled or not configured():return "Add your API key in OpenAI Settings before starting the game."
	if not verification_error.is_empty():return "Connection failed. "+verification_error
	return "API key connected. The model is checked when class first uses it."

func verify_class_connection() -> Dictionary:
	var signature:=_connection_signature()
	var result:=await respond("Reply with the single word Ready.")
	if signature!=_connection_signature():return {"ok":false,"error":"The selected connection changed. Test it again."}
	if result.get("ok",false):
		_verified_signature=signature
		verification_error=""
		return {"ok":true,"message":class_connection_status()}
	if not busy:
		_verified_signature=""
		verification_error=str(result.get("error","OpenAI did not return a response."))
	return result

func respond(prompt: String,timeout := 180.0) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Enter a prompt of 1 to 4,000 characters."}
	var signature:=_connection_signature()
	var response:=await _request_text(prompt,model,max_output_tokens,reasoning_effort,true,{},timeout)
	if response.get("ok",false) and signature==_connection_signature():
		_verified_signature=signature
		verification_error=""
	return response

func plan_visual(prompt: String) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Visual plan context is too large."}
	return await _request_text(prompt,model,clampi(max_output_tokens,1600,2400),reasoning_effort,true,{},24.)

func respond_character(instructions: String,context: Dictionary,dialogue: String,visual := false) -> Dictionary:
	return await _character_request(instructions,context,dialogue,clampi(max_output_tokens,1800 if visual else 1400,4096),24.0)

func interpret_character(instructions: String,context: Dictionary,dialogue: String) -> Dictionary:
	return await _character_request(instructions,context,dialogue,clampi(max_output_tokens,900,2048),18.0)

## Independent bounded population lane, canceled on credential/model changes.
func generate_character_dossier(instructions: String, context: Dictionary, output_limit: int=10000) -> Dictionary:
	if not host_allowed() or not ready_for_class():return {"ok":false,"error":"Character generation is unavailable."}
	if background_busy:return {"ok":false,"error":"A character generation job is already running."}
	var input:=JSON.stringify(context)
	if instructions.length()>24000 or input.length()>60000:return {"ok":false,"error":"Character generation context exceeds its bounded budget."}
	var epoch:=_background_epoch
	var id:=Crypto.new().generate_random_bytes(12).hex_encode()
	background_busy=true
	_background_request_id=id
	var result:=await _request_text(input,model,clampi(output_limit,4096,16000),reasoning_effort,true,{"_character_background":true,"request_type":"feature","request_id":id},75.0,instructions)
	if _background_request_id==id:
		background_busy=false
		_background_request_id=""
	if epoch!=_background_epoch:
		result.ok=false
		result.cancelled=true
		result.erase("text")
		result.error="Character generation was cancelled."
	return result

func cancel_background_generation() -> void:
	_background_epoch+=1
	if not _background_request_id.is_empty():_cancelled_requests[_background_request_id]=true

func _character_request(instructions: String,context: Dictionary,dialogue: String,output: int,timeout: float) -> Dictionary:
	if dialogue.length()>8000:return {"ok":false,"error":"The character message is too long."}
	var request:={"context":context.duplicate(true),"player_dialogue":dialogue}
	var input:=JSON.stringify(request)
	var reduced: Array[String]=[]
	# Retain identity, worldview, current affect, semantic interpretation and the
	# most recent turns. Retrieval storage is not truncated when prompt size grows.
	for field in ["recent_experiences","memories","reported_facts","topic_summaries","earlier_turns","prior_turns"]:
		var entries: Variant=request.context.get(field)
		if not entries is Array:continue
		var keep:=4 if field in ["earlier_turns","prior_turns"] else 2
		while input.length()>MAX_CHARACTER_INPUT_CHARS and entries.size()>keep:
			if field in ["reported_facts","memories","topic_summaries"]:entries.pop_back()
			else:entries.pop_front()
			if field not in reduced:reduced.append(field)
			input=JSON.stringify(request)
	if input.length()>MAX_CHARACTER_INPUT_CHARS or instructions.length()>MAX_CHARACTER_INSTRUCTION_CHARS:
		return {"ok":false,"error":"Character context exceeds its bounded budget.","context_chars":input.length(),"instruction_chars":instructions.length(),"reduced_fields":reduced}
	var result:=await _request_text(input,model,output,reasoning_effort,true,{},timeout,instructions)
	result.context_chars=input.length()
	result.instruction_chars=instructions.length()
	result.reduced_fields=reduced
	return result

func respond_with_image(prompt: String,jpeg: PackedByteArray,draft: Dictionary={}) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS or jpeg.size()<4 or jpeg.size()>262144 or jpeg[0]!=255 or jpeg[1]!=216:return {"ok":false,"error":"The image or question is too large."}
	var content: Array=[{"type":"input_text","text":prompt},{"type":"input_image","image_url":"data:image/jpeg;base64,"+Marshalls.raw_to_base64(jpeg),"detail":"low"}]
	var choice:=str(draft.get("modalities",{}).get("image",image_model))
	if choice.is_empty() and draft.is_empty():choice=model
	if not Models.available_for(choice,"image"):return {"ok":false,"error":"Choose an image analysis model in OpenAI Settings."}
	var effort:=str(draft.get("image_effort",image_reasoning_effort))
	return await _request_text(content,choice,int(draft.get("output",max_output_tokens)),Models.normalize_effort(choice,effort),draft.is_empty(),draft)

func speak(text: String,draft: Dictionary={},voice: Variant="alloy",delivery: Dictionary={}) -> Dictionary:
	var pinned_model:=str(delivery.get("model",""))
	var choice:=str(draft.get("modalities",{}).get("tts",pinned_model if not pinned_model.is_empty() else tts_model))
	if not bool(draft.get("tts_enabled",tts_enabled)) or not Models.available_for(choice,"tts"):
		return {"ok":false,"error":"Enable character speech and choose an operational voice model in OpenAI Settings.","retryable":false}
	var voice_type:=str(delivery.get("voice_type","preset"))
	if not Models.voice_compatible(choice,voice,voice_type):
		return {"ok":false,"error":"This permanent voice is incompatible with the selected speech model. Its voice has not changed.","retryable":false,"code":"incompatible_voice"}
	if text.strip_edges().is_empty() or text.length()>1600:return {"ok":false,"error":"The speech exceeds the conversation playback budget.","retryable":false}
	delivery=VoiceDelivery.for_text(delivery,text)
	if str(delivery.get("instructions","")).length()>12000:return {"ok":false,"error":"The character's performance instructions exceed the bounded voice context; no instructions were truncated.","retryable":false}
	var context:=draft.duplicate(true)
	context.request_id=str(delivery.get("request_id",Crypto.new().generate_random_bytes(12).hex_encode()))
	if draft.is_empty():context.request_type="feature"
	if Models.verified_family(choice) in Models.LIVE+Models.REALTIME:
		return await _render_voice(text,choice,voice,voice_type,delivery,context,draft.is_empty())
	if Models.verified_family(choice)=="gpt-audio-1.5":
		context.expected_spoken_text=text
		var payload:={"model":choice,"modalities":["text","audio"],"audio":{"voice":voice,"format":"wav"},"messages":[{"role":"system","content":"Perform the supplied words exactly, with no paraphrase, added words, or read-out instructions. "+str(delivery.get("instructions",""))},{"role":"user","content":text}],"store":false}
		var result:=await _call(HTTPClient.METHOD_POST,"/chat/completions",payload,draft.is_empty(),context,120.0,"tts")
		result.provider="openai_audio_chat";result.request_id=context.request_id
		return result
	var payload:={"model":choice,"input":text,"voice":voice,"response_format":"wav"}
	if not delivery.is_empty():
		payload.speed=clampf(float(delivery.get("speed",1.)),.5,1.5)
		if Models.voice_capabilities(choice).expressive:
			var directions:=str(delivery.get("instructions",""))
			if directions.length()>4096:return {"ok":false,"error":"Legacy speech instructions exceed the documented 4096-character limit. Choose a modern compatible voice model.","retryable":false}
			payload.instructions=directions
	var result:=await _call(HTTPClient.METHOD_POST,"/audio/speech",payload,draft.is_empty(),context,60.0,"tts")
	result.provider="openai_speech"
	result.request_id=context.request_id
	return result

func _render_voice(text: String,choice: String,voice: Variant,voice_type: String,delivery: Dictionary,draft: Dictionary,needs_enabled: bool) -> Dictionary:
	var access:=_voice_access(draft,needs_enabled)
	if not access.ok:return access
	var id:=str(draft.request_id)
	if not await _acquire_lane("speech",id):return _queue_error(id)
	var session:=VoiceSession.new()
	add_child(session)
	_voice_requests[id]=session
	var results: Array=[]
	session.speech_completed.connect(func(value: Dictionary):results.append(value))
	var started:=Time.get_ticks_msec()
	var begun:=session.begin(choice,voice,voice_type,str(access.key),str(delivery.get("instructions","")),[],text,_test_voice_base,id)
	if not begun.ok:
		_voice_requests.erase(id);_release_lane("speech");session.queue_free()
		return begun
	var epoch:=_connection_epoch
	while results.is_empty() and is_instance_valid(session):
		if _cancelled_requests.has(id) or epoch!=_connection_epoch:session.cancel()
		await get_tree().process_frame
	var result: Dictionary=results[0] if not results.is_empty() else {"ok":false,"error":"The voice session ended.","retryable":true}
	var availability_key:=_account_cache_id(str(access.key))+":"+choice
	if str(result.get("code","")) in ["model_not_found","permission_denied","insufficient_permissions"] and voice_type=="preset":_access_failures[availability_key]=str(result.code)
	elif result.get("ok",false):_access_failures.erase(availability_key)
	# Allow the Live terminal usage event to drain before releasing the transport.
	# No client audio can become audible after cancellation, even if close is slow.
	if is_instance_valid(session) and session.state!="closed":
		session.close_session()
		while is_instance_valid(session) and session.state!="closed":await get_tree().process_frame
	var metadata: Dictionary=result.get("_api_metadata",{})
	var seconds: float=-1.0
	if is_instance_valid(session) and Models.supports(choice,"live"):
		metadata={"usage":{"seconds":session.latest_usage_seconds},"model":choice}
		seconds=session.latest_usage_seconds
		result.usage_confirmed=session.final_usage_confirmed
	result.measurement=_record_request(choice,"tts",metadata,bool(result.get("ok",false)),Time.get_ticks_msec()-started,draft,{},seconds,text.length())
	result.erase("_api_metadata")
	_voice_requests.erase(id);_cancelled_requests.erase(id);_release_lane("speech")
	if is_instance_valid(session):session.queue_free()
	return result

func create_prompt_voice(voice_name: String,prompt: String,script_hint: String="",draft: Dictionary={}) -> Dictionary:
	if voice_name.strip_edges().is_empty() or voice_name.length()>256 or prompt.strip_edges().is_empty() or prompt.length()>2000:
		return {"ok":false,"error":"Voice names allow 256 characters and descriptions allow 2,000 characters.","retryable":false}
	if script_hint.length()>2000 or (not script_hint.is_empty() and script_hint.strip_edges().length()<20):
		return {"ok":false,"error":"Use a representative preview script of 20–2,000 characters, or leave it blank.","retryable":false}
	var payload:={"type":"prompt","name":voice_name,"prompt":prompt,"model":"auto"}
	if not script_hint.is_empty():payload.script_hint=script_hint
	# Creation is deliberately never retried automatically: a lost response can
	# already have allocated a voice and another POST would consume more capacity.
	return await _call(HTTPClient.METHOD_POST,"/audio/voices",payload,false,draft,90.0,"voice_creation")

func create_live_conversation(_context: Dictionary,_voice: Variant,_delivery: Dictionary={}) -> Dictionary:
	# Old scene/scripts cannot reactivate microphone streaming by toggling a
	# stale preference. GPT-Live remains supported through speak() exclusively.
	return {"ok":false,"error":"Native Live conversations were retired. Use recorded speech recognition and the normal character dialogue pipeline.","code":"native_live_retired","retryable":false}

func cancel_speech_request(id: String) -> void:
	if id.is_empty():return
	_cancelled_requests[id]=true
	if _cancelled_requests.size()>256:_cancelled_requests.erase(_cancelled_requests.keys()[0])
	var session: Node=_voice_requests.get(id)
	if is_instance_valid(session):session.cancel()

func _voice_access(draft: Dictionary,needs_enabled: bool) -> Dictionary:
	if not host_allowed():return {"ok":false,"error":"Only the host can access AI voices.","retryable":false}
	if needs_enabled and not enabled:return {"ok":false,"error":"The host's AI connection is disabled.","retryable":false}
	var key:=str(draft.get("key",""))
	if key.is_empty():key=_credential()
	if key.is_empty():return {"ok":false,"error":"Connect the host's OpenAI API key in AI Settings.","retryable":false}
	if not _valid_key(key):return {"ok":false,"error":"Invalid OpenAI API key format.","retryable":false}
	return {"ok":true,"key":key}

func model_status(id: String,purpose: String,draft: Dictionary={}) -> Dictionary:
	var result:=Models.lifecycle(id).duplicate(true)
	result.compatible=Models.supports(id,purpose)
	var account:=_account_cache_id(str(draft.get("key","")))
	var catalog_current:=_model_cache_key==account
	result.account_listed=catalog_current and id in _model_cache
	result.catalog_known=catalog_current
	result.access_failure=_access_failures.has(account+":"+id)
	result.account_availability="unavailable" if result.access_failure else "available" if result.account_listed else "unavailable" if catalog_current else "unknown"
	return result

func _account_cache_id(key: String="") -> String:
	if key.is_empty():key=_credential()
	return (key+"\n"+_test_base).sha256_text()

func voice_diagnostics() -> Dictionary:
	var active: Array=[]
	for session: Node in _voice_requests.values():
		if is_instance_valid(session):active.append(session.diagnostics())
	var queued:={}
	for lane in _lane_waiting:queued[lane]=_lane_waiting[lane].size()
	return {"active":active,"request_lanes":_lane_active.duplicate(),"queued":queued,"tts_model":tts_model,"stt_model":stt_model,"speech_only":true,"microphone_streaming":false,"lifecycle":Models.lifecycle(tts_model)}

func generate_image(prompt: String, draft: Dictionary={}) -> Dictionary:
	var choice:=str(draft.get("modalities",{}).get("image_generation",image_generation_model))
	if not Models.available_for(choice,"image_generation"):
		return {"ok":false,"error":"Choose an image generation model."}
	prompt=prompt.strip_edges()
	if prompt.is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Enter an image prompt of up to %d characters."%MAX_INPUT_CHARS}
	var options: Variant=draft.get("image_generation_options",image_generation_options)
	if not options is Dictionary or not Models.valid_image_generation_options(choice,options):return {"ok":false,"error":"Choose image dimensions and quality supported by the selected model."}
	var payload:={"model":choice,"prompt":prompt,"size":str(options.get("size","1024x1024")),"output_format":"png","quality":str(options.get("quality","low")),"n":1}
	return await _call(HTTPClient.METHOD_POST,"/images/generations",payload,draft.is_empty(),draft)

func _request_text(input: Variant, choice: String, output: int, effort: String, needs_enabled: bool, draft := {}, timeout := 180.0,trusted_instructions := "") -> Dictionary:
	var path:=Models.endpoint(choice)
	if path.is_empty() or Models.lifecycle(choice).status=="retired":
		return {"ok":false,"error":"Choose an available model for this request."}
	var category:="image" if input is Array else "text"
	var setting:="image_mode" if category=="image" else "mode"
	var mode:=str(draft.get(setting,image_reasoning_mode if category=="image" else reasoning_mode))
	if not _mode_allowed(choice,mode):mode="standard"
	if effort!=Models.normalize_effort(choice,effort):return {"ok":false,"error":"This model does not support that thinking effort."}
	var payload: Dictionary={"model":choice}
	if draft.get("request_type","")=="comparison":payload.service_tier="default"
	if path=="/chat/completions":
		var content: Variant=input
		if input is Array:
			content=[{"type":"text","text":input[0].text},{"type":"image_url","image_url":{"url":input[1].image_url,"detail":"low"}}]
		payload.messages=[{"role":"user","content":content}]
		if not trusted_instructions.is_empty():payload.messages.push_front({"role":"system","content":trusted_instructions})
		payload.max_completion_tokens=output
	else:
		payload.input=input if input is String else [{"role":"user","content":input}]
		if not trusted_instructions.is_empty():payload.instructions=trusted_instructions
		payload.max_output_tokens=output
		payload.store=false
		if not effort.is_empty():payload.reasoning={"effort":effort}
		if mode=="pro":payload.get_or_add("reasoning",{}).mode="pro"
	return await _call(HTTPClient.METHOD_POST,path,payload,needs_enabled,draft,timeout,category)

func moderate(input: String) -> Dictionary:
	if input.strip_edges().is_empty() or input.length()>8000:return {"ok":false,"error":"The message is too long."}
	var result: Dictionary=await _call(HTTPClient.METHOD_POST,"/moderations",{"model":"omni-moderation-latest","input":input},true)
	return result

func transcribe_wav(wav: PackedByteArray,draft: Dictionary={}) -> Dictionary:
	if not valid_transcription_wav(wav):return {"ok":false,"error":"Record 0.15–180 seconds of mono 16 kHz PCM16 speech.","retryable":false}
	var access:=_voice_access(draft,draft.is_empty())
	if not access.ok:return access
	var choice:=str(draft.get("modalities",{}).get("stt",stt_model))
	if not bool(draft.get("stt_enabled",stt_enabled)) or not Models.available_for(choice,"stt"):
		return {"ok":false,"error":"Speech recognition is disabled or its model has retired.","retryable":false}
	var id:=str(draft.get("request_id",Crypto.new().generate_random_bytes(12).hex_encode()))
	if not await _acquire_lane("transcription",id):return _queue_error(id)
	var now:=Time.get_ticks_msec()
	if Models.verified_family(choice) in Models.STREAMING_STT:
		var result:=await _stream_transcription(wav,choice,str(access.key),id,draft)
		_release_lane("transcription")
		var metadata: Dictionary=result.get("_api_metadata",{})
		result.measurement=_record_request(choice,"stt",metadata,bool(result.get("ok",false)),Time.get_ticks_msec()-now,draft,{},float(wav.size()-44)/32000.)
		result.erase("_api_metadata");_cancelled_requests.erase(id)
		return result
	var boundary:="LabVoltVoice"+Crypto.new().generate_random_bytes(16).hex_encode()
	var fields:={"model":choice}
	var hint:=str(draft.get("transcription_prompt",""))
	if not hint.is_empty() and Models.verified_family(choice)!="gpt-4o-transcribe-diarize":fields.prompt=hint.left(2000)
	if Models.verified_family(choice)=="gpt-4o-transcribe-diarize":fields.chunking_strategy="auto";fields.response_format="json"
	var body:=PackedByteArray()
	for name: String in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"%[boundary,name,fields[name]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.wav\"\r\nContent-Type: audio/wav\r\n\r\n"%boundary).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n"%boundary).to_utf8_buffer())
	var headers:=PackedStringArray(["Authorization: Bearer "+str(access.key),"Content-Type: multipart/form-data; boundary="+boundary])
	var base:=_test_base if not _test_base.is_empty() else API_BASE
	var raw:=await _http_exchange(base+"/audio/transcriptions",headers,HTTPClient.METHOD_POST,body,90.0,131072,id)
	_release_lane("transcription")
	var result: Dictionary
	if not raw.ok:
		result=raw
	elif int(raw.code)<200 or int(raw.code)>=300:
		result=_read_response(HTTPRequest.RESULT_SUCCESS,int(raw.code),raw.body,"/audio/transcriptions",choice)
	else:
		var parsed: Variant=JSON.parse_string((raw.body as PackedByteArray).get_string_from_utf8())
		if not parsed is Dictionary:result={"ok":false,"error":"Speech recognition returned an unreadable transcript.","retryable":false}
		else:
			var words:=str(parsed.get("text","")).strip_edges()
			if words.length()>8000:result={"ok":false,"error":"The recognized utterance exceeds the conversation limit; no partial question was sent.","retryable":false}
			else:result={"ok":true,"text":words,"_api_metadata":parsed} if not words.is_empty() else {"ok":false,"error":"No speech was recognized.","retryable":false}
	var metadata: Dictionary=result.get("_api_metadata",{})
	result.measurement=_record_request(choice,"stt",metadata,bool(result.get("ok",false)),Time.get_ticks_msec()-now,draft,{},float(wav.size()-44)/32000.0)
	result.erase("_api_metadata")
	_cancelled_requests.erase(id)
	return result

func _stream_transcription(wav: PackedByteArray,choice: String,key: String,id: String,draft: Dictionary) -> Dictionary:
	var session:=TranscriptionSession.new()
	var epoch:=_connection_epoch
	var begun:=session.begin(choice,key,wav.slice(44),_test_voice_base,id)
	if not begun.get("ok",false):return begun
	var last_partial:=""
	var progress: Variant=draft.get("_transcription_progress")
	while session.state!="closed" and is_inside_tree():
		if epoch!=_connection_epoch or _cancelled_requests.has(id):
			session.cancel();break
		session.poll()
		if session.partial!=last_partial:
			last_partial=session.partial
			if progress is Callable and progress.is_valid():progress.call(last_partial)
		if session.state!="closed":await get_tree().process_frame
	if session.state!="closed":session.cancel()
	return session.result

static func valid_transcription_wav(wav: PackedByteArray) -> bool:
	return wav.size()>=4844 and wav.size()<=5760044 and wav.size()%2==0 and wav.slice(0,4).get_string_from_ascii()=="RIFF" and wav.slice(8,12).get_string_from_ascii()=="WAVE" and wav.slice(12,16).get_string_from_ascii()=="fmt " and wav.decode_u32(16)==16 and wav.decode_u16(20)==1 and wav.decode_u16(22)==1 and wav.decode_u32(24)==16000 and wav.decode_u32(28)==32000 and wav.decode_u16(32)==2 and wav.decode_u16(34)==16 and wav.slice(36,40).get_string_from_ascii()=="data" and wav.decode_u32(40)==wav.size()-44 and wav.decode_u32(4)==wav.size()-8

func set_local_test_endpoint(value: String) -> bool:
	if not OS.has_feature("editor"):return false
	var pattern := RegEx.create_from_string("^http://127\\.0\\.0\\.1:[0-9]{2,5}/v1$")
	if pattern.search(value)==null:return false
	_test_base=value
	return true

func set_local_test_voice_endpoint(value: String) -> bool:
	if not OS.has_feature("editor") or RegEx.create_from_string("^ws://127\\.0\\.0\\.1:[0-9]{2,5}/v1$").search(value)==null:return false
	_test_voice_base=value
	return true

func _acquire_lane(lane: String,id: String) -> bool:
	var queue: Array=_lane_waiting.get_or_add(lane,[])
	if queue.size()>=MAX_WAITERS:return false
	var epoch:=_connection_epoch
	var ticket:={"id":id,"created":Time.get_ticks_msec()}
	queue.append(ticket)
	while is_inside_tree():
		if epoch!=_connection_epoch:_cancelled_requests[id]=true
		if _cancelled_requests.has(id) or Time.get_ticks_msec()-int(ticket.created)>30000:
			queue.erase(ticket);return false
		if queue[0]==ticket and int(_lane_active.get(lane,0))<int(LANE_LIMITS.get(lane,1)):
			queue.pop_front()
			_lane_active[lane]=int(_lane_active.get(lane,0))+1
			busy=int(_lane_active.get("text",0))>0
			speech_busy=int(_lane_active.get("speech",0))>0
			return true
		await get_tree().process_frame
	queue.erase(ticket)
	return false

func _release_lane(lane: String) -> void:
	_lane_active[lane]=maxi(0,int(_lane_active.get(lane,0))-1)
	busy=int(_lane_active.get("text",0))>0
	speech_busy=int(_lane_active.get("speech",0))>0

func _queue_error(id: String) -> Dictionary:
	var canceled:=_cancelled_requests.has(id)
	_cancelled_requests.erase(id)
	return {"ok":false,"error":"Speech canceled." if canceled else "The voice request queue is full or timed out. Please try again.","canceled":canceled,"retryable":not canceled,"retry_after_ms":1000}

func _http_exchange(url: String,headers: PackedStringArray,method: HTTPClient.Method,body: PackedByteArray,timeout: float,limit: int,id: String) -> Dictionary:
	var request:=HTTPRequest.new()
	request.timeout=timeout
	request.body_size_limit=limit
	request.max_redirects=0
	add_child(request)
	_http_requests[id]=request
	var completed: Array=[]
	request.request_completed.connect(func(result: int,code: int,response_headers: PackedStringArray,response_body: PackedByteArray):completed.append([result,code,response_headers,response_body]))
	var epoch:=_connection_epoch
	var error:=request.request_raw(url,headers,method,body)
	if error!=OK:
		_http_requests.erase(id);request.queue_free()
		return {"ok":false,"error":"Could not start the OpenAI request.","retryable":true,"retry_after_ms":1000}
	while completed.is_empty() and is_inside_tree():
		if _cancelled_requests.has(id) or epoch!=_connection_epoch:
			request.cancel_request();_http_requests.erase(id);request.queue_free()
			return {"ok":false,"error":"The request was canceled or the host connection changed.","canceled":true,"retryable":false}
		await get_tree().process_frame
	_http_requests.erase(id);request.queue_free()
	if _cancelled_requests.has(id) or epoch!=_connection_epoch:return {"ok":false,"error":"The request was canceled or the host connection changed.","canceled":true,"retryable":false}
	if completed.is_empty() or int(completed[0][0])!=HTTPRequest.RESULT_SUCCESS:
		return {"ok":false,"error":"OpenAI could not be reached or timed out.","retryable":true,"retry_after_ms":1000}
	var retry_after:=1000
	for header: String in completed[0][2]:
		if header.to_lower().begins_with("retry-after:"):
			var seconds:=header.substr(header.find(":")+1).strip_edges()
			if seconds.is_valid_float():retry_after=clampi(roundi(seconds.to_float()*1000.),250,30000)
	return {"ok":true,"code":int(completed[0][1]),"body":completed[0][3],"retry_after_ms":retry_after}

func _call(method: HTTPClient.Method,path: String,payload: Dictionary,needs_enabled: bool,draft := {},timeout := 180.0,purpose := "") -> Dictionary:
	var access:=_voice_access(draft,needs_enabled)
	if not access.ok:return access
	var request_model:=str(payload.get("model",model))
	if not Models.valid_id(request_model):return {"ok":false,"error":"Choose a valid model ID in OpenAI Settings.","retryable":false}
	var speech:=path=="/audio/speech" or purpose=="tts"
	var background:=bool(draft.get("_character_background",false))
	var connection_signature:=_connection_signature()
	var background_epoch:=_background_epoch
	var lane:="background" if background else "speech" if speech else "management" if method==HTTPClient.METHOD_GET or path=="/audio/voices" else "image" if path=="/images/generations" else "text"
	var id:=str(draft.get("request_id",Crypto.new().generate_random_bytes(12).hex_encode()))
	if not await _acquire_lane(lane,id):return _queue_error(id)
	var started:=Time.get_ticks_msec()
	var headers:=PackedStringArray(["Authorization: Bearer "+str(access.key),"Content-Type: application/json"])
	var base:=_test_base if not _test_base.is_empty() else API_BASE
	var limit:=8388608 if speech else 2097152 if path=="/models" else MAX_IMAGE_RESPONSE_BYTES if path=="/images/generations" else MAX_RESPONSE_BYTES
	var raw:=await _http_exchange(base+path,headers,method,JSON.stringify(payload).to_utf8_buffer() if method==HTTPClient.METHOD_POST else PackedByteArray(),timeout,limit,id)
	_release_lane(lane)
	var response: Dictionary=raw if not raw.ok else _read_response(HTTPRequest.RESULT_SUCCESS,int(raw.code),raw.body,path,request_model)
	if speech and path=="/chat/completions" and response.get("ok",false):
		if not VoiceSession.transcript_matches(str(draft.get("expected_spoken_text","")),str(response.get("transcript",""))):
			response.erase("stream");response.ok=false;response.error="Generated speech did not match the validated dialogue. No mismatched audio was played.";response.code="speech_transcript_mismatch";response.retryable=true
		else:response.transcript_verified=true;response.text=str(draft.expected_spoken_text)
	if raw.ok:
		response.status=int(raw.code)
		response.retryable=int(raw.code)==429 or int(raw.code)>=500
		response.retry_after_ms=int(raw.retry_after_ms) if response.retryable else 0
		var availability_key:=_account_cache_id(str(access.key))+":"+request_model
		if int(raw.code) in [403,404] and path!="/audio/voices" and not (speech and (payload.get("voice") is Dictionary or payload.get("audio",{}).get("voice") is Dictionary)):_access_failures[availability_key]=int(raw.code)
		elif response.get("ok",false):_access_failures.erase(availability_key)
	if path=="/audio/voices" and not response.get("ok",false):
		response.retryable=false
		if not raw.ok or int(raw.get("code",0))>=500:
			response.error="Voice creation could not be confirmed. Check the OpenAI voice dashboard before creating another candidate; the first request may have succeeded."
			response.creation_uncertain=true
	if method==HTTPClient.METHOD_POST and path!="/audio/voices":
		if background:purpose="character_generation"
		if purpose.is_empty():purpose={"/images/generations":"image_generation","/audio/speech":"tts","/moderations":"moderation"}.get(path,"text")
		var raw_data: Variant=response.get("_api_metadata",{})
		if not raw_data is Dictionary:raw_data={}
		var clip: AudioStreamWAV=response.get("stream")
		var characters: int=str(payload.get("input","")).length() if purpose=="tts" else -1
		response.measurement=_record_request(request_model,purpose,raw_data,bool(response.get("ok",false)),Time.get_ticks_msec()-started,draft,payload.get("reasoning",{}),clip.get_length() if clip!=null else -1.,characters)
		response.erase("_api_metadata")
	if (lane=="text" and draft.is_empty() or background) and connection_signature==_connection_signature() and (not background or background_epoch==_background_epoch) and raw.ok and int(raw.code) in [401,403,404]:
		_verified_signature=""
		verification_error=str(response.get("error","Connection verification is required."))
	_cancelled_requests.erase(id)
	return response

func _read_response(result: int,code: int,body: PackedByteArray,path: String,request_model: String) -> Dictionary:
	if result!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"error":"OpenAI could not be reached or timed out."}
	if code==401:return {"ok":false,"error":"OpenAI rejected the API key."}
	if code==403:return {"ok":false,"error":"This API key cannot access the selected model."}
	if code==404:return {"ok":false,"error":"The selected OpenAI model was not found."}
	if code==429:return {"ok":false,"error":"OpenAI is rate limiting this key. Try again later."}
	if code>=500:return {"ok":false,"error":"OpenAI is temporarily unavailable."}
	if code<200 or code>=300:return {"ok":false,"error":"OpenAI rejected the request (HTTP %d)."%code}
	if path=="/audio/speech":
		if body.size()<44 or body.slice(0,4).get_string_from_ascii()!="RIFF" or body.slice(8,12).get_string_from_ascii()!="WAVE":
			return {"ok":false,"error":"OpenAI returned an unreadable voice clip."}
		var wav:=_finish_streamed_wav(body)
		if wav.is_empty():return {"ok":false,"error":"OpenAI returned an unreadable voice clip."}
		var stream:=AudioStreamWAV.load_from_buffer(wav)
		if stream==null or stream.data.is_empty():return {"ok":false,"error":"OpenAI returned an unreadable voice clip."}
		return {"ok":true,"stream":stream}
	var parser:=JSON.new()
	if parser.parse(body.get_string_from_utf8())!=OK:return {"ok":false,"error":"OpenAI returned an unreadable response."}
	var parsed: Variant=parser.data
	if not parsed is Dictionary:return {"ok":false,"error":"OpenAI returned an unreadable response."}
	if path=="/models":
		if not parsed.get("data") is Array:return {"ok":false,"error":"OpenAI did not return a model list."}
		var unique: Dictionary={}
		for entry in parsed.data:
			if entry is Dictionary and entry.get("id") is String and Models.valid_id(entry.id):unique[entry.id]=true
		var ids:=unique.keys()
		ids.sort()
		return {"ok":true,"models":ids}
	if path.begins_with("/models/"):
		return {"ok":true,"message":"Connected to OpenAI. Model is available."} if str(parsed.get("id",""))==request_model else {"ok":false,"error":"OpenAI did not confirm the selected model."}
	var response:=_decode_body(path,parsed)
	response._api_metadata={"usage":parsed.get("usage",{}),"model":parsed.get("model",""),"service_tier":parsed.get("service_tier",""),"reasoning":parsed.get("reasoning",{})}
	return response

static func _finish_streamed_wav(wav: PackedByteArray) -> PackedByteArray:
	# Streamed responses can leave both RIFF lengths unknown. Godot receives the
	# completed HTTP body, so the final data chunk's exact size is available.
	const UNKNOWN_LENGTH := 0xffffffff
	if wav.decode_u32(4)!=UNKNOWN_LENGTH:return wav
	var offset:=12
	while offset+8<=wav.size():
		var length:=wav.decode_u32(offset+4)
		if length==UNKNOWN_LENGTH:
			if wav.slice(offset,offset+4).get_string_from_ascii()!="data":return PackedByteArray()
			wav.encode_u32(offset+4,wav.size()-offset-8)
			break
		if length>wav.size()-offset-8:return PackedByteArray()
		offset+=8+length+(length&1)
	wav.encode_u32(4,wav.size()-8)
	return wav

func _decode_body(path: String, parsed: Dictionary) -> Dictionary:
	if path=="/audio/voices":
		var voice_id:=str(parsed.get("id",""))
		if parsed.get("object")!="audio.voice" or parsed.get("type")!="prompt" or not voice_id.begins_with("voice_") or not Models.valid_id(voice_id):
			return {"ok":false,"error":"OpenAI did not confirm a saved prompt-generated voice.","creation_uncertain":true}
		return {"ok":true,"id":voice_id,"name":str(parsed.get("name","")),"type":"prompt","prompt":str(parsed.get("prompt","")),"created_at":int(parsed.get("created_at",0))}
	if path=="/images/generations":
		var items: Variant=parsed.get("data")
		if not items is Array or items.size()!=1 or not items[0] is Dictionary:
			return {"ok":false,"error":"OpenAI returned no image."}
		var png:=Marshalls.base64_to_raw(str(items[0].get("b64_json","")))
		# Check the PNG signature and dimensions before decoding the image.
		if png.size()<33 or png.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or png.slice(12,16).get_string_from_ascii()!="IHDR":
			return {"ok":false,"error":"OpenAI returned an unreadable image."}
		var width:=int(png[18])*256+int(png[19])
		var height:=int(png[22])*256+int(png[23])
		if png[16]!=0 or png[17]!=0 or png[20]!=0 or png[21]!=0 or width<1 or width>1536 or height<1 or height>1536 or width*height>1536*1024:
			return {"ok":false,"error":"The generated image exceeded the preview dimensions."}
		var image:=Image.new()
		if image.load_png_from_buffer(png)!=OK:return {"ok":false,"error":"OpenAI returned an unreadable image."}
		return {"ok":true,"image":image}
	if parsed.has("results"):
		var results: Array=parsed.get("results",[])
		return {"ok":true,"flagged":bool(results[0].get("flagged",false)),"categories":results[0].get("categories",{})} if not results.is_empty() and results[0] is Dictionary else {"ok":false,"error":"OpenAI returned no moderation result."}
	if path=="/chat/completions":
		var choices: Variant=parsed.get("choices",[])
		if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:return {"ok":false,"error":"OpenAI returned no text."}
		if choices[0].get("finish_reason","")=="length":return {"ok":false,"error":"The response reached the output token limit."}
		var message: Variant=choices[0].get("message",{})
		if not message is Dictionary:return {"ok":false,"error":"OpenAI returned an unreadable completion."}
		if message.get("audio") is Dictionary:
			var audio: Dictionary=message.audio
			var encoded:=str(audio.get("data",""))
			if encoded.is_empty() or encoded.length()>8*1024*1024:return {"ok":false,"error":"The audio completion exceeded its bounded response size."}
			var wav:=Marshalls.base64_to_raw(encoded)
			if wav.size()<44 or wav.slice(0,4).get_string_from_ascii()!="RIFF" or wav.slice(8,12).get_string_from_ascii()!="WAVE":return {"ok":false,"error":"The audio completion did not return WAV audio."}
			var clip:=AudioStreamWAV.load_from_buffer(_finish_streamed_wav(wav))
			if clip==null or clip.data.is_empty() or clip.get_length()>120.:return {"ok":false,"error":"The audio completion returned invalid or oversized audio."}
			return {"ok":true,"stream":clip,"transcript":str(audio.get("transcript",""))}
		return _text_result(str(message.get("content","")))
	if parsed.get("status","")!="completed":
		var incomplete: Variant=parsed.get("incomplete_details")
		if incomplete is Dictionary and incomplete.get("reason","")=="max_output_tokens":
			return {"ok":false,"error":"The response reached the output token limit. Raise the limit or lower thinking effort."}
		return {"ok":false,"error":"OpenAI did not complete the response."}
	var parts: Array[String]=[]
	for item in parsed.get("output",[]):
		if not item is Dictionary or item.get("type","")!="message":continue
		for content in item.get("content",[]):
			if content is Dictionary and content.get("type","")=="output_text":parts.append(str(content.get("text","")))
	return _text_result("\n".join(parts))

func _text_result(value: String) -> Dictionary:
	var answer:=value.strip_edges()
	if answer.length()>16000:return {"ok":false,"error":"The response exceeds the bounded text budget. No partial response was accepted."}
	return {"ok":true,"text":answer} if not answer.is_empty() else {"ok":false,"error":"OpenAI returned no text."}

func _mode_allowed(choice: String, mode: String) -> bool:
	return mode=="standard" or (mode=="pro" and Models.has_pro_mode(choice))

func _clean_profile(value: String) -> String:
	var clean:=value.strip_edges().left(36)
	# A local label can never be used to store a pasted credential.
	if clean.begins_with("sk-"):return ""
	for character in clean:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_":return ""
	return clean

func usage_scope(draft := {}) -> String:
	var label:=_clean_profile(str(draft.get("usage_profile",usage_profile)))
	return "Profile "+label if not label.is_empty() else local_usage_session

func _record_request(id: String,purpose: String,response: Dictionary,success: bool,elapsed: int,draft: Dictionary,reasoning: Dictionary,seconds := -1.0,characters := -1) -> Dictionary:
	var measurement:=Usage.usage_from(response,seconds,characters)
	var requested_effort:=str(reasoning.get("effort",""))
	var observed: Variant=response.get("reasoning",{})
	var effort:=str(observed.get("effort",requested_effort)) if observed is Dictionary else requested_effort
	var mode:=str(reasoning.get("mode","pro" if id.ends_with("-pro") else "standard"))
	var snapshot:=str(response.get("model",""))
	if not Models.valid_id(snapshot) or snapshot==id:snapshot=""
	var processing:=str(response.get("service_tier",""))
	if processing.is_empty() or processing in ["auto","default"]:processing="standard"
	if processing=="priority":processing="fast"
	var data:={"profile":usage_scope(draft),"model":id,"snapshot":snapshot,"purpose":purpose,
		"effort":effort,"mode":mode,"tier":processing,"date":Time.get_date_string_from_system(true),"type":str(draft.get("request_type","feature" if draft.is_empty() else "test")),"billed_usage":not response.get("usage",{}).is_empty()}
	var entry:=usage_tracker.record(data,measurement,success,elapsed)
	if success or not measurement.is_empty():
		var totals: Dictionary=model_usage.get_or_add(id,{"requests":0,"input":0,"output":0,"reasoning":0,"seconds":0.0})
		totals.requests+=1
		for field in ["input","output","reasoning","seconds"]:totals[field]+=measurement.get(field,0)
	entry.effort=effort
	entry.mode=mode
	_save()
	usage_changed.emit()
	return entry

func comparison_question(question: String,choice: String,effort: String,mode: String,limit: int,draft: Dictionary) -> Dictionary:
	if not Models.available_for(choice,"text") or not _mode_allowed(choice,mode) or limit not in range(16,2049):
		return {"ok":false,"error":"Comparison request is unavailable for this model."}
	var context:=draft.duplicate()
	context.request_type="comparison"
	context.mode=mode
	return await _request_text(question,choice,limit,effort,false,context,35.0)

func _token_count(value: Variant) -> int:
	return clampi(int(value),0,2000000000) if (value is int or value is float) and is_finite(float(value)) else 0

func _credential() -> String:
	return _session_key if not _session_key.is_empty() else "" if _environment_key_disconnected else OS.get_environment("OPENAI_API_KEY").strip_edges()

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH)!=OK:return
	var saved_model := str(config.get_value("openai","model",DEFAULT_MODEL))
	model=saved_model if Models.valid_id(saved_model) else DEFAULT_MODEL
	max_output_tokens=clampi(int(config.get_value("openai","max_output_tokens",384)),16,32768)
	reasoning_effort=Models.normalize_effort(model,str(config.get_value("openai","reasoning_effort","")))
	enabled=bool(config.get_value("openai","enabled",false))
	image_model=str(config.get_value("openai","image_model",""))
	image_reasoning_effort=Models.normalize_effort(image_model,str(config.get_value("openai","image_reasoning_effort","")))
	image_generation_model=str(config.get_value("openai","image_generation_model",""))
	var stored_generation: Variant=config.get_value("openai","image_generation_options",{})
	if stored_generation is Dictionary and Models.valid_image_generation_options(image_generation_model,stored_generation):
		image_generation_options={"size":str(stored_generation.get("size","1024x1024")),"quality":str(stored_generation.get("quality","low")),"output_format":"png"}
	stt_model=str(config.get_value("openai","stt_model",TRANSCRIPTION_MODEL))
	tts_model=str(config.get_value("openai","tts_model",SPEECH_MODEL))
	stt_enabled=bool(config.get_value("openai","stt_enabled",enabled))
	tts_enabled=bool(config.get_value("openai","tts_enabled",false))
	live_model=str(config.get_value("openai","live_model","gpt-live-1.1"))
	live_enabled=false # Migrate the retired native-conversation toggle off.
	usage_profile=_clean_profile(str(config.get_value("openai","usage_profile","")))
	reasoning_mode=str(config.get_value("openai","reasoning_mode","standard"))
	if not _mode_allowed(model,reasoning_mode):reasoning_mode="standard"
	image_reasoning_mode=str(config.get_value("openai","image_reasoning_mode","standard"))
	if not _mode_allowed(image_model,image_reasoning_mode):image_reasoning_mode="standard"
	usage_tracker.load_rows(config.get_value("usage_v2","rows",{}))
	var usage: Variant=config.get_value("usage","models",{})
	if usage is Dictionary:
		for id in usage:
			var totals: Variant=usage[id]
			if not id is String or not Models.valid_id(id) or not totals is Dictionary:continue
			model_usage[id]={"requests":_token_count(totals.get("requests",0)),"input":_token_count(totals.get("input",0)),"output":_token_count(totals.get("output",0)),"reasoning":_token_count(totals.get("reasoning",0)),"seconds":maxf(0,float(totals.get("seconds",0)))}

func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("openai","model",model)
	config.set_value("openai","max_output_tokens",max_output_tokens)
	config.set_value("openai","reasoning_effort",reasoning_effort)
	config.set_value("openai","enabled",enabled)
	config.set_value("openai","image_model",image_model)
	config.set_value("openai","image_reasoning_effort",image_reasoning_effort)
	config.set_value("openai","image_generation_model",image_generation_model)
	config.set_value("openai","image_generation_options",image_generation_options)
	config.set_value("openai","stt_model",stt_model)
	config.set_value("openai","tts_model",tts_model)
	config.set_value("openai","stt_enabled",stt_enabled)
	config.set_value("openai","tts_enabled",tts_enabled)
	config.set_value("openai","usage_profile",usage_profile)
	config.set_value("openai","reasoning_mode",reasoning_mode)
	config.set_value("openai","image_reasoning_mode",image_reasoning_mode)
	config.set_value("usage","models",model_usage)
	config.set_value("usage_v2","rows",usage_tracker.rows)
	return config.save(SETTINGS_PATH)

func _exit_tree() -> void:
	_connection_epoch+=1
	for request: HTTPRequest in _http_requests.values():
		if is_instance_valid(request):request.cancel_request()
	for session: Node in _voice_requests.values():
		if is_instance_valid(session):session.cancel()
	_http_requests.clear();_voice_requests.clear();_cancelled_requests.clear()
