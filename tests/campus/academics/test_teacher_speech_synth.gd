extends SceneTree
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
var events: Array=[]
var killed: Array=[]
var running:=true
var output: AudioStreamWAV

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var synth:=Synth.new();root.add_child(synth)
	synth.completed.connect(func(room,serial,key,stream,status):events.append([room,serial,key,stream,status]))
	assert(synth.request("ac_lab",1,"x","Hello","k")=="unavailable")
	synth.profile_adapter=func():return {"x":{"model":"res://assets/campus/faculty/voices/test.onnx","speaker":0,"rate":1.0,"gain":1.0,"pause_ms":100}}
	synth.model_adapter=func(_path):return true
	synth.launch_adapter=func(_exe,_args):return 1234
	synth.running_adapter=func(_pid):return running
	synth.kill_adapter=func(pid):killed.append(pid)
	output=AudioStreamWAV.new();output.format=AudioStreamWAV.FORMAT_16_BITS;output.mix_rate=16000;output.data=PackedByteArray([0,0,100,0])
	synth.load_adapter=func(_path):return output
	assert(synth.request("ac_lab",1,"x","Hello","k")=="queued")
	assert(synth.request("dc_lab",2,"x","Hello","k")=="duplicate")
	for serial in range(2,Synth.MAX_LISTENERS):assert(synth.request("dc_lab",serial+1,"x","Hello","k")=="duplicate")
	assert(synth.request("dc_lab",99,"x","Hello","k")=="busy")
	assert(synth.request("dc_lab",1,"x","Other","k2")=="queued")
	assert(synth.pending.size()==1)
	synth.cancel("dc_lab")
	assert(synth.pending.is_empty())
	assert(events.size()==Synth.MAX_LISTENERS and events.all(func(item):return item[4]=="cancelled"))
	running=false
	var path: String=synth.active.output
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_8(1);file.close()
	synth._process(0)
	assert(events.size()==Synth.MAX_LISTENERS+1 and events[-1][4]=="ok" and events[-1][3]==output)
	assert(not FileAccess.file_exists(path))
	running=true
	assert(synth.request("ac_lab",3,"x","Late","late")=="queued")
	synth.active.started=Time.get_ticks_msec()-Synth.TIMEOUT_MS-1
	synth._process(0)
	assert(events[-1][4]=="timeout" and killed.size()==1)
	assert(synth.request("ac_lab",4,"x","Cancel","cancel")=="queued")
	synth.cancel("ac_lab")
	assert(events[-1][4]=="cancelled" and killed.size()==2 and synth.keys.is_empty())
	synth.launch_adapter=func(_exe,_args):return 0
	assert(synth.request("ac_lab",5,"x","Failure","failure")=="queued")
	assert(events[-1][4]=="engine_unavailable")
	synth.queue_free()
	print("TEACHER_SPEECH_SYNTH PASS (adapter only; no real voice)")
	quit()
