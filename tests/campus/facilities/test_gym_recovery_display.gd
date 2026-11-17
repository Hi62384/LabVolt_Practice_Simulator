extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var saved=Host.empty_profile()
func _initialize() -> void:
	var host=Host.new()
	host.authority=func():return true
	host.clock=func():return 1801000
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	saved.gym=Host.GymProgress.empty()
	saved.gym.muscles.biceps={"fatigue":0.6,"strength":0.2,"size":0.2,"stimulus":0.3,"delay":0.0}
	host.load_profile=func(_identity):return saved.duplicate(true)
	host.commit_profile=func(_identity,_dollars,profile):saved=profile.duplicate(true);return true
	host.gym_recovery_clock.student=1000
	var first: Dictionary=host.private_state(1)
	var second: Dictionary=host.private_state(1)
	var a: Dictionary=first.profile.gym.muscles.biceps
	var b: Dictionary=second.profile.gym.muscles.biceps
	var ok: bool=a.fatigue<0.6 and a.size>0.2 and is_equal_approx(a.fatigue,b.fatigue) and is_equal_approx(a.size,b.size) and is_equal_approx(saved.gym.muscles.biceps.fatigue,0.6)
	ok=host.commit_recovery(1) and ok
	var revision: int=saved.revision
	ok=ok and is_equal_approx(saved.gym.muscles.biceps.fatigue,a.fatigue) and is_equal_approx(saved.gym.muscles.biceps.size,a.size)
	ok=host.commit_recovery(1) and ok and saved.revision==revision
	if not ok:push_error("Recovery display is stale, mutates the save, or awards recovery repeatedly")
	print("GYM_RECOVERY_DISPLAY ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
