extends Node
## Bounded host speech scheduler. Provider failures never change vocal identity.
## The legacy process path is isolated behind explicit selection/test adapters.
signal completed(room: String,serial: int,key: String,stream: AudioStreamWAV,status: String)
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Mixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
const Delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const SpeechPlayer=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const MAX_JOBS:=6
const MAX_LISTENERS:=32
const TIMEOUT_MS:=30000
var pending: Array[Dictionary]=[]
var active: Dictionary={}
var keys: Dictionary={}
var launch_adapter: Callable
var running_adapter: Callable
var kill_adapter: Callable
var load_adapter: Callable
var profile_adapter: Callable
var model_adapter: Callable
var last_synthesis_ms := 0
const MAX_CLOUD_JOBS:=48
const MAX_CONCURRENT:=3
const MAX_ATTEMPTS:=3
const CLOUD_TIMEOUT_MS:=120000
var provider: Node
var legacy_enabled:=false
var cloud_pending: Array[Dictionary]=[]
var cloud_active: Dictionary={}
var cloud_keys: Dictionary={}
var session_epoch:=0
var request_serial:=0
var last_error:=""

func configure_provider(client: Node,mode: String="openai") -> void:
	if provider!=client or legacy_enabled!=(mode=="legacy_offline"):clear_session()
	provider=client;legacy_enabled=mode=="legacy_offline"

func diagnostics() -> Dictionary:
	var jobs: Array=[]
	for job in cloud_active.values():jobs.append({"character_id":job.id,"request_id":job.request_id,"age_ms":Time.get_ticks_msec()-int(job.created),"attempt":job.attempts,"state":"generating"})
	for job in cloud_pending:jobs.append({"character_id":job.id,"request_id":job.request_id,"age_ms":Time.get_ticks_msec()-int(job.created),"attempt":job.attempts,"state":"queued"})
	return {"provider":"legacy_offline" if legacy_enabled else "openai","active":cloud_active.size(),"queued":cloud_pending.size(),"jobs":jobs,"last_error":last_error,"last_synthesis_ms":last_synthesis_ms}


func request(room: String,serial: int,id: String,text: String,key: String,priority:=0,delivery: Dictionary={}) -> String:
	if room.is_empty() or room.length()>160 or serial<1 or serial>2147483647 or id.is_empty() or text.is_empty() or text.length()>SpeechPlayer.MAX_TEXT or key.is_empty() or key.length()>128:return "invalid"
	if legacy_enabled or profile_adapter.is_valid() or launch_adapter.is_valid():return _request_legacy(room,serial,id,text,key,priority)
	if not is_instance_valid(provider):return "unavailable"
	if provider.has_method("configured") and not provider.configured():return "unavailable"
	if delivery.has("ok") and not bool(delivery.ok):return "incompatible_voice"
	if cloud_keys.has(key):
		var listeners: Array=cloud_keys[key]
		for listener in listeners:
			if str(listener.room)==room and int(listener.serial)==serial:return "duplicate"
		if listeners.size()>=MAX_LISTENERS:return "busy"
		listeners.append({"room":room,"serial":serial})
		for queued_job in cloud_pending:
			if str(queued_job.key)==key:queued_job.priority=maxi(int(queued_job.priority),priority)
		return "duplicate"
	if cloud_pending.size()+cloud_active.size()>=MAX_CLOUD_JOBS:return "busy"
	request_serial+=1
	var now:=Time.get_ticks_msec()
	var details:=Delivery.for_text(delivery,text)
	var request_id:="voice-%d-%d"%[session_epoch,request_serial]
	details.request_id=request_id
	var job:={"room":room,"serial":serial,"id":id,"text":text,"key":key,"priority":clampi(priority,0,14),"delivery":details,"request_id":request_id,
		"created":now,"ready_at":now,"attempts":0,"epoch":session_epoch}
	cloud_keys[key]=[{"room":room,"serial":serial}]
	cloud_pending.append(job)
	_pump_cloud.call_deferred()
	return "queued"

