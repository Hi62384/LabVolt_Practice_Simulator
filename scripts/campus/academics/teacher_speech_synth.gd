extends Node
## One local synthesis process at a time. Text never enters a shell command.
signal completed(room: String,serial: int,key: String,stream: AudioStreamWAV,status: String)
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const MAX_JOBS:=6
const MAX_LISTENERS:=32
const TIMEOUT_MS:=12000
var pending: Array[Dictionary]=[]
var active: Dictionary={}
var keys: Dictionary={}
var launch_adapter: Callable
var running_adapter: Callable
var kill_adapter: Callable
var load_adapter: Callable
var profile_adapter: Callable
var model_adapter: Callable

func request(room: String,serial: int,id: String,text: String,key: String) -> String:
	if room.is_empty() or serial<1 or text.is_empty() or text.length()>350 or key.is_empty():return "invalid"
	var profiles: Dictionary=profile_adapter.call() if profile_adapter.is_valid() else Profiles.profiles()
	var profile: Dictionary=profiles.get(id,{})
	if profile.is_empty() and Roster.GENERATED.has(id):profile=profiles.get("dr_volts",{})
	var model:=str(profile.get("model",""))
	var model_disk:=Profiles.resolve_model(model)
	var model_valid:=not model_disk.is_empty()
	if model_adapter.is_valid():model_valid=bool(model_adapter.call(model))
	if not model_valid:return "unavailable"
	if keys.has(key):
		if keys[key].size()>=MAX_LISTENERS:return "busy"
		keys[key].append({"room":room,"serial":serial})
		return "duplicate"
	if pending.size()+(1 if not active.is_empty() else 0)>=MAX_JOBS:return "busy"
	var job:={"room":room,"serial":serial,"id":id,"text":text,"key":key,"model":model,"model_disk":model_disk,"speaker":int(profile.speaker),"rate":float(profile.rate),"gain":float(profile.gain),"pause":int(profile.pause_ms)}
	keys[key]=[{"room":room,"serial":serial}];pending.append(job)
	if active.is_empty():_start_next()
	return "queued"

func cancel(room: String) -> void:
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
	pending.clear();keys.clear()
	if not active.is_empty():_finish("cancelled",true)

func _start_next() -> void:
	if not active.is_empty() or pending.is_empty():return
	active=pending.pop_front()
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
	if executable.is_empty():
		active.standalone=true
		var bundled:=OS.get_executable_path().get_base_dir().path_join("piper/piper.exe")
		if not FileAccess.file_exists(bundled):
			var development:=ProjectSettings.globalize_path("res://.deps/piper-standalone/piper/piper.exe")
			if FileAccess.file_exists(development):bundled=development
		if not FileAccess.file_exists(bundled) and not launch_adapter.is_valid():_finish("engine_unavailable");return
		var runner:=ProjectSettings.globalize_path("res://scripts/campus/academics/piper_runner.ps1")
		if not FileAccess.file_exists(runner):runner=OS.get_executable_path().get_base_dir().path_join("teacher_voices/piper_runner.ps1")
		if not FileAccess.file_exists(runner) and not launch_adapter.is_valid():_finish("engine_unavailable");return
		executable="powershell.exe"
		args=PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",runner,"-Piper",bundled,"-Model",model_path,"-InputPath",input_path,"-OutputPath",output_path,"-Speaker",str(active.speaker),"-LengthScale",str(1.0/float(active.rate)),"-SentenceSilence",str(float(active.pause)/1000.0)])
	else:
		args=PackedStringArray(["--model",model_path,"--config",model_path+".json","--input-file",input_path,"--output-file",output_path,"--speaker",str(active.speaker),"--length-scale",str(1.0/float(active.rate)),"--sentence-silence",str(float(active.pause)/1000.0),"--volume",str(active.gain)])
	var pid: int=launch_adapter.call(executable,args) if launch_adapter.is_valid() else OS.create_process(executable,args,false)
	if pid<=0:_finish("engine_unavailable");return
	active.pid=pid;active.started=Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if active.is_empty():return
	if Time.get_ticks_msec()-int(active.started)>TIMEOUT_MS:_finish("timeout",true);return
	var running: bool=running_adapter.call(int(active.pid)) if running_adapter.is_valid() else OS.is_process_running(int(active.pid))
	if running:return
	if not FileAccess.file_exists(active.output):_finish("output_error");return
	var output_file:=FileAccess.open(active.output,FileAccess.READ)
	if output_file==null or output_file.get_length()>2000100:
		_finish("output_error");return
	output_file.close()
	var stream: AudioStreamWAV=load_adapter.call(active.output) if load_adapter.is_valid() else AudioStreamWAV.load_from_file(active.output)
	if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.data.is_empty() or stream.data.size()>2000000:_finish("output_error");return
	if active.get("standalone",false) and float(active.gain)!=1.0:
		var pcm: PackedByteArray=stream.data.duplicate()
		for i in range(0,pcm.size()-1,2):pcm.encode_s16(i,clampi(roundi(float(pcm.decode_s16(i))*float(active.gain)),-32768,32767))
		stream.data=pcm
	_finish("ok",false,stream)

func _finish(status: String,kill: bool=false,stream: AudioStreamWAV=null) -> void:
	if active.is_empty():return
	var job:=active;active={}
	if kill and job.has("pid"):
		if kill_adapter.is_valid():kill_adapter.call(int(job.pid))
		else:OS.kill(int(job.pid))
	for path in [str(job.get("input","")),str(job.get("output",""))]:
		if not path.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var listeners: Array=keys.get(job.key,[])
	keys.erase(job.key)
	for listener in listeners:completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,status)
	_start_next()
