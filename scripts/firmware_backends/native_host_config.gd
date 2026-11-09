extends RefCounted
## Host-local discovery only. No paths come from saves, components, RPC or PATH.
## Program Files installations precede the bundled desktop runtime fallback.
static var cached_node := ""
static func executable() -> String:
	if not cached_node.is_empty() and FileAccess.file_exists(cached_node):return cached_node
	var user := OS.get_environment("USERPROFILE")
	var candidates := ["C:/Program Files/nodejs/node.exe","C:/Program Files (x86)/nodejs/node.exe"]
	if not user.is_empty():candidates.append(user.path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe"))
	for path in candidates:
		if not FileAccess.file_exists(path):continue
		var output: Array=[]
		if OS.execute(path,PackedStringArray(["--version"]),output)!=0:continue
		var version: PackedStringArray=str(output[0]).strip_edges().trim_prefix("v").split(".") if not output.is_empty() else PackedStringArray()
		if version.size()>=2 and version[0].is_valid_int() and version[1].is_valid_int() and (int(version[0])>20 or (int(version[0])==20 and int(version[1])>=19)):
			cached_node=path;return path
	return ""
static func dependency_report() -> Dictionary:
	var node := executable()
	var backend := ProjectSettings.globalize_path("res://scripts/firmware_backends")
	var ready := not node.is_empty() and FileAccess.file_exists(backend.path_join("bridge.cjs"))
	var compiler := compiler_report()
	var result := {"schema":1,"node":node,"backend_directory":backend,"runtime_ready":ready,"configuration_required":not ready,"compiler_enabled":compiler.enabled,"source_compile_status":compiler.status,"compiler":compiler,"spi_i2c":"Consult the current electrical native backend capabilities","micropython":false,"boot_rom":false,"usb":false}
	# Known installation locations are proposals, never executable guest data.
	var local := OS.get_environment("LOCALAPPDATA")
	var avr_roots: Array=[]
	if not local.is_empty():
		var root := local.path_join("Arduino15/packages/arduino/tools/avr-gcc")
		if DirAccess.dir_exists_absolute(root):
			for version in DirAccess.get_directories_at(root):
				var candidate := root.path_join(version).path_join("bin/avr-g++.exe")
				if FileAccess.file_exists(candidate):avr_roots.append(candidate)
	result.compiler_candidates=avr_roots
	return result

static func compiler_report() -> Dictionary:
	var manifest := "user://firmware_toolchain/trusted-manifest.json"
	var state := {}
	if FileAccess.file_exists("user://firmware_toolchain/isolation-status.json"):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://firmware_toolchain/isolation-status.json"))
		if value is Dictionary:state=value
	var installed := FileAccess.file_exists(manifest)
	return {"enabled":installed and preload("res://scripts/firmware_toolchain/acceptance.gd").verified(),"manifest_installed":installed,"last_probe":state,"status":str(state.get("error","Compile checks Windows LPAC isolation first; official host-local toolchain setup is required.")) if preload("res://scripts/firmware_toolchain/acceptance.gd").verified() else preload("res://scripts/firmware_toolchain/acceptance.gd").explanation(),"setup_script":"res://scripts/firmware_toolchain/setup_official.ps1","pico":"Bare-metal C/C++ target when official Arm toolchain is installed; general SDK/MicroPython runtime not claimed"}
