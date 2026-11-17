extends SceneTree
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var saved:=Rules.empty_profile()
var now:=1000
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var controller=Controller.new();root.add_child(controller)
	var host=controller.host
	host.clock=func():return now
	host.context=func(_peer):return {"identity":"local","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_identity):return saved.duplicate(true)
	host.commit_profile=func(_identity,_dollars,value):saved=value.duplicate(true);return true
	host.anchors={"gym/pushup":{"kind":"pushup","room_id":"gym","position":Vector3.ZERO}}
	var result: Dictionary=host.act(1,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0,"sequence":1})
	if result.get("ok",false):
		for seq in [2,3]:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":seq})
			if not result.get("ok",false):break
	controller.finish_session()
	var history: Array=saved.get("gym",{}).get("history",[])
	var ok: bool=result.get("ok",false) and host.active.is_empty() and history.size()==1 and history[0].get("outcome","")=="interrupted" and history[0].get("reps",0)==1
	if not ok:push_error("Session checkpoint did not persist the interrupted set")
	print("GYM_SESSION_CHECKPOINT ","PASS" if ok else "FAIL")
	host.clock=Callable();host.context=Callable();host.load_profile=Callable();host.commit_profile=Callable()
	controller.free();quit(0 if ok else 1)
