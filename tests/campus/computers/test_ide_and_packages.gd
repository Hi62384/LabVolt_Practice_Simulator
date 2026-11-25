extends SceneTree

const Execution=preload("res://scripts/campus/computers/ide_execution.gd")
const Package=preload("res://scripts/campus/computers/application_package.gd")
const Zip=preload("res://scripts/campus/computers/VirtualZip.cs")

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
	runtime.queue_free()
	print("IDE_AND_PACKAGES PASS")
	quit()
