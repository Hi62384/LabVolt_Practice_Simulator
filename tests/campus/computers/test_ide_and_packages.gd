extends SceneTree

const Execution=preload("res://scripts/campus/computers/ide_execution.gd")
const Package=preload("res://scripts/campus/computers/application_package.gd")
const Zip=preload("res://scripts/campus/computers/VirtualZip.cs")
const Apps=preload("res://scripts/campus/computers/application_registry.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var runtime:=Execution.new()
	root.add_child(runtime)
	runtime.configure_from_host()
	var result:=await runtime.supported_runtimes()
	assert(result.get("runtimes",[]).size()==2)
	var answer:=await runtime.execute("hello.py","print(int(input()) * 2)","21\n")
	assert(answer.contains("Python") and answer.contains("42") and answer.contains("4096 KiB"))
	answer=await runtime.execute("hello.py","rate")
	assert(answer.contains("rate limiting"))
	create_timer(.15).timeout.connect(runtime.stop)
	answer=await runtime.execute("hello.py","pending")
	assert(answer=="Stopped.")
	runtime.endpoint+="/auth"
	runtime.cached_until=0
	result=await runtime.supported_runtimes()
	assert(str(result.get("error","")).contains("rejected"))
	assert(Execution.validate_json("{}")=="Valid JSON")
	assert(Execution.validate_json("{").begins_with("JSON error"))
	var manifest:={"schema":1,"id":"example.counter","name":"Counter","version":"1.0.0","description":"An example","publisher":"LabVolt","entry":"index.html","runtime":"web"}
	var files:={"manifest.json":JSON.stringify(manifest).to_utf8_buffer(),"index.html":"<!doctype html><title>Counter</title>".to_utf8_buffer()}
	assert(Package.inspect(Zip.new().Pack(files)).get("manifest",{}).get("id")=="example.counter")
	files["Index.html"]=files["index.html"]
	assert(Package.inspect(Zip.new().Pack(files)).has("error"))
	files.erase("Index.html")
	files["../other.txt"]="bad".to_utf8_buffer()
	assert(Package.inspect(Zip.new().Pack(files)).has("error"))
	files.erase("../other.txt")
	files["program.exe"]=PackedByteArray([77,90])
	assert(Package.inspect(Zip.new().Pack(files)).has("error"))
	files.erase("program.exe")
	var drive:=Drive.new(64*1024)
	var archive: PackedByteArray=Zip.new().Pack(files)
	var path:="counter.campusapp"
	assert(drive.write_file(path,archive))
	var install:={"op":"install_app","path":path,"sha256":Apps.sha256(archive),"folder":"Counter","shortcut":true}
	assert(Apps.apply(drive,install).is_empty())
	var app: Dictionary=Apps.installed(drive)["example.counter"]
	assert(app.archive=="Program Files/Counter/Application.campusapp" and app.shortcut and app.state=="{}")
	assert(not Apps.apply(drive,install).is_empty())
	var state:={"op":"save_app_state","app_id":app.id,"sha256":app.sha256,"state":'{"count":42}'}
	assert(Apps.apply(drive,state).is_empty())
	state.state="[]"
	assert(not Apps.apply(drive,state).is_empty())
	manifest.version="1.2.0"
	files["manifest.json"]=JSON.stringify(manifest).to_utf8_buffer()
	var update: PackedByteArray=Zip.new().Pack(files)
	assert(drive.write_file(path,update))
	install.replace=true
	assert(not Apps.apply(drive,install).is_empty())
	install.sha256=Apps.sha256(update)
	assert(Apps.apply(drive,install).is_empty())
	app=Apps.installed(drive)["example.counter"]
	assert(app.version=="1.2.0" and app.state=='{"count":42}')
	assert(drive.write_file(path,archive))
	install.sha256=Apps.sha256(archive)
	assert(not Apps.apply(drive,install).is_empty())
	var uninstall:={"op":"uninstall_app","app_id":app.id,"keep_data":true}
	assert(Apps.apply(drive,uninstall).is_empty())
	assert(Apps.installed(drive).is_empty())
	assert(Apps.apply(drive,install).is_empty())
	assert(Apps.installed(drive)["example.counter"].state=='{"count":42}')
	uninstall.keep_data=false
	assert(Apps.apply(drive,uninstall).is_empty())
	assert(not drive.entries.has(Apps.state_path(str(app.id))))
	var full:=Drive.new(archive.size()+1)
	assert(full.write_file(path,archive))
	assert(not Apps.apply(full,install).is_empty() and full.entries.size()==1)
	runtime.queue_free()
	print("IDE_AND_PACKAGES PASS")
	quit()
