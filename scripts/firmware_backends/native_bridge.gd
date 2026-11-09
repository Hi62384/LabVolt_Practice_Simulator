extends RefCounted
## Host-only asynchronous transport. Caller must hold circuit simulation time until
## the matching reply is consumed. Never advance a separate copy on clients.
var process: Dictionary = {}
var pending := false
var buffer := ""
var started_at := 0
var last_error := ""
var last_state: Dictionary = {}
var upload_commands: Array=[]

func start(node_executable: String, external_backend_directory: String = "") -> bool:
	close()
	var root := external_backend_directory
	if root.is_empty():root=ProjectSettings.globalize_path("res://scripts/firmware_backends")
	# A trusted executable path is host configuration, never a field in player saves.
	if not node_executable.is_absolute_path() or not FileAccess.file_exists(node_executable):
		last_error="Configure an absolute trusted Node.js 20.19+ executable path";return false
	if not FileAccess.file_exists(root.path_join("bridge.cjs")) or not FileAccess.file_exists(root.path_join("../electronics_buses/native_bus.cjs")) or not FileAccess.file_exists(root.path_join("../electronics_buses/native_group.cjs")):
		last_error="Native backend source files are missing from the configured project directory";return false
	process=OS.execute_with_pipe(node_executable,PackedStringArray(["--max-old-space-size=128",root.path_join("bridge.cjs")]),false)
	if process.is_empty():last_error="Could not launch native firmware backend";return false
	return true

func request(command: Dictionary) -> bool:
	if process.is_empty() or pending or not upload_commands.is_empty():return false
	if command.get("op","")=="load" and str(command.get("image","")).length()>2048:
		var spec := command.duplicate();var image := str(spec.get("image",""));spec.erase("image");spec.erase("op")
		if image.length()>2800000:last_error="Image upload limit";return false
		upload_commands.append({"op":"image_begin","spec":spec})
		for offset in range(0,image.length(),2048):upload_commands.append({"op":"image_chunk","data":image.substr(offset,2048)})
		upload_commands.append({"op":"image_commit"})
		return send(upload_commands.pop_front())
	return send(command)

func send(command: Dictionary) -> bool:
	var encoded := JSON.stringify(command)+"\n"
	# Keep nonblocking writes below the Windows pipe buffer. Large images are
	# transferred in acknowledged chunks, never one multi-megabyte write.
	if encoded.to_utf8_buffer().size()>4096:last_error="Firmware request exceeds frame size limit";return false
	process.stdio.store_buffer(encoded.to_utf8_buffer());process.stdio.flush()
	pending=true;started_at=Time.get_ticks_msec();return true

func poll() -> Dictionary:
	if not pending:return {}
	# Nonblocking pipe get_buffer reads available bytes; never use blocking get_line.
	var bytes: PackedByteArray=process.stdio.get_buffer(65536)
	if not bytes.is_empty():buffer+=bytes.get_string_from_utf8()
	if buffer.length()>262144:
		last_error="Backend response size limit";close();return {"ok":false,"error":last_error}
	if "\n" in buffer:
		var line := buffer.get_slice("\n",0);buffer=buffer.substr(line.length()+1);pending=false
		var result=JSON.parse_string(line)
		if not result is Dictionary:last_error="Invalid backend response";return {"ok":false,"error":last_error}
		if result.get("ok",false) and not upload_commands.is_empty():
			send(upload_commands.pop_front());return {}
		if not result.get("ok",false):upload_commands.clear()
		if result.get("ok",false):last_state=result.state
		else:last_error=str(result.get("error","Backend failed"))
		return result
	if Time.get_ticks_msec()-started_at>3000:
		last_error="Backend response timeout";close();return {"ok":false,"error":last_error}
	return {}

func close() -> void:
	if not process.is_empty():
		# Only this adapter's child PID. No process enumeration or global cleanup.
		if OS.is_process_running(int(process.pid)):OS.kill(int(process.pid))
		process.clear()
	pending=false;buffer="";last_state={};upload_commands.clear()

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and not process.is_empty():
		if OS.is_process_running(int(process.pid)):OS.kill(int(process.pid))