func _pump_cloud() -> void:
	if not is_inside_tree() or not is_instance_valid(provider):return
	var now:=Time.get_ticks_msec()
	for index in range(cloud_pending.size()-1,-1,-1):
		if now-int(cloud_pending[index].created)>=CLOUD_TIMEOUT_MS:
			var expired: Dictionary=cloud_pending.pop_at(index);_complete_cloud(expired,null,"expired")
	while cloud_active.size()<MAX_CONCURRENT and not cloud_pending.is_empty():
		var next:=-1
		var best:=-INF
		for index in cloud_pending.size():
			var job: Dictionary=cloud_pending[index]
			if int(job.ready_at)>now:continue
			var same_character:=false
			for running in cloud_active.values():
				if str(running.id)==str(job.id):same_character=true;break
			if same_character:continue
			var score:=float(job.priority)+float(now-int(job.created))/5000.
			if score>best:best=score;next=index
		if next<0:break
		var job: Dictionary=cloud_pending.pop_at(next)
		cloud_active[job.request_id]=job
		_run_cloud(job)

func _run_cloud(job: Dictionary) -> void:
	job.attempts=int(job.attempts)+1
	var voice: Variant=job.delivery.get("voice","alloy")
	var result: Dictionary=await provider.speak(str(job.text),{},voice,job.delivery)
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id):return
	cloud_active.erase(job.request_id)
	if bool(result.get("ok",false)) and result.get("stream") is AudioStreamWAV and SpeechPlayer.valid_stream(result.stream):
		var stream: AudioStreamWAV=Mixer.normalise(result.stream,job.delivery)
		last_synthesis_ms=Time.get_ticks_msec()-int(job.created)
		_complete_cloud(job,stream,"ok")
	else:
		var code:=int(result.get("status",result.get("code",0)))
		var reason:=str(result.get("error","speech unavailable"))
		var retryable:=bool(result.get("retryable",false)) or code==429 or code>=500 or reason.to_lower() in ["busy","timeout","network error"]
		if retryable and int(job.attempts)<MAX_ATTEMPTS and Time.get_ticks_msec()-int(job.created)<CLOUD_TIMEOUT_MS and cloud_keys.has(job.key):
			var retry_after:=clampi(int(result.get("retry_after_ms",0)),0,15000)
			job.ready_at=Time.get_ticks_msec()+maxi(retry_after,500*(1<<int(job.attempts)))
			cloud_pending.append(job)
		else:
			last_error=reason.left(240)
			_complete_cloud(job,null,"unavailable")
	_pump_cloud.call_deferred()

func _complete_cloud(job: Dictionary,stream: AudioStreamWAV,status: String) -> void:
	var listeners: Array=cloud_keys.get(job.key,[])
	cloud_keys.erase(job.key)
	for listener in listeners:completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,status)

func _cancel_cloud(room: String) -> void:
	for key in cloud_keys.keys():
		var listeners: Array=cloud_keys[key]
		for index in range(listeners.size()-1,-1,-1):
			if str(listeners[index].room)==room:
				var listener: Dictionary=listeners.pop_at(index)
				completed.emit(room,int(listener.serial),str(key),null,"cancelled")
		if listeners.is_empty():cloud_keys.erase(key)
	for index in range(cloud_pending.size()-1,-1,-1):
		if not cloud_keys.has(cloud_pending[index].key):cloud_pending.remove_at(index)
	for request_id in cloud_active.keys():
		var job: Dictionary=cloud_active[request_id]
		if cloud_keys.has(job.key):continue
		cloud_active.erase(request_id)
		if is_instance_valid(provider) and provider.has_method("cancel_speech_request"):provider.cancel_speech_request(request_id)
	_pump_cloud.call_deferred()

