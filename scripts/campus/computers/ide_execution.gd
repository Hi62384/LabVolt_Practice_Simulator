extends Node

const SOURCE_LIMIT := 32 * 1024
const OUTPUT_LIMIT := 16 * 1024
const EXTENSIONS := {
	"py":"Python","pyw":"Python","c":"C","cc":"C++","cpp":"C++","cxx":"C++","cs":"C#",
	"java":"Java","rs":"Rust","go":"Go","rb":"Ruby","lua":"Lua","php":"PHP","kt":"Kotlin","swift":"Swift",
	"sh":"Bash","r":"R","hs":"Haskell","scala":"Scala","dart":"Dart","exs":"Elixir","erl":"Erlang",
	"pl":"Perl","pas":"Pascal","f90":"Fortran","fs":"F#","fsx":"F#","nim":"Nim","zig":"Zig",
	"clj":"Clojure","ml":"OCaml","ts":"TypeScript","js":"JavaScript","sql":"SQL","vb":"Visual Basic"
}

var endpoint := ""
var credential := ""
var runtimes: Array[Dictionary] = []
var cached_until := 0
var generation := 0
var in_flight: HTTPRequest
var running := false

func configure_from_host() -> void:
	endpoint=OS.get_environment("LABVOLT_JUDGE0_URL").strip_edges().trim_suffix("/")
	credential=OS.get_environment("LABVOLT_JUDGE0_TOKEN").strip_edges()
	if not endpoint.begins_with("https://") and not (credential.is_empty() and endpoint.begins_with("http://127.0.0.1:")):
		endpoint=""
	var authority:=endpoint.get_slice("/",2)
	if authority.is_empty() or authority.contains("@") or endpoint.contains("#") or endpoint.contains("?") or endpoint.contains("\\") or credential.contains("\n") or credential.contains("\r"):
		endpoint=""

static func validate_json(source: String) -> String:
	var parser:=JSON.new()
	if parser.parse(source)!=OK:return "JSON error on line %d · %s"%[parser.get_error_line()+1,parser.get_error_message()]
	return "Valid JSON"

func supported_runtimes() -> Dictionary:
	if endpoint.is_empty():return {"error":"The session host has not configured Judge0."}
	if Time.get_ticks_msec()<cached_until and not runtimes.is_empty():return {"runtimes":runtimes}
	var result:=await _request("/languages")
	if result.has("error"):return result
	if not result.data is Array:return {"error":"Judge0 returned an invalid language list."}
	runtimes.clear()
	for item in result.data:
		if not item is Dictionary or not item.get("name") is String or not (item.get("id") is int or item.get("id") is float):continue
		var id:=int(item.id)
		if id<=0 or item.name.length()>120 or item.name.begins_with("Multi-file"):continue
		runtimes.append({"name":item.name,"id":id})
	cached_until=Time.get_ticks_msec()+300000
	return {"runtimes":runtimes}

