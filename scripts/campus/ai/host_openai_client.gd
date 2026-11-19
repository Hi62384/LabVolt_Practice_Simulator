extends Node
## Host-only OpenAI transport. No credential is written to Godot user data.

const SETTINGS_PATH := "user://host_openai.cfg"
const API_BASE := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-5.4-mini"
const MAX_INPUT_CHARS := 4000
const MAX_RESPONSE_BYTES := 262144

var enabled := false
var model := DEFAULT_MODEL
var max_output_tokens := 384
var requests_per_minute := 8
var requests_per_day := 20
var used_today := 0
var usage_day := ""
var busy := false
var _session_key := ""
var _minute_calls: Array[int] = []
var _test_base := ""
var _verified_signature := ""
var verification_error := ""

func _ready() -> void:
	_load()

func host_allowed() -> bool:
	return multiplayer.is_server()

func credential_source() -> String:
	if not _session_key.is_empty():return "Session key"
	if not OS.get_environment("OPENAI_API_KEY").strip_edges().is_empty():return "Host environment"
	return "Not connected"

func configured() -> bool:
	return not _credential().is_empty()

func set_session_key(value: String) -> bool:
	if not host_allowed():return false
	var clean := value.strip_edges()
	if clean.length()<20 or clean.length()>256 or not clean.begins_with("sk-"):
		return false
	for character in clean:
		if character in " \t\r\n":return false
	_session_key=clean
	return true

func clear_session_key() -> void:
	if host_allowed():
		_session_key=""
		_verified_signature=""

func configure(next_model: String, output_limit: int, minute_limit: int, day_limit: int, next_enabled: bool) -> Error:
	if not host_allowed() or not _valid_model(next_model):return ERR_INVALID_PARAMETER
	model=next_model
	max_output_tokens=clampi(output_limit,16,2048)
	requests_per_minute=clampi(minute_limit,1,10)
	requests_per_day=clampi(day_limit,1,200)
	enabled=next_enabled
	return _save()

func test_connection() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET,"/models/"+model,{},false)

func _connection_signature() -> String:
	return (_credential()+"\n"+model+"\n"+_test_base).sha256_text()

func verified_for_class() -> bool:
	return enabled and configured() and _verified_signature==_connection_signature()

func class_connection_status() -> String:
	if verified_for_class():return "Connected — AI teaching available"
	if not enabled or not configured():return "Not connected — Enable OpenAI and add a key in Host Server settings."
	if not verification_error.is_empty():return "Connection failed — "+verification_error
	return "Not verified — Test the host's OpenAI connection to start classes."

func verify_class_connection() -> Dictionary:
	var signature:=_connection_signature()
	var result:=await _call(HTTPClient.METHOD_POST,"/responses",{"model":model,"input":"Reply with the single word Ready.","max_output_tokens":64,"store":false},true)
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
	var payload := {"model":model,"input":prompt,"max_output_tokens":max_output_tokens,"store":false}
	return await _call(HTTPClient.METHOD_POST,"/responses",payload,true)

func respond_with_image(prompt: String,jpeg: PackedByteArray) -> Dictionary:
	if prompt.strip_edges().is_empty() or prompt.length()>MAX_INPUT_CHARS or jpeg.size()<4 or jpeg.size()>262144 or jpeg[0]!=255 or jpeg[1]!=216:return {"ok":false,"error":"The image or question is too large."}
	var content: Array=[{"type":"input_text","text":prompt},{"type":"input_image","image_url":"data:image/jpeg;base64,"+Marshalls.raw_to_base64(jpeg),"detail":"low"}]
	var payload:={"model":model,"input":[{"role":"user","content":content}],"max_output_tokens":max_output_tokens,"store":false}
	return await _call(HTTPClient.METHOD_POST,"/responses",payload,true)

func moderate(input: String) -> Dictionary:
	if input.strip_edges().is_empty() or input.length()>1000:return {"ok":false,"error":"The message is too long."}
	var result: Dictionary=await _call(HTTPClient.METHOD_POST,"/moderations",{"model":"omni-moderation-latest","input":input},true)
	return result

