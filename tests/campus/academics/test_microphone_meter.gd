extends SceneTree
const Meter=preload("res://scripts/campus/voice/microphone_meter.gd")
func _initialize() -> void:
 var meter:=Meter.new();root.add_child(meter);meter.build()
 assert(not meter.running and meter.player==null and meter.capture==null)
 assert(is_equal_approx(Meter.level(PackedVector2Array([Vector2(.1,.1),Vector2(-.1,-.1)])),.1))
 assert(Meter.level(PackedVector2Array())==0.0)
 assert(not Meter.above_threshold(.03,1.0) and Meter.above_threshold(.03,2.0))
 assert(not Meter.above_threshold(NAN,1.0))
 meter._stop();assert(not meter.running and meter.bus_name.is_empty())
 print("MICROPHONE_METER PASS");quit(0)