func execute(path: String, source: String, stdin: String ="", runtime_id: int =0) -> String:
	var extension:=path.get_extension().to_lower()
	if extension=="json":return validate_json(source)
	if endpoint.is_empty():return "Remote execution requires a Judge0 service configured by the session host."
	if running or is_instance_valid(in_flight):return "A compiler request is already running."
	var code:=source.to_utf8_buffer()
	var input:=stdin.to_utf8_buffer()
	if code.is_empty() or code.size()>SOURCE_LIMIT or input.size()>SOURCE_LIMIT:return "Source and standard input must each fit within 32 KiB."
	var family:=str(EXTENSIONS.get(extension,""))
	if family.is_empty() and runtime_id==0:return "Choose a supported runtime for this source file."
	running=true
	var job:=generation
	var catalog:=await supported_runtimes()
	if job!=generation:return "Stopped."
	if catalog.has("error"):running=false;return catalog.error
	var selected: Dictionary={}
	for runtime in runtimes:
		var name:=str(runtime.name)
		if runtime_id==int(runtime.id) or (runtime_id==0 and (name==family or name.begins_with(family+" "))):
			selected=runtime
			if runtime_id!=0:break
	if selected.is_empty():running=false;return "Judge0 has no matching runtime for this file."
	var payload:={"language_id":selected.id,"source_code":Marshalls.raw_to_base64(code),"stdin":"" if input.is_empty() else Marshalls.raw_to_base64(input),
		"cpu_time_limit":3,"wall_time_limit":8,"memory_limit":262144,"max_file_size":16,"enable_network":false}
	var submission:=await _request("/submissions?base64_encoded=true&wait=false",payload)
	if job!=generation:return "Stopped."
	if submission.has("error"):running=false;return submission.error
	var id:=str(submission.data.get("token","")) if submission.data is Dictionary else ""
	if not _valid_token(id):running=false;return "Judge0 returned an invalid job identifier."
	var deadline:=Time.get_ticks_msec()+18000
	while Time.get_ticks_msec()<deadline and job==generation:
		await get_tree().create_timer(.85).timeout
		if job!=generation:return "Stopped."
		var result:=await _request("/submissions/"+id+"?base64_encoded=true&fields=status,stdout,stderr,compile_output,message,time,memory")
		if job!=generation:return "Stopped."
		if result.has("error"):running=false;return result.error
		if not result.data is Dictionary or not result.data.get("status") is Dictionary:
			running=false;return "Judge0 returned an invalid execution result."
		if int(result.data.status.get("id",0))>2:
			running=false
			return _format_result(result.data,str(selected.name))
	running=false
	return "The compiler did not return a result in time."

func stop() -> void:
	generation+=1
	running=false
	# Leave the bounded HTTP request to finish so suspended callers can unwind.
	# The submitted job remains subject to server-side time and memory limits.

func _request(path: String, payload := {}) -> Dictionary:
	if is_instance_valid(in_flight):return {"error":"A compiler request is already running."}
	var request:=HTTPRequest.new()
	request.use_threads=true
	request.timeout=7
	request.max_redirects=0
	request.body_size_limit=192*1024
	in_flight=request
	add_child(request)
	var headers:=PackedStringArray(["Content-Type: application/json","Accept: application/json"])
	if not credential.is_empty():headers.append("X-Auth-Token: "+credential)
	var error:=request.request(endpoint+path,headers,HTTPClient.METHOD_GET if payload.is_empty() else HTTPClient.METHOD_POST,"" if payload.is_empty() else JSON.stringify(payload))
	if error!=OK:
		in_flight=null
		request.queue_free()
		return {"error":"Could not reach Judge0."}
	var response: Array=await request.request_completed
	in_flight=null
	request.queue_free()
	if response[0]!=HTTPRequest.RESULT_SUCCESS:return {"error":"Judge0 connection failed or the response was too large."}
	match int(response[1]):
		401,403:return {"error":"Judge0 rejected the host credentials."}
		429:return {"error":"Judge0 is rate limiting this session."}
		200,201:return {"data":JSON.parse_string(response[3].get_string_from_utf8())}
		_:return {"error":"Judge0 returned HTTP %d."%response[1]}

static func _valid_token(value: String) -> bool:
	if value.is_empty() or value.length()>96:return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":return false
	return true

static func _format_result(value: Dictionary, runtime: String) -> String:
	var rows:=PackedStringArray(["%s · %s"%( [runtime,str(value.status.get("description","Finished")).left(90)] )])
	if value.get("time")!=null:rows[0]+="   %s s"%str(value.time).left(24)
	if value.get("memory") is float or value.get("memory") is int:rows[0]+="   %d KiB"%int(value.memory)
	for field in ["compile_output","stderr","stdout","message"]:
		var item: Variant=value.get(field)
		if item is String and not item.is_empty():
			var decoded:=Marshalls.base64_to_raw(item)
			var length:=mini(decoded.size(),OUTPUT_LIMIT)
			while length<decoded.size() and length>0 and (decoded[length]&192)==128:length-=1
			rows.append(decoded.slice(0,length).get_string_from_utf8()+("\n[Output truncated]" if length<decoded.size() else ""))
	return "\n".join(rows)
