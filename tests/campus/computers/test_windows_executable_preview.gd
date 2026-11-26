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
	assert(str(inspected.sha256).length()==64)
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
	var manifest := '<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"><Identity Name="Campus.Test" Publisher="CN=Campus Fixture" Version="1.2.3.4" ProcessorArchitecture="arm64"/></Package>'
	var packaged := _package("AppxManifest.xml",manifest)
	var app: Dictionary=inspector.InspectPackage("msix",packaged)
	assert(app.get("name","")=="Campus.Test" and app.get("architecture","")=="arm64")
	assert(app.get("publisher","")=="CN=Campus Fixture" and app.get("version","")=="1.2.3.4")
	assert(inspector.InspectPackage("msixbundle",packaged).has("error"))
	var bundle := '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle"><Identity Name="Campus.Test" Publisher="CN=Campus Fixture" Version="1.2.3.4"/><Packages><Package Architecture="x64"/><Package Architecture="arm64"/></Packages></Bundle>'
	assert(inspector.InspectPackage("msixbundle",_package("AppxMetadata/AppxBundleManifest.xml",bundle)).get("architecture","")=="x64, arm64")
	var invalid := _package("AppxManifest.xml",'<!DOCTYPE Package [<!ENTITY name "Injected">]>'+manifest)
	assert(inspector.InspectPackage("msix",invalid).has("error"))
	assert(inspector.InspectPackage("msix",_package("AppxManifest.xml","x".repeat(262145))).has("error"))
	viewer.free()
	print("WINDOWS_EXECUTABLE_PREVIEW PASS")
	quit()

func _package(path: String, xml: String) -> PackedByteArray:
	var target := "user://windows-preview-test.zip"
	var packer := ZIPPacker.new()
	assert(packer.open(target)==OK)
	assert(packer.start_file(path)==OK)
	assert(packer.write_file(xml.to_utf8_buffer())==OK)
	assert(packer.close_file()==OK)
	assert(packer.close()==OK)
	return FileAccess.get_file_as_bytes(target)