func _request_legacy(room: String,serial: int,id: String,text: String,key: String,priority := 0) -> String:
	if room.is_empty() or serial<1 or text.is_empty() or text.length()>SpeechPlayer.MAX_TEXT or key.is_empty():return "invalid"
	var profiles: Dictionary=profile_adapter.call() if profile_adapter.is_valid() else Profiles.profiles()
	var profile: Dictionary=profiles.get(id,{})
	var model:=str(profile.get("model",""))
	var model_disk:=Profiles.resolve_model(model)
	var model_valid:=not model_disk.is_empty()
	if model_adapter.is_valid():model_valid=bool(model_adapter.call(model))
	if not model_valid:return "unavailable"
	if keys.has(key):
		if keys[key].size()>=MAX_LISTENERS:return "busy"
		keys[key].append({"room":room,"serial":serial})
		for queued in pending:
			if queued.key==key:queued.priority=maxi(int(queued.priority),priority)
		return "duplicate"
	if pending.size()+(1 if not active.is_empty() else 0)>=MAX_JOBS:return "busy"
	var job:={"room":room,"serial":serial,"id":id,"text":text,"key":key,"model":model,"model_disk":model_disk,"speaker":int(profile.speaker),"rate":float(profile.rate),"gain":float(profile.gain),"pause":int(profile.pause_ms),"priority":priority}
	keys[key]=[{"room":room,"serial":serial}];pending.append(job)
	# Launch failures may finish immediately. Give callers a chance to connect
	# or await completion before the worker can emit a result.
	if active.is_empty():_start_next.call_deferred()
	return "queued"

func cancel(room: String) -> void:
	_cancel_cloud(room)
	for key in keys.keys():
		var listeners: Array=keys[key]
		for index in range(listeners.size()-1,-1,-1):
			if str(listeners[index].room)==room:
				completed.emit(str(listeners[index].room),int(listeners[index].serial),str(key),null,"cancelled")
				listeners.remove_at(index)
	for index in range(pending.size()-1,-1,-1):
		if keys[pending[index].key].is_empty():
			keys.erase(pending[index].key);pending.remove_at(index)
	if not active.is_empty() and keys[active.key].is_empty():_finish("cancelled",true)

func clear_session() -> void:
	session_epoch+=1
	for request_id in cloud_active.keys():
		if is_instance_valid(provider) and provider.has_method("cancel_speech_request"):provider.cancel_speech_request(request_id)
	cloud_pending.clear();cloud_active.clear();cloud_keys.clear()
	pending.clear();keys.clear()
	if not active.is_empty():_finish("cancelled",true)

func _exit_tree() -> void:
	clear_session()

func _start_next() -> void:
	if not active.is_empty() or pending.is_empty():return
	var next := 0
	for index in range(1,pending.size()):
		if int(pending[index].priority)>int(pending[next].priority):next=index
	active=pending.pop_at(next)
	var base:="user://teacher_speech/"+str(Time.get_ticks_usec())+"_"+str(randi())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://teacher_speech"))
	active.input=base+".txt";active.output=base+".wav"
	var input:=FileAccess.open(active.input,FileAccess.WRITE)
	if input==null:_finish("input_error");return
	input.store_string(str(active.text));input.close()
	var executable:=OS.get_environment("LABVOLT_PIPER_PATH")
	var model_path:=str(active.model_disk)
	var input_path:=ProjectSettings.globalize_path(active.input)
	var output_path:=ProjectSettings.globalize_path(active.output)
	var args: PackedStringArray
	var bundled:=OS.get_executable_path().get_base_dir().path_join("piper/piper.exe")
	if executable.is_empty():
		if not FileAccess.file_exists(bundled):
			var development:=ProjectSettings.globalize_path("res://.deps/piper-standalone/piper/piper.exe")
			if FileAccess.file_exists(development):bundled=development
		if not FileAccess.file_exists(bundled) and not launch_adapter.is_valid():
			executable = "piper.exe" if OS.get_name() == "Windows" else "piper"
	if executable.is_empty():
		active.standalone=true
		var runner:=ProjectSettings.globalize_path("res://scripts/campus/academics/piper_runner.ps1")
		if not FileAccess.file_exists(runner):runner=OS.get_executable_path().get_base_dir().path_join("teacher_voices/piper_runner.ps1")
		if not FileAccess.file_exists(runner) and not launch_adapter.is_valid():_finish("engine_unavailable");return
		executable="powershell.exe"
		args=PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",runner,"-Piper",bundled,"-Model",model_path,"-InputPath",input_path,"-OutputPath",output_path,"-Speaker",str(active.speaker),"-LengthScale",str(1.0/float(active.rate)),"-SentenceSilence",str(float(active.pause)/1000.0)])
	else:
		args=PackedStringArray(["--model",model_path,"--config",model_path+".json","--input-file",input_path,"--output-file",output_path,"--speaker",str(active.speaker),"--length-scale",str(1.0/float(active.rate)),"--sentence-silence",str(float(active.pause)/1000.0),"--volume",str(active.gain)])
	if not launch_adapter.is_valid():
		executable=_resolve_executable(executable)
		if executable.is_empty():_finish("engine_unavailable");return
	var pid: int=launch_adapter.call(executable,args) if launch_adapter.is_valid() else OS.create_process(executable,args,false)
	if pid<=0:_finish("engine_unavailable");return
	active.pid=pid;active.started=Time.get_ticks_msec()