func transcribe_wav(wav: PackedByteArray) -> Dictionary:
	if wav.size()<32044 or wav.size()>192044 or wav.slice(0,4).get_string_from_ascii()!="RIFF" or wav.slice(8,12).get_string_from_ascii()!="WAVE" or wav.slice(12,16).get_string_from_ascii()!="fmt " or wav.decode_u16(20)!=1 or wav.decode_u16(22)!=1 or wav.decode_u32(24)!=16000 or wav.decode_u16(34)!=16 or wav.slice(36,40).get_string_from_ascii()!="data" or wav.decode_u32(40)!=wav.size()-44:return {"ok":false,"error":"Record between one and six seconds of speech."}
	if not host_allowed() or not enabled or not configured():return {"ok":false,"error":"The host AI connection is unavailable."}
	if busy:return {"ok":false,"error":"An AI request is already running."}
	var now:=Time.get_ticks_msec()
	_minute_calls=_minute_calls.filter(func(t: int):return now-t<60000)
	var today:=Time.get_date_string_from_system(true)
	if usage_day!=today:usage_day=today;used_today=0
	if _minute_calls.size()>=requests_per_minute or used_today>=requests_per_day:return {"ok":false,"error":"The host's OpenAI request limit has been reached."}
	used_today+=1
	if _save()!=OK:used_today-=1;return {"ok":false,"error":"Could not save the OpenAI request count."}
	_minute_calls.append(now)
	busy=true
	var boundary:="LabVoltVoice"+str(now)
	var head:=("--%s\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.wav\"\r\nContent-Type: audio/wav\r\n\r\n"%[boundary,boundary]).to_utf8_buffer()
	var body:=head+wav+("\r\n--%s--\r\n"%boundary).to_utf8_buffer()
	var request:=HTTPRequest.new();request.timeout=20.0;request.body_size_limit=32768;add_child(request)
	var headers:=PackedStringArray(["Authorization: Bearer "+_credential(),"Content-Type: multipart/form-data; boundary="+boundary])
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
	var words:=str(parsed.get("text","")).strip_edges().left(500)
	return {"ok":true,"text":words} if not words.is_empty() else {"ok":false,"error":"No speech was recognized."}

func set_local_test_endpoint(value: String) -> bool:
	if not OS.has_feature("editor"):return false
	var pattern := RegEx.create_from_string("^http://127\\.0\\.0\\.1:[0-9]{2,5}/v1$")
	if pattern.search(value)==null:return false
	_test_base=value
	return true

