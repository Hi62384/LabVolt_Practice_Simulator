extends RefCounted
## A resumed sandbox process is not proof that its boundary/runtime was verified.
## Host-owned receipt only; never accepted from firmware, inventory or RPC data.
const CHECKS=["files","network","timeout","output","descendants","resources","compiler_pipeline"]
static func verified() -> bool:
 var path="user://firmware_toolchain/boundary-acceptance.json"
 if not FileAccess.file_exists(path):return false
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:return false
 if file.get_length()>8192:file.close();return false
 var receipt:Variant=JSON.parse_string(file.get_as_text());file.close()
 if not receipt is Dictionary or receipt.get("schema",0)!=1:return false
 if receipt.get("launcher_sha256","")!=FileAccess.get_sha256("res://scripts/firmware_toolchain/windows_sandbox.cs"):return false
 if not FileAccess.file_exists("user://firmware_toolchain/trusted-manifest.json"):return false
 if receipt.get("manifest_sha256","")!=FileAccess.get_sha256("user://firmware_toolchain/trusted-manifest.json"):return false
 if receipt.get("os","")!=OS.get_name()+":"+OS.get_version():return false
 var checks:Variant=receipt.get("checks",{})
 if not checks is Dictionary:return false
 for key in CHECKS:
  if not checks.get(key,false) is bool or checks.get(key,false)!=true:return false
 return true
static func explanation() -> String:
 return "Source compilation is unavailable until this computer passes the trusted compiler isolation and runtime checks. You can still edit/save source and import compiled firmware."
