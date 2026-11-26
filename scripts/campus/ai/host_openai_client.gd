extends Node
## Host-only OpenAI transport. No credential is written to Godot user data.
signal usage_changed

const SETTINGS_PATH := "user://host_openai.cfg"
const API_BASE := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-5.4-mini"
const MAX_INPUT_CHARS := 4000
const MAX_RESPONSE_BYTES := 262144
const MAX_IMAGE_RESPONSE_BYTES := 8 * 1024 * 1024
const TRANSCRIPTION_MODEL := "gpt-4o-mini-transcribe"
const SPEECH_MODEL := "gpt-4o-mini-tts"
const Models = preload("res://scripts/campus/ai/openai_models.gd")

var enabled := false
var model := DEFAULT_MODEL
var image_model := ""
var image_generation_model := ""
var stt_model := TRANSCRIPTION_MODEL
var tts_model := SPEECH_MODEL
var stt_enabled := false
var tts_enabled := false
var max_output_tokens := 384
var reasoning_effort := ""
var image_reasoning_effort := ""
var model_usage: Dictionary = {}
var busy := false
var _session_key := ""
var _environment_key_disconnected := false
var _model_cache_key := ""
var _model_cache: Array[String] = []
var _test_base := ""
var _verified_signature := ""
var verification_error := ""

func _ready() -> void:
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
	_session_key=clean
	return true

func _valid_key(clean: String) -> bool:
	if clean.length()<20 or clean.length()>256 or not clean.begins_with("sk-"):
		return false
	for character in clean:
		if character in " \t\r\n":return false
	return true

func clear_session_key() -> void:
	if host_allowed():
		_session_key=""
		_verified_signature=""

func disconnect_key() -> void:
	if not host_allowed():return
	clear_session_key()
	_environment_key_disconnected=true
	_model_cache_key=""
	_model_cache.clear()
	verification_error=""

func configure(next_model: String, output_limit: int, next_effort: String, next_enabled: bool) -> Error:
	if not host_allowed() or not Models.valid_id(next_model) or Models.endpoint(next_model).is_empty():return ERR_INVALID_PARAMETER
	if next_effort!=Models.normalize_effort(next_model,next_effort):return ERR_INVALID_PARAMETER
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
	var signature:=_signature(key,choice,effort,output)
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
		if not id.is_empty() and not Models.supports(id,purpose):return ERR_INVALID_PARAMETER
	var next_image:=str(choices.get("image",image_model))
	var next_image_effort:=str(draft.get("image_effort",image_reasoning_effort))
	if next_image_effort!=Models.normalize_effort(next_image,next_image_effort):return ERR_INVALID_PARAMETER
	var previous: Array=[image_model,stt_model,tts_model,stt_enabled,tts_enabled,image_generation_model,image_reasoning_effort]
	image_model=next_image
	image_reasoning_effort=next_image_effort
	image_generation_model=str(choices.get("image_generation",image_generation_model))
	stt_model=str(choices.get("stt",stt_model))
	tts_model=str(choices.get("tts",tts_model))
	stt_enabled=bool(draft.get("stt_enabled",stt_enabled)) and not stt_model.is_empty()
	tts_enabled=bool(draft.get("tts_enabled",tts_enabled)) and not tts_model.is_empty()
	var error:=configure(str(draft.model),int(draft.output),str(draft.get("effort","")),true)
	if error!=OK:
		image_model=previous[0];stt_model=previous[1];tts_model=previous[2];stt_enabled=previous[3];tts_enabled=previous[4]
		image_generation_model=previous[5]
		image_reasoning_effort=previous[6]
		return error
	if not key.is_empty():set_session_key(key)
	if signature==_connection_signature():
		_verified_signature=signature
		verification_error=""
	return OK

func _connection_signature() -> String:
	return _signature(_credential(),model,reasoning_effort,max_output_tokens)

func _signature(key: String, choice: String, effort: String, output: int) -> String:
	return JSON.stringify([key,choice,effort,output,_test_base]).sha256_text()

func verified_for_class() -> bool:
	return enabled and configured() and _verified_signature==_connection_signature()

func class_connection_status() -> String:
	if verified_for_class():return "Connected â€” AI teaching available"
	if not enabled or not configured():return "Not connected â€” Add your API key in OpenAI Settings before starting the game."
	if not verification_error.is_empty():return "Connection failed â€” "+verification_error
	return "Not verified â€” Test the host's OpenAI connection to start classes."

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

