extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var now:=1000
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var identity:="gym-history-test"
	var profile=preload("res://scripts/electronics_profile.gd").new();profile.open(identity)
	var adapter=preload("res://scripts/campus/facilities/profile_adapter.gd").new()
	adapter.profiles[identity]=profile;adapter.is_authority=func():return true
	var host=Host.new()
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":identity,"position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=adapter.load_facilities;host.commit_profile=adapter.commit
	host.anchors={"gym/pushup":{"kind":"pushup","room_id":"gym","position":Vector3.ZERO}}
	var start: Dictionary=host.act(1,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0,"sequence":1})
	now+=100
	var stopped: Dictionary=host.act(1,{"op":"cancel","sequence":2}) if start.ok else {}
	var reopened=preload("res://scripts/electronics_profile.gd").new();reopened.open(identity)
	var saved: Dictionary=reopened.data.get("facilities",{})
	var history: Array=saved.get("gym",{}).get("history",[])
	var ok: bool=start.ok and stopped.get("ok",false) and history.size()==1 and history[0].get("outcome","")=="cancelled" and Host.valid_profile(saved)
	if not ok:push_error("Set history did not survive the real profile save and reopen")
	print("GYM_HISTORY_PERSISTENCE ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
