extends RefCounted

const Zip = preload("res://scripts/campus/computers/VirtualZip.cs")
const Files = preload("res://scripts/campus/computers/device_filesystem.gd")
const MAX_EXPANDED := 16 * 1024 * 1024
const FIELD_LIMITS := {"id":64,"name":64,"publisher":64,"version":36,"description":400,"entry":96}
const CONTENT := ["html","htm","css","js","mjs","json","png","jpg","jpeg","webp","gif","avif","svg","ico",
	"woff","woff2","ttf","otf","wasm","mp3","ogg","wav","mp4","webm","txt","md"]

static func inspect(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size()>8*1024*1024:return {"error":"The package exceeds the 8 MiB download limit."}
	var extracted: Dictionary=Zip.new().Unpack(bytes,MAX_EXPANDED)
	if extracted.has("error"):return extracted
	return validate(extracted.files)

static func validate(entries: Dictionary) -> Dictionary:
	var manifest_bytes: Variant=entries.get("manifest.json")
	if not manifest_bytes is PackedByteArray or manifest_bytes.size()>16*1024:return {"error":"The package needs a root manifest.json under 16 KiB."}
	var manifest: Variant=JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary or manifest.get("schema")!=1 or manifest.get("runtime")!="web":
		return {"error":"Use a version 1 Campus OS web application manifest."}
	for field in FIELD_LIMITS:
		var value: Variant=manifest.get(field)
		if not value is String or value.strip_edges().is_empty() or value.length()>FIELD_LIMITS[field]:
			return {"error":"Invalid manifest field: "+field}
	var id: String=manifest.id
	if not id.contains(".") or id.begins_with(".") or id.ends_with(".") or id.contains(".."):
		return {"error":"Use a namespaced application ID such as example.notes."}
	for character in id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789.-":return {"error":"Invalid application ID."}
	var parts: PackedStringArray=str(manifest.version).split(".")
	if parts.size()!=3:return {"error":"Use a three-part version such as 1.2.0."}
	for part in parts:
		if not part.is_valid_int() or int(part)<0 or part!=str(int(part)):return {"error":"Invalid application version."}
	var permissions: Variant=manifest.get("permissions",[])
	if not permissions is Array or not permissions.is_empty():
		return {"error":"Privileged package permissions are unavailable."}
	var dependencies: Variant=manifest.get("dependencies",[])
	if manifest.get("minimum_os",1)!=1 or not dependencies is Array or not dependencies.is_empty():
		return {"error":"The package needs an unsupported Campus OS version or dependency."}
	var start: String=manifest.entry
	if not entries.has(start) or start.get_extension().to_lower() not in ["html","htm"]:
		return {"error":"The entry point must be an HTML file in the package."}
	var icon: Variant=manifest.get("icon","")
	if not icon is String or (not icon.is_empty() and (not entries.has(icon) or icon.get_extension().to_lower()!="png")):
		return {"error":"The optional icon must reference a packaged PNG."}
	var seen:={}
	var size:=0
	var count:=0
	for name: String in entries:
		var path:=name.trim_suffix("/")
		var folder:=name.ends_with("/")
		var key:=path.to_lower()
		if not Files.valid_path(path) or seen.has(key):return {"error":"The package contains an invalid or conflicting path."}
		seen[key]=folder
		if folder:continue
		if path.get_extension().to_lower() not in CONTENT:return {"error":"Unsupported application resource: "+name}
		var data: PackedByteArray=entries[name]
		size+=data.size()
		count+=1
		if size>MAX_EXPANDED:return {"error":"The package exceeds the unpacked size limit."}
	for key: String in seen:
		var parent:=key.get_base_dir()
		while not parent.is_empty():
			if seen.has(parent) and not seen[parent]:return {"error":"A package file conflicts with a directory."}
			parent=parent.get_base_dir()
	return {"manifest":manifest,"bytes":size,"files":count}
