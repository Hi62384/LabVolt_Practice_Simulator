extends RefCounted
## A resumed sandbox process is not proof that its boundary/runtime was verified.
## Host-owned receipt only; never accepted from firmware, inventory or RPC data.
const CHECKS=["files","network","timeout","output","descendants","resources","compiler_pipeline"]
static func install_root() -> String:
 var local:=OS.get_environment("LOCALAPPDATA")
 if local.is_empty():return ProjectSettings.globalize_path("user://firmware_toolchain")
 return local.path_join("LabVolt/FirmwareToolchain")
static func script_root() -> String:
 var bundled:=OS.get_executable_path().get_base_dir().path_join("firmware_toolchain")
 if FileAccess.file_exists(bundled.path_join("windows_sandbox.cs")):return bundled
 return ProjectSettings.globalize_path("res://scripts/firmware_toolchain")
static func verified() -> bool:
 var path=install_root().path_join("boundary-acceptance.json")
 if not FileAccess.file_exists(path):return false
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:return false
 if file.get_length()>8192:file.close();return false
 var receipt:Variant=JSON.parse_string(file.get_as_text());file.close()
 if not receipt is Dictionary or receipt.get("schema",0)!=2:return false
 var root:=script_root()
 for pair in [["launcher_sha256","windows_sandbox.cs"],["broker_sha256","broker.ps1"],["plan_sha256","build_plan.ps1"],["probe_sha256","acceptance_probe.exe"]]:
  var script_path: String=root.path_join(pair[1])
  if not FileAccess.file_exists(script_path) or receipt.get(pair[0],"")!=FileAccess.get_sha256(script_path):return false
 var manifest_path:=install_root().path_join("trusted-manifest.json")
 if not FileAccess.file_exists(manifest_path):return false
 if receipt.get("manifest_sha256","")!=FileAccess.get_sha256(manifest_path):return false
 if receipt.get("os","")!=OS.get_name()+":"+OS.get_version():return false
 var checks:Variant=receipt.get("checks",{})
 if not checks is Dictionary:return false
 for key in CHECKS:
  if not checks.get(key,false) is bool or checks.get(key,false)!=true:return false
 return true
static func explanation() -> String:
 return "The bundled compiler will be prepared and checked on first use. If setup fails, source drafts and imported firmware remain available."