static func _resolve_executable(candidate: String) -> String:
	# An absent optional voice engine is an ordinary unavailable feature, not
	# a failed OS launch that asks Godot/.NET to format a native error stack.
	if candidate.is_empty():return ""
	if candidate.contains("/") or candidate.contains("\\"):
		var path:=ProjectSettings.globalize_path(candidate)
		return path if _executable_file(path) else ""
	var separator:=";" if OS.get_name()=="Windows" else ":"
	for directory in OS.get_environment("PATH").split(separator,false):
		var path:=str(directory).path_join(candidate)
		if _executable_file(path):return path
	return ""

static func _executable_file(path: String) -> bool:
	if not FileAccess.file_exists(path):return false
	return OS.get_name()=="Windows" or (FileAccess.get_unix_permissions(path)&73)!=0

func _process(_delta: float) -> void:
	_pump_cloud()
	if active.is_empty():return
	if Time.get_ticks_msec()-int(active.started)>TIMEOUT_MS:_finish("timeout",true);return
	var running: bool=running_adapter.call(int(active.pid)) if running_adapter.is_valid() else OS.is_process_running(int(active.pid))
	if running:return
	if not FileAccess.file_exists(active.output):_finish("output_error");return
	var output_file:=FileAccess.open(active.output,FileAccess.READ)
	if output_file==null or output_file.get_length()>SpeechPlayer.MAX_WAV_BYTES+100:
		_finish("output_error");return
	output_file.close()
	var stream: AudioStreamWAV=load_adapter.call(active.output) if load_adapter.is_valid() else AudioStreamWAV.load_from_file(active.output)
	if not SpeechPlayer.valid_stream(stream):_finish("output_error");return
	if active.get("standalone",false) and float(active.gain)!=1.0:
		stream.set_meta(SpeechPlayer.GAIN_META,clampf(float(active.gain),0.,2.))
	_finish("ok",false,stream)

func _finish(status: String,kill: bool=false,stream: AudioStreamWAV=null) -> void:
	if active.is_empty():return
	var job:=active;active={}
	if job.has("started"):last_synthesis_ms=Time.get_ticks_msec()-int(job.started)
	if kill and job.has("pid"):
		if kill_adapter.is_valid():kill_adapter.call(int(job.pid))
		else:OS.kill(int(job.pid))
	for path in [str(job.get("input","")),str(job.get("output",""))]:
		if not path.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var listeners: Array=keys.get(job.key,[])
	keys.erase(job.key)
	for listener in listeners:completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,status)
	if not pending.is_empty():_start_next.call_deferred()
