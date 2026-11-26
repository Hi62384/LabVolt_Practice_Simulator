extends SceneTree

const Types=preload("res://scripts/campus/computers/browser_download.gd")
const Inspector=preload("res://scripts/campus/computers/WindowsExecutableInspector.cs")
const ROOT:="res://CampusOS-Test-Files"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var seen: Dictionary={}
	for folder in DirAccess.get_directories_at(ROOT):
		for file in DirAccess.get_files_at(ROOT+"/"+folder):
			var extension:=file.get_extension().to_lower()
			var data:=FileAccess.get_file_as_bytes(ROOT+"/"+folder+"/"+file)
			assert(Types.extension_for(file,"application/octet-stream")==extension,file)
			assert(Types.valid(data,extension),"Invalid fixture "+file)
			if extension in ["exe","msi","msix","msixbundle"]:
				var inspector:=Inspector.new()
				var metadata: Dictionary=inspector.Inspect(data) if extension=="exe" else inspector.InspectPackage(extension,data)
				assert(not metadata.has("error"),file+" "+str(metadata.get("error","")))
			seen[extension]=true
	for group in [Types.TEXT_EXTENSIONS,Types.CODE_EXTENSIONS,Types.IMAGE_EXTENSIONS,Types.AUDIO_EXTENSIONS,Types.VIDEO_EXTENSIONS,Types.MODEL_EXTENSIONS,Types.STORED_EXTENSIONS]:
		for extension in group:assert(seen.has(extension),"Missing ."+extension+" fixture")
	print("CAMPUS_FILE_FIXTURES PASS (%d extensions)"%seen.size())
	quit()