func _call(method: HTTPClient.Method,path: String,payload: Dictionary,needs_enabled: bool) -> Dictionary:
	if not host_allowed():return {"ok":false,"error":"Only the host can use the OpenAI connection."}
	if needs_enabled and not enabled:return {"ok":false,"error":"Turn on the OpenAI connection in Host Server settings."}
	if not configured():return {"ok":false,"error":"Add an OpenAI API key in Host Server settings or set OPENAI_API_KEY for the host process."}
	if busy:return {"ok":false,"error":"An OpenAI request is already running."}
	if not _valid_model(model):return {"ok":false,"error":"Choose a valid model ID in Host Server settings."}
	var now := Time.get_ticks_msec()
	_minute_calls=_minute_calls.filter(func(t: int):return now-t<60000)
	var today := Time.get_date_string_from_system(true)
	if usage_day!=today:usage_day=today;used_today=0
	if _minute_calls.size()>=requests_per_minute:return {"ok":false,"error":"The host's per-minute OpenAI request limit has been reached."}
	if used_today>=requests_per_day:return {"ok":false,"error":"The host's daily OpenAI request limit has been reached."}
	used_today+=1
	if _save()!=OK:
		used_today-=1
		return {"ok":false,"error":"Could not save the OpenAI request count. No request was sent."}
	_minute_calls.append(now)
	busy=true
	var request := HTTPRequest.new()
	request.timeout=15.0
	request.body_size_limit=MAX_RESPONSE_BYTES
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer "+_credential(),"Content-Type: application/json"])
	var base := _test_base if not _test_base.is_empty() else API_BASE
	var error := request.request(base+path,headers,method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:
		request.queue_free()
		busy=false
		return {"ok":false,"error":"Could not start the OpenAI request."}
	var completed: Array=await request.request_completed
	request.queue_free()
	busy=false
	var response:=_read_response(int(completed[0]),int(completed[1]),completed[3],method)
	if int(completed[0])==HTTPRequest.RESULT_SUCCESS and int(completed[1]) in [401,403,404]:
		_verified_signature=""
		verification_error=str(response.get("error","Connection verification is required."))
	return response

func _read_response(result: int,code: int,body: PackedByteArray,method: HTTPClient.Method) -> Dictionary:
	if result!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"error":"OpenAI could not be reached or timed out."}
	if code==401:return {"ok":false,"error":"OpenAI rejected the API key."}
	if code==403:return {"ok":false,"error":"This API key cannot access the selected model."}
	if code==404:return {"ok":false,"error":"The selected OpenAI model was not found."}
	if code==429:return {"ok":false,"error":"OpenAI is rate limiting this key. Try again later."}
	if code>=500:return {"ok":false,"error":"OpenAI is temporarily unavailable."}
	if code<200 or code>=300:return {"ok":false,"error":"OpenAI rejected the request (HTTP %d)."%code}
	var parsed: Variant=JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:return {"ok":false,"error":"OpenAI returned an unreadable response."}
	if method==HTTPClient.METHOD_GET:
		return {"ok":true,"message":"Connected to OpenAI. Model is available."} if str(parsed.get("id",""))==model else {"ok":false,"error":"OpenAI did not confirm the selected model."}
	if parsed.has("results"):
		var results: Array=parsed.get("results",[])
		return {"ok":true,"flagged":bool(results[0].get("flagged",false))} if not results.is_empty() and results[0] is Dictionary else {"ok":false,"error":"OpenAI returned no moderation result."}
	if parsed.get("status","")!="completed":return {"ok":false,"error":"OpenAI did not complete the response."}
	var parts: Array[String]=[]
	for item in parsed.get("output",[]):
		if not item is Dictionary or item.get("type","")!="message":continue
		for content in item.get("content",[]):
			if content is Dictionary and content.get("type","")=="output_text":parts.append(str(content.get("text","")))
	var answer := "\n".join(parts).strip_edges().left(16000)
	return {"ok":true,"text":answer} if not answer.is_empty() else {"ok":false,"error":"OpenAI returned no text."}

func _credential() -> String:
	return _session_key if not _session_key.is_empty() else OS.get_environment("OPENAI_API_KEY").strip_edges()

func _valid_model(value: String) -> bool:
	if value.is_empty() or value.length()>64:return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-":return false
	return true

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH)!=OK:return
	var saved_model := str(config.get_value("openai","model",DEFAULT_MODEL))
	model=saved_model if _valid_model(saved_model) else DEFAULT_MODEL
	max_output_tokens=clampi(int(config.get_value("openai","max_output_tokens",384)),16,2048)
	requests_per_minute=clampi(int(config.get_value("openai","requests_per_minute",4)),1,10)
	requests_per_day=clampi(int(config.get_value("openai","requests_per_day",20)),1,200)
	enabled=bool(config.get_value("openai","enabled",false))
	usage_day=str(config.get_value("usage","day",""))
	used_today=maxi(0,int(config.get_value("usage","count",0)))

func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("openai","model",model)
	config.set_value("openai","max_output_tokens",max_output_tokens)
	config.set_value("openai","requests_per_minute",requests_per_minute)
	config.set_value("openai","requests_per_day",requests_per_day)
	config.set_value("openai","enabled",enabled)
	config.set_value("usage","day",usage_day)
	config.set_value("usage","count",used_today)
	return config.save(SETTINGS_PATH)
