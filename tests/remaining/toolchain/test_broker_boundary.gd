extends SceneTree
var result := {}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service := preload("res://scripts/firmware_toolchain/compile_service.gd").new();root.add_child(service)
	service.finished.connect(func(value):result=value)
	var request: Dictionary=service.start("uno",{"sketch.ino":"#include \"C:/outside/private.h\"\nvoid setup(){}\nvoid loop(){}"},"sketch.ino")
	if not request.ok:push_error(str(request));quit(1);return
	var deadline := Time.get_ticks_msec()+15000
	while result.is_empty() and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	var ok: bool=not result.is_empty() and not result.get("ok",true) and result.get("status","") in ["sandbox_unavailable","dependencies_missing"]
	if not ok:push_error("Boundary must fail closed on this unconfigured host: "+str(result))
	print("BROKER_BOUNDARY result="+JSON.stringify(result))
	service.free()
	quit(0 if ok else 1)