func respond(prompt: String) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Enter a prompt of 1 to 4,000 characters."}
	return await _request_text(prompt,model,max_output_tokens,reasoning_effort,true)

func respond_with_image(prompt: String,jpeg: PackedByteArray,draft: Dictionary={}) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS or jpeg.size()<4 or jpeg.size()>262144 or jpeg[0]!=255 or jpeg[1]!=216:return {"ok":false,"error":"The image or question is too large."}
	var content: Array=[{"type":"input_text","text":prompt},{"type":"input_image","image_url":"data:image/jpeg;base64,"+Marshalls.raw_to_base64(jpeg),"detail":"low"}]
	var choice:=str(draft.get("modalities",{}).get("image",image_model))
	if choice.is_empty() and draft.is_empty():choice=model
	if not Models.supports(choice,"image"):return {"ok":false,"error":"Choose an image analysis model in OpenAI Settings."}
	var effort:=str(draft.get("image_effort",image_reasoning_effort))
	return await _request_text(content,choice,int(draft.get("output",max_output_tokens)),Models.normalize_effort(choice,effort),draft.is_empty(),draft)

func speak(text: String, draft: Dictionary={}, voice := "alloy") -> Dictionary:
	var choice:=str(draft.get("modalities",{}).get("tts",tts_model))
	if not bool(draft.get("tts_enabled",tts_enabled)) or not Models.supports(choice,"tts"):
		return {"ok":false,"error":"Enable text-to-speech and choose a voice model in OpenAI Settings."}
	if voice not in Models.speech_voices(choice):return {"ok":false,"error":"This voice is unavailable for the selected speech model."}
	if text.strip_edges().is_empty() or text.length()>350:return {"ok":false,"error":"Enter up to 350 characters to read aloud."}
	return await _call(HTTPClient.METHOD_POST,"/audio/speech",{"model":choice,"input":text,"voice":voice,"response_format":"wav"},draft.is_empty(),draft)

func generate_image(prompt: String, draft: Dictionary={}) -> Dictionary:
	var choice:=str(draft.get("modalities",{}).get("image_generation",image_generation_model))
	if not Models.supports(choice,"image_generation"):
		return {"ok":false,"error":"Choose an image generation model."}
	prompt=prompt.strip_edges()
	if prompt.is_empty() or prompt.length()>MAX_INPUT_CHARS:
		return {"ok":false,"error":"Enter an image prompt of up to %d characters."%MAX_INPUT_CHARS}
	var payload:={"model":choice,"prompt":prompt,"size":"1024x1024","output_format":"png","quality":"low","n":1}
	return await _call(HTTPClient.METHOD_POST,"/images/generations",payload,draft.is_empty(),draft)

func _request_text(input: Variant, choice: String, output: int, effort: String, needs_enabled: bool, draft := {}) -> Dictionary:
	var path:=Models.endpoint(choice)
	if path.is_empty():return {"ok":false,"error":"This model uses a specialized API. Choose a text model for classroom prompts."}
	if effort!=Models.normalize_effort(choice,effort):return {"ok":false,"error":"This model does not support that thinking effort."}
	var payload: Dictionary={"model":choice}
	if path=="/chat/completions":
		var content: Variant=input
		if input is Array:
			content=[{"type":"text","text":input[0].text},{"type":"image_url","image_url":{"url":input[1].image_url,"detail":"low"}}]
		payload.messages=[{"role":"user","content":content}]
		payload.max_completion_tokens=output
	else:
		payload.input=input if input is String else [{"role":"user","content":input}]
		payload.max_output_tokens=output
		payload.store=false
		if not effort.is_empty():payload.reasoning={"effort":effort}
	return await _call(HTTPClient.METHOD_POST,path,payload,needs_enabled,draft)

func moderate(input: String) -> Dictionary:
	if input.strip_edges().is_empty() or input.length()>1000:return {"ok":false,"error":"The message is too long."}
	var result: Dictionary=await _call(HTTPClient.METHOD_POST,"/moderations",{"model":"omni-moderation-latest","input":input},true)
	return result

