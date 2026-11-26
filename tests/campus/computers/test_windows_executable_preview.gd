extends SceneTree

const Viewer = preload("res://scripts/campus/computers/file_viewer.gd")
const Inspector = preload("res://scripts/campus/computers/WindowsExecutableInspector.cs")
const Downloads = preload("res://scripts/campus/computers/browser_download.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Pass the window.exe built by test_window_capture.ps1.")
		quit(1)
		return
	var fixture:=FileAccess.get_file_as_bytes(args[0])
	var inspector:=Inspector.new()
	var inspected: Dictionary=inspector.Inspect(fixture)
	assert(inspected.get("architecture")=="x64" and inspected.get("runtime")=="Native entry point")
	assert(not inspected.get("kind","").is_empty())
	assert(inspector.Inspect(fixture.slice(0,512)).has("error"))
	var fake:=PackedByteArray()
	fake.resize(128)
	fake[0]=77
	fake[1]=90
	assert(inspector.Inspect(fake).has("error"))
	var viewer:=Viewer.new()
	root.add_child(viewer)
	viewer.show_file("Downloads/window.exe",fixture)
	var labels:=viewer.body.find_children("*","Label",true,false)
	assert(labels.any(func(label):return label.text=="x64"))
	assert(labels.any(func(label):return label.text=="Native entry point"))
	for extension in ["msix","msixbundle"]:
		assert(Downloads.extension_for("setup."+extension,"application/octet-stream")==extension)
		assert(Viewer.app_for("setup."+extension)=="Windows Application")
		assert(not Downloads.valid(fake,extension))
	viewer.free()
	print("WINDOWS_EXECUTABLE_PREVIEW PASS")
	quit()
