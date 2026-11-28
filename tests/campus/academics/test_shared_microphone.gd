extends SceneTree
const Activity=preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const Targeting=preload("res://scripts/campus/voice/conversation_targeting.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var processor=Processor.new()
 var frames:=PackedVector2Array()
 for i in 960:
  var sample:=sin(float(i)*TAU*220.0/48000.0)*.08
  frames.append(Vector2(sample,sample))
 var result: Dictionary=processor.Process(frames,48000.,1.,false)
 assert(result.pcm.size()==640 and result.speech and result.rms>0.01)
 # Sensitivity reaches the real processor. Quiet speech can use the higher
 # setting; normal and loud voiced input must not require shouting.
 var quiet:=PackedVector2Array()
 var loud:=PackedVector2Array()
 var noise:=PackedVector2Array()
 var random:=RandomNumberGenerator.new();random.seed=5102
 for i in 960:
  var wave:=sin(float(i)*TAU*220.0/48000.0)
  quiet.append(Vector2(wave,wave)*.005)
  loud.append(Vector2(wave,wave)*.9)
  noise.append(Vector2(random.randf_range(-.04,.04),random.randf_range(-.04,.04)))
 assert(not Processor.new().Process(quiet,48000.,.5,false).speech)
 assert(Processor.new().Process(quiet,48000.,2.,false).speech)
 assert(Processor.new().Process(loud,48000.,1.,false).speech)
 assert(not Processor.new().Process(noise,48000.,1.,false).speech,"Loud broadband noise is not automatically speech")
 var activity=Activity.new()
 var rollover:=0
 var final_count:=0
 var emitted_bytes:=0
 var stable_turn:=-1
 for i in 3100:
  var packet: Dictionary=activity.PushPcm(result.pcm,true)
  if packet.get("onset",false):stable_turn=int(packet.turn_id)
  if packet.has("audio"):
   assert(packet.turn_id==stable_turn)
   assert(packet.continued,"A long question ended prematurely")
   rollover+=1;emitted_bytes+=packet.audio.size()
 var silence:=PackedByteArray();silence.resize(640)
 for i in 110:
  var packet: Dictionary=activity.PushPcm(silence,false)
  if packet.has("audio"):
   assert(not packet.continued and packet.turn_id==stable_turn)
   final_count+=1;emitted_bytes+=packet.audio.size()
 assert(rollover==2 and final_count==1 and emitted_bytes>=16000*2*61)
 assert(activity.Flush().is_empty())
 var candidates: Array=[{"id":"bro","position":Vector3(0,0,-2),"visible":true},{"id":"volts","position":Vector3(2,0,-2),"visible":true}]
 assert(Targeting.select(candidates,Vector3.ZERO,Vector3.FORWARD).id=="bro")
 assert(Targeting.select(candidates,Vector3.ZERO,Vector3.FORWARD,"volts").id=="volts")
 assert(Targeting.select([{ "id":"wall","position":Vector3(0,0,-1),"visible":false}],Vector3.ZERO,Vector3.FORWARD).is_empty())
 assert(Targeting.select([{ "id":"aside","position":Vector3(1,0,-2),"visible":true}],Vector3.ZERO,Vector3.FORWARD,"",[Vector3(0,0,-1)]).is_empty())
 assert(Targeting.acknowledgement("Yeah!") and not Targeting.acknowledgement("Yeah, but what does that mean?"))
 print("SHARED_MICROPHONE PASS: native resampling, 62-second continuous turn, targeting and acknowledgements")
 quit()