func transcribe_wav(wav: PackedByteArray,draft: Dictionary={}) -> Dictionary:
	if wav.size()<32044 or wav.size()>192044 or wav.slice(0,4).get_string_from_ascii()!="RIFF" or wav.slice(8,12).get_string_from_ascii()!="WAVE" or wav.slice(12,16).get_string_from_ascii()!="fmt " or wav.decode_u16(20)!=1 or wav.decode_u16(22)!=1 or wav.decode_u32(24)!=16000 or wav.decode_u16(34)!=16 or wav.slice(36,40).get_string_from_ascii()!="data" or wav.decode_u32(40)!=wav.size()-44:return {"ok":false,"error":"Record between one and six seconds of speech."}
	var key:=str(draft.get("key",""))
	if key.is_empty():key=_credential()
	if not host_allowed() or (draft.is_empty() and not enabled) or key.is_empty():return {"ok":false,"error":"The host AI connection is unavailable."}
	var choice:=str(draft.get("modalities",{}).get("stt",stt_model))
	if not bool(draft.get("stt_enabled",stt_enabled)) or not Models.supports(choice,"stt"):return {"ok":false,"error":"Speech-to-text is disabled in the host's OpenAI settings."}
	if busy:return {"ok":false,"error":"An AI request is already running."}
	var now:=Time.get_ticks_msec()
	busy=true
	var boundary:="LabVoltVoice"+str(now)
	var head:=("--%s\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%s\r\n--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.wav\"\r\nContent-Type: audio/wav\r\n\r\n"%[boundary,choice,boundary]).to_utf8_buffer()
	var body:=head+wav+("\r\n--%s--\r\n"%boundary).to_utf8_buffer()
	var request:=HTTPRequest.new();request.timeout=20.0;request.body_size_limit=32768;request.max_redirects=0;add_child(request)
	var headers:=PackedStringArray(["Authorization: Bearer "+key,"Content-Type: multipart/form-data; boundary="+boundary])
	var base:=_test_base if not _test_base.is_empty() else API_BASE
	var error:=request.request_raw(base+"/audio/transcriptions",headers,HTTPClient.METHOD_POST,body)
	if error!=OK:request.queue_free();busy=false;return {"ok":false,"error":"Could not start speech transcription."}
	var completed: Array=await request.request_completed
	request.queue_free();busy=false
	if int(completed[0])!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"error":"Speech transcription timed out."}
	var code:=int(completed[1])
	if code<200 or code>=300:return {"ok":false,"error":"Speech transcription failed (HTTP %d)."%code}
	var parsed: Variant=JSON.parse_string((completed[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:return {"ok":false,"error":"Speech transcription was unreadable."}
	_record_usage(choice,parsed,float(wav.size()-44)/32000.0)
	var words:=str(parsed.get("text","")).strip_edges().left(500)
	return {"ok":true,"text":words} if not words.is_empty() else {"ok":false,"error":"No speech was recognized."}

func set_local_test_endpoint(value: String) -> bool:
	if not OS.has_feature("editor"):return false
	var pattern := RegEx.create_from_string("^http://127\\.0\\.0\\.1:[0-9]{2,5}/v1$")
	if pattern.search(value)==null:return false
	_test_base=value
	return true

func _call(method: HTTPClient.Method,path: String,payload: Dictionary,needs_enabled: bool,draft := {}) -> Dictionary:
	if not host_allowed():return {"ok":false,"error":"Only the host can use the OpenAI connection."}
	if needs_enabled and not enabled:return {"ok":false,"error":"Accept the OpenAI settings before starting the game."}
	var key:=str(draft.get("key",""))
	if key.is_empty():key=_credential()
	if key.is_empty():return {"ok":false,"error":"Add an API key in OpenAI Settings or set OPENAI_API_KEY for the host process."}
	if busy:return {"ok":false,"error":"An OpenAI request is already running."}
	var request_model:=str(payload.get("model",model))
	if not Models.valid_id(request_model):return {"ok":false,"error":"Choose a valid model ID in OpenAI Settings."}
	busy=true
	var request := HTTPRequest.new()
	request.timeout=180.0 if path in ["/responses","/images/generations"] else 30.0
	request.body_size_limit=2097152 if path in ["/models","/audio/speech"] else MAX_RESPONSE_BYTES
	if path=="/images/generations":request.body_size_limit=MAX_IMAGE_RESPONSE_BYTES
	request.max_redirects=0
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer "+key,"Content-Type: application/json"])
	var base := _test_base if not _test_base.is_empty() else API_BASE
	var error := request.request(base+path,headers,method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:
		request.queue_free()
		busy=false
		return {"ok":false,"error":"Could not start the OpenAI request."}
	var completed: Array=await request.request_completed
	request.queue_free()
	busy=false
	var response:=_read_response(int(completed[0]),int(completed[1]),completed[3],path,request_model)
	if draft.is_empty() and int(completed[0])==HTTPRequest.RESULT_SUCCESS and int(completed[1]) in [401,403,404]:
		_verified_signature=""
		verification_error=str(response.get("error","Connection verification is required."))
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
		var stream:=AudioStreamWAV.load_from_buffer(body)
		if stream==null or stream.data.is_empty():return {"ok":false,"error":"OpenAI returned an unreadable voice clip."}
		_record_usage(request_model,{},stream.get_length())
		return {"ok":true,"stream":stream}
	var parsed: Variant=JSON.parse_string(body.get_string_from_utf8())
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
	_record_usage(request_model,parsed)
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
		if png[16]!=0 or png[17]!=0 or png[20]!=0 or png[21]!=0 or width<1 or width>1024 or height<1 or height>1024:
			return {"ok":false,"error":"The generated image exceeded the preview dimensions."}
		var image:=Image.new()
		if image.load_png_from_buffer(png)!=OK:return {"ok":false,"error":"OpenAI returned an unreadable image."}
		return {"ok":true,"image":image}
	if parsed.has("results"):
		var results: Array=parsed.get("results",[])
		return {"ok":true,"flagged":bool(results[0].get("flagged",false))} if not results.is_empty() and results[0] is Dictionary else {"ok":false,"error":"OpenAI returned no moderation result."}
	if path=="/chat/completions":
		var choices: Array=parsed.get("choices",[])
		if choices.is_empty():return {"ok":false,"error":"OpenAI returned no text."}
		return _text_result(str(choices[0].get("message",{}).get("content","")))
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
	var answer:=value.strip_edges().left(16000)
	return {"ok":true,"text":answer} if not answer.is_empty() else {"ok":false,"error":"OpenAI returned no text."}

func _record_usage(id: String, response: Dictionary, audio_seconds := 0.0) -> void:
	var raw: Variant=response.get("usage",{})
	var usage: Dictionary=raw if raw is Dictionary else {}
	var details: Variant=usage.get("output_tokens_details",usage.get("completion_tokens_details",{}))
	var totals: Dictionary=model_usage.get_or_add(id,{"requests":0,"input":0,"output":0,"reasoning":0,"seconds":0.0})
	totals.requests+=1
	totals.input+=_token_count(usage.get("input_tokens",usage.get("prompt_tokens",0)))
	totals.output+=_token_count(usage.get("output_tokens",usage.get("completion_tokens",0)))
	if details is Dictionary:totals.reasoning+=_token_count(details.get("reasoning_tokens",0))
	var seconds: Variant=usage.get("seconds",audio_seconds)
	if (seconds is int or seconds is float) and is_finite(float(seconds)) and seconds>0:totals.seconds+=float(seconds)
	_save()
	usage_changed.emit()

func _token_count(value: Variant) -> int:
	return clampi(int(value),0,2000000000) if (value is int or value is float) and is_finite(float(value)) else 0

func _credential() -> String:
	return _session_key if not _session_key.is_empty() else "" if _environment_key_disconnected else OS.get_environment("OPENAI_API_KEY").strip_edges()

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH)!=OK:return
	var saved_model := str(config.get_value("openai","model",DEFAULT_MODEL))
	model=saved_model if Models.valid_id(saved_model) and not Models.endpoint(saved_model).is_empty() else DEFAULT_MODEL
	max_output_tokens=clampi(int(config.get_value("openai","max_output_tokens",384)),16,32768)
	reasoning_effort=Models.normalize_effort(model,str(config.get_value("openai","reasoning_effort","")))
	enabled=bool(config.get_value("openai","enabled",false))
	image_model=str(config.get_value("openai","image_model",""))
	image_reasoning_effort=Models.normalize_effort(image_model,str(config.get_value("openai","image_reasoning_effort","")))
	image_generation_model=str(config.get_value("openai","image_generation_model",""))
	stt_model=str(config.get_value("openai","stt_model",TRANSCRIPTION_MODEL))
	tts_model=str(config.get_value("openai","tts_model",SPEECH_MODEL))
	stt_enabled=bool(config.get_value("openai","stt_enabled",enabled))
	tts_enabled=bool(config.get_value("openai","tts_enabled",false))
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
	config.set_value("openai","stt_model",stt_model)
	config.set_value("openai","tts_model",tts_model)
	config.set_value("openai","stt_enabled",stt_enabled)
	config.set_value("openai","tts_enabled",tts_enabled)
	config.set_value("usage","models",model_usage)
	return config.save(SETTINGS_PATH)
