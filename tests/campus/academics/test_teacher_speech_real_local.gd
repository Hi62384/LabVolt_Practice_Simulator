extends SceneTree
## Run only with a verified temporary Piper model copied into assets/campus/faculty/voices.
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const MODEL="res://assets/campus/faculty/voices/en_US-joe-medium.onnx"
var done:=false
var status: String=""
var stream: AudioStreamWAV
func _initialize() -> void:call_deferred("run")
func run() -> void:
	assert(FileAccess.file_exists(MODEL) and FileAccess.file_exists(MODEL+".json"))
	var synth:=Synth.new();root.add_child(synth)
	synth.profile_adapter=func():return {"joe":{"model":MODEL,"speaker":0,"rate":1.0,"gain":1.0,"pause_ms":100}}
	synth.completed.connect(func(_room,_serial,_key,wav,result):stream=wav;status=result;done=true)
	var player:=Player.new();root.add_child(player)
	var anchor:=Node3D.new();root.add_child(anchor)
	assert(player.accept("ac_lab","Joe",1,"Check the total resistance.",1,anchor))
	assert(synth.request("ac_lab",1,"joe","Check the total resistance.","joe:sample")=="queued")
	var deadline:=Time.get_ticks_msec()+20000
	while not done and Time.get_ticks_msec()<deadline:await process_frame
	assert(done and status=="ok" and stream!=null)
	assert(stream.mix_rate==22050 and stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.data.is_empty())
	assert(player.cache_stream("joe:sample",stream))
	assert(player.deliver_stream("ac_lab",1,stream))
	assert(player.active.has("ac_lab") and player.active.ac_lab.player is AudioStreamPlayer3D)
	player.cancel("ac_lab");synth.clear_session()
	anchor.queue_free();player.queue_free();synth.queue_free()
	print("TEACHER_SPEECH_REAL_LOCAL PASS (one voice; playback path constructed)")
	quit()
