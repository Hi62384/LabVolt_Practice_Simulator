extends SceneTree
## Frozen pre-change implementations are retained only for this paired native
## benchmark. These are local serialization/conversion measurements, not API
## or physical-microphone latency claims.
const Session=preload("res://scripts/campus/ai/openai_transcription_session.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
func _initialize() -> void:run.call_deferred()
func original_resample(pcm: PackedByteArray) -> PackedByteArray:
 var frames:=pcm.size()/2
 var output:=PackedByteArray()
 if frames<=0 or pcm.size()%2:return output
 var count:=int(ceil(float(frames)*1.5));output.resize(count*2)
 for i in count:
  var pos:=float(i)*2./3.;var index:=mini(int(pos),frames-1)
  var a:=pcm.decode_s16(index*2);var b:=pcm.decode_s16(mini(index+1,frames-1)*2)
  output.encode_s16(i*2,clampi(roundi(lerpf(float(a),float(b),pos-float(index))),-32768,32767))
 return output
func original_wav(samples: PackedByteArray) -> PackedByteArray:
 var wav:=PackedByteArray();wav.resize(44+samples.size())
 for pair in [[0,"RIFF"],[8,"WAVE"],[12,"fmt "],[36,"data"]]:
  var bytes: PackedByteArray=str(pair[1]).to_ascii_buffer()
  for i in 4:wav[int(pair[0])+i]=bytes[i]
 wav.encode_u32(4,36+samples.size());wav.encode_u32(16,16);wav.encode_u16(20,1);wav.encode_u16(22,1)
 wav.encode_u32(24,16000);wav.encode_u32(28,32000);wav.encode_u16(32,2);wav.encode_u16(34,16);wav.encode_u32(40,samples.size())
 for i in samples.size():wav[44+i]=samples[i]
 return wav
func timed(action: Callable,pcm: PackedByteArray,repeats: int) -> Dictionary:
 var values: Array[int]=[]
 for index in repeats:
  var start:=Time.get_ticks_usec();var result: PackedByteArray=action.call(pcm);values.append(Time.get_ticks_usec()-start)
  assert(not result.is_empty())
 values.sort()
 return {"samples":repeats,"median_ms":float(values[values.size()/2])/1000.,"maximum_ms":float(values.back())/1000.,"all_us":values}
func run() -> void:
 var rows: Array=[]
 # Exercise signed, extremal and odd-length frame interpolation independently
 # of the large constant signal used to avoid benchmark setup overhead.
 var edges:=PackedByteArray()
 for value in [-32768,-32767,-1,0,1,32766,32767]:
  var at:=edges.size();edges.resize(at+2);edges.encode_s16(at,value)
 assert(original_resample(edges)==Session.resample_16k_to_24k(edges))
 for seconds in [1,10,30,180]:
  var pcm:=PackedByteArray();pcm.resize(seconds*32000);pcm.fill(17)
  assert(original_wav(pcm)==TeacherAI.wav_16k(pcm))
  assert(original_resample(pcm)==Session.resample_16k_to_24k(pcm))
  var row:={"recording_seconds":seconds,"source_bytes":pcm.size(),"resample_before":timed(original_resample,pcm,5),"resample_after":timed(Session.resample_16k_to_24k,pcm,5),"wav_before":timed(original_wav,pcm,5),"wav_after":timed(TeacherAI.wav_16k,pcm,5)}
  var processor=Processor.new();var started:=Time.get_ticks_usec()
  processor.BeginResample16kTo24k(pcm);row.worker_dispatch_ms=float(Time.get_ticks_usec()-started)/1000.
  var frames:=0
  while not processor.IsResampleReady():frames+=1;await process_frame
  row.worker_total_ms=float(Time.get_ticks_usec()-started)/1000.;row.frames_yielded=frames
  assert(processor.TakeResampledPcm()==Session.resample_16k_to_24k(pcm))
  rows.append(row)
 var report:={"kind":"paired local native audio benchmark","provider_latency_measured":false,"physical_microphone_measured":false,"godot":Engine.get_version_info(),"results":rows}
 var output:=FileAccess.open("user://transcription-audio-benchmark.json",FileAccess.WRITE)
 output.store_string(JSON.stringify(report,"  "));output.close()
 print("TRANSCRIPTION_AUDIO_BENCHMARK PASS ",JSON.stringify(report))
 quit()
