extends SceneTree
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
class HostController extends Controller:
	func is_host() -> bool:return true

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var controller:=HostController.new();root.add_child(controller)
	controller.host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	controller.host.active[2]={"type":"exercise","exercise":"pushup","station":"gym/pushup","room_id":"gym","position":Vector3.ZERO,"phase":0,"reps":0,"weight":0,"half_ms":700,"started":1234,"mat_position":Vector3(1,.08,2)}
	controller.interested_peers=func(_room):return [1]
	var events:=[];controller.room_event.connect(func(peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	controller._accept_preview(2,.5,0,0,1234)
	var ok: bool=events.size()==1 and is_equal_approx(float(events[0].event.phase),.5) and controller.host.active[2].phase==0 and events[0].event.get("mat_position")==Vector3(1,.08,2)
	controller._accept_preview(2,.8,0,0,1234)
	ok=ok and events.size()==1
	controller.preview_times[2]=-1000
	controller._accept_preview(2,.8,1,0,1234)
	ok=ok and events.size()==1
	controller.host.active[2].phase=1;controller._accept_preview(2,.25,1,0,1234)
	ok=ok and events.size()==2 and is_equal_approx(float(events[1].event.phase),.75)
	controller.preview_times[2]=-1000;controller.host.active[2].reps=1
	controller._accept_preview(2,.5,1,0,1234)
	ok=ok and events.size()==2
	controller._accept_preview(2,.5,1,1,1233)
	ok=ok and events.size()==2
	controller.host.active.erase(2);controller.preview_times[2]=-1000
	controller._accept_preview(2,.5,1,0,1234)
	ok=ok and events.size()==2
	if not ok:push_error("Preview validation, rate limiting, or phase mapping failed")
	controller.free();print("LIFT_PREVIEW ","PASS" if ok else "FAIL");quit(0 if ok else 1)
