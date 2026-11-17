extends Node
## Local editor broker only. Never instantiate this from a network action handler.
signal finished(result: Dictionary)
const Request=preload("res://scripts/firmware_toolchain/source_request.gd")
const Artifact=preload("res://scripts/firmware_toolchain/artifact.gd")
const Acceptance=preload("res://scripts/firmware_toolchain/acceptance.gd")
static var process_busy := false
var broker_pid := -1
var setup_pid := -1
var setup_started_at := 0
var pending_request := {}
var started_at := 0
var cancel_started_at := 0
var current_request := {}
var job_directory := ""

func start(board: String,files: Dictionary,entry: String,language: String="") -> Dictionary:
	if process_busy:return Request.failure("Another local compilation is running","busy")
	var request := {"schema":1,"board":board,"language":language if language!="" else "arduino_cpp" if board in ["uno","nano"] else "pico_cpp","entry":entry,"files":files.duplicate(true)}
	var check := Request.validate(request)
	if not check.ok:return check
	if OS.get_name()!="Windows":return Request.failure("This compiler broker currently requires Windows AppContainer isolation","sandbox_unavailable")
	var shell := OS.get_environment("WINDIR").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(shell):return Request.failure("Trusted Windows PowerShell broker is unavailable","sandbox_unavailable")
	if not Acceptance.verified():
		var root: String=Acceptance.script_root()
		var installer: String=root.path_join("install_bundled.ps1")
		var game_dir: String=OS.get_executable_path().get_base_dir()
		if not FileAccess.file_exists(installer) or not FileAccess.file_exists(root.path_join("avr-gcc.zip")) or not FileAccess.file_exists(root.path_join("arduino-core.zip")) or not FileAccess.file_exists(root.path_join("arm-gcc.zip")):
			return Request.failure(Acceptance.explanation(),"boundary_unverified")
		pending_request={"board":board,"files":files.duplicate(true),"entry":entry,"language":language}
		var install_root: String=Acceptance.install_root()
		DirAccess.make_dir_recursive_absolute(install_root)
		setup_pid=OS.create_process(shell,PackedStringArray(["-NoProfile","-NonInteractive","-File",installer,"-GameDirectory",game_dir,"-InstallRoot",install_root]),false)
		if setup_pid<0:return Request.failure("Cannot start bundled compiler setup","setup_failed")
		process_busy=true;setup_started_at=Time.get_ticks_msec()
		return {"ok":true,"status":"preparing"}
	var temp_root := OS.get_environment("TEMP")
	if temp_root.is_empty():temp_root=ProjectSettings.globalize_path("user://")
	var base := temp_root.path_join("LabVoltFirmwareJobs")
	job_directory=base.path_join(Crypto.new().generate_random_bytes(16).hex_encode())
	if DirAccess.make_dir_recursive_absolute(job_directory)!=OK:return Request.failure("Cannot create a private compilation job directory","workspace_unavailable")
	request.source_sha256=check.source_sha256 # Host-added metadata, not accepted as a player option.
	var file := FileAccess.open(job_directory.path_join("request.json"),FileAccess.WRITE)
	if file==null:return Request.failure("Cannot write local compilation request","workspace_unavailable")
	file.store_string(JSON.stringify(request));file.close()
	current_request=request
	var manifest := Acceptance.install_root().path_join("trusted-manifest.json")
	var arguments := PackedStringArray(["-NoProfile","-NonInteractive","-File",Acceptance.script_root().path_join("broker.ps1"),"-JobDirectory",job_directory,"-Manifest",manifest])
	broker_pid=OS.create_process(shell,arguments,false)
	if broker_pid<0:return Request.failure("Cannot start compiler broker","broker_unavailable")
	process_busy=true;started_at=Time.get_ticks_msec();cancel_started_at=0
	return {"ok":true,"status":"running"}

func cancel() -> void:
	if job_directory.is_empty() or broker_pid<0:return
	cancel_started_at=Time.get_ticks_msec()
	var file := FileAccess.open(job_directory.path_join("cancel"),FileAccess.WRITE)
	if file!=null:file.store_string("cancel");file.close()

func _process(_delta: float) -> void:
	if setup_pid>=0:
		if OS.is_process_running(setup_pid):
			if Time.get_ticks_msec()-setup_started_at>600000:OS.kill(setup_pid)
			else:return
		var setup_exit: int=OS.get_process_exit_code(setup_pid)
		setup_pid=-1;process_busy=false
		var pending: Dictionary=pending_request
		pending_request={}
		if setup_exit==0 and Acceptance.verified():
			var restarted: Dictionary=start(str(pending.board),pending.files,str(pending.entry),str(pending.language))
			if not restarted.ok:finished.emit(restarted)
			return
		var detail: String="Bundled compiler setup or acceptance failed"
		var result_path: String=Acceptance.install_root().path_join("install-result.json")
		if FileAccess.file_exists(result_path):
			var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(result_path))
			if data is Dictionary:detail=str(data.get("error",detail))
		finished.emit(Request.failure(detail,"setup_failed"))
		return
	if broker_pid<0:return
	var elapsed := Time.get_ticks_msec()-started_at
	if OS.is_process_running(broker_pid):
		if elapsed>120000 or (cancel_started_at>0 and Time.get_ticks_msec()-cancel_started_at>5000):
			OS.kill(broker_pid) # Only this service's broker; its job handle kills its compiler descendants.
		else:return
	var exit_code: int=OS.get_process_exit_code(broker_pid)
	broker_pid=-1;process_busy=false
	var path := job_directory.path_join("result.json")
	var result := Request.failure("Compiler broker failed without a result (exit %d)"%exit_code,"broker_failed")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file!=null and file.get_length()<=4194304:
			var data: Variant=JSON.parse_string(file.get_as_text())
			if data is Dictionary:result=data
		if file!=null:file.close()
	result=Artifact.validate(result,str(current_request.board),current_request.files)
	if cancel_started_at>0:result=Request.failure("Compilation cancelled; previous image retained","cancelled")
	if result.has("output"):result.diagnostics=preload("res://scripts/firmware_toolchain/diagnostics.gd").parse(str(result.output),current_request.files)
	DirAccess.make_dir_recursive_absolute(Acceptance.install_root())
	var report := FileAccess.open(Acceptance.install_root().path_join("isolation-status.json"),FileAccess.WRITE)
	if report!=null:report.store_string(JSON.stringify({"ok":bool(result.get("ok",false)),"isolation_established":bool(result.get("isolation_established",false)),"dependencies_verified":bool(result.get("dependencies_verified",false)),"status":result.get("status","unknown"),"error":result.get("error","Last isolated compilation succeeded"),"time":Time.get_datetime_string_from_system()}));report.close()
	# Broker quiesces its process tree and removes its source/build scratch files.
	# Remove only fixed local filenames; directory removal fails if unexpected files remain.
	for name in ["request.json","result.json","cancel"]:DirAccess.remove_absolute(job_directory.path_join(name))
	DirAccess.remove_absolute(job_directory)
	finished.emit(result)

func _exit_tree() -> void:
	if setup_pid>=0:
		if OS.is_process_running(setup_pid):OS.kill(setup_pid)
		setup_pid=-1;process_busy=false
	if broker_pid>=0:
		cancel()
		if OS.is_process_running(broker_pid):OS.kill(broker_pid)
		broker_pid=-1;process_busy=false
