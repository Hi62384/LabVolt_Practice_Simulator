extends SceneTree
const Activity=preload("res://scripts/campus/voice/teacher_sound_activity.gd")
func packet(value: int) -> PackedByteArray:
 var result:=PackedByteArray();result.resize(640)
 for i in range(0,640,2):result.encode_s16(i,value)
 return result
func _initialize() -> void:
 var activity:=Activity.new();var quiet:=packet(300);var sound:=packet(6000)
 for i in 10:assert(activity.observe(1,quiet,i*20)==0.0)
 for i in 5:assert(activity.observe(1,sound,200+i*20)==0.0)
 assert(activity.observe(1,sound,300)>0.0)
 for i in 20:assert(activity.observe(1,sound,320+i*20)==0.0)
 for i in 5:assert(activity.observe(2,sound,5000+i*20)==0.0)
 assert(activity.observe(2,sound,5100)>0.0)
 assert(not str(activity.state).contains("6000"))
 activity.forget(1);assert(not activity.state.has(1))
 assert(activity.observe(3,PackedByteArray(),7000)==0.0)
 for i in 5:assert(activity.observe(3,sound,8000+i*20)==0.0)
 assert(activity.observe(3,sound,9000)==0.0)
 var medium:=packet(1000)
 for i in 6:assert(activity.observe(4,medium,10000+i*20,.5)==0.0)
 for i in 5:assert(activity.observe(5,medium,10000+i*20,2.0)==0.0)
 assert(activity.observe(5,medium,10100,2.0)>0.0)
 print("TEACHER_SOUND_ACTIVITY PASS");quit(0)
