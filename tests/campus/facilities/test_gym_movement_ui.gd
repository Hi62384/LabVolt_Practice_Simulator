extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
class FakeController extends Node:
 var sent:={}
 func request(value: Dictionary) -> void:sent=value.duplicate(true)
var failures: Array[String]=[]
func check(value: bool,message: String):
 if not value:failures.append(message)
func _initialize():call_deferred("run")
func run():
 var panel=preload("res://scripts/campus/facilities/facility_panel.gd").new();root.add_child(panel)
 panel.station_kind="curl";panel.station_id="gym/curl"
 var profile=Host.empty_profile();profile.gym={"muscles":{}}
 panel.state={"level":1,"profile":profile,"active":{"type":"exercise","exercise":"curl","reps":0,"weight":20,"phase":0,"half_ms":900}}
 panel.redraw()
 check(panel.body.find_children("*","Label",true,false).any(func(label):return label.text=="Biceps curl"),"active exercise name was not shown")
 var controls=panel.find_children("*","HSlider",true,false)
 if controls.size()!=1:
  push_error("Expected one effort control");quit(1);return
 var slider: HSlider=controls[0]
 var control=slider.get_parent()
 check(not panel.workout_reached,"movement started complete")
 slider.value=0.0;control.held=true
 for i in 10:control._process(.1)
 check(is_zero_approx(control.progress),"insufficient effort advanced the lift")
 slider.value=.65
 for i in 100:
  control._process(.1)
  if panel.workout_reached:break
 check(panel.workout_reached,"controlled effort failed to complete movement")
 panel.workout_ready_at=0;panel._process(.1)
 check(not panel.workout_step.disabled,"completed movement could not be submitted")
 var controller:=FakeController.new();root.add_child(controller);panel.controller=controller
 panel.workout_step.pressed.emit()
 check(controller.sent.get("op","")=="beat" and controller.sent.get("sequence",0)==1,"completed movement did not send the host action")
 var failure=preload("res://scripts/campus/facilities/gym_lift_control.gd").new();root.add_child(failure)
 failure.configure(20,30,.8,false)
 var outcome:={"failed":false};failure.failure_ready.connect(func():outcome.failed=true)
 failure.held=true
 for i in 12:failure._process(.1)
 check(outcome.failed and is_zero_approx(failure.progress),"impossible lift did not stall and reach failure")
 failure.queue_free()
 var curl=preload("res://scripts/campus/facilities/gym_lift_control.gd").new();root.add_child(curl);curl.configure(100,80,1,false,"curl")
 var deadlift=preload("res://scripts/campus/facilities/gym_lift_control.gd").new();root.add_child(deadlift);deadlift.configure(100,80,1,false,"deadlift")
 check(absf(curl._target_effort()-deadlift._target_effort())>.1,"exercise types used identical force curves")
 curl.queue_free();deadlift.queue_free()
 for failure_message in failures:push_error(failure_message)
 print("GYM_MOVEMENT ","PASS" if failures.is_empty() else "FAIL")
 controller.queue_free();panel.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
