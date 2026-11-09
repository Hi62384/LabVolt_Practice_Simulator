extends Node3D
# Eight spatial voices, 22050 Hz output. Circuit waveforms remain solver-limited
# (currently 2000 samples/s); interpolation cannot recover ultrasonic content.
const OUTPUT_RATE := 22050.0
const MAX_VOICES := 8
const MAX_SAMPLES := 800
var voices := {}
var phases := {}
var levels := {}
var frequencies := {}
var queues := {}
var cursors := {}
var last_times := {}
var filters := {}
var rates := {}
var envelopes := {}
var outputs := {}
var active_tone: AudioStreamWAV
var voice_kinds := {}

func update_circuit(board: Dictionary,result: Dictionary) -> void:
 var active := {}
 var catalog: Dictionary=preload("res://scripts/breadboard_model.gd").catalog(board)
 for device in preload("res://scripts/breadboard_model.gd").devices(board):
  var kind: String=str(catalog.get(device.part.type,{}).get("kind",""))
  if kind not in ["buzzer","speaker","piezo"]:continue
  if active.size()>=MAX_VOICES:break
  var id: String=device.id;active[id]=true
  # IDs survive editor replacement. A stream cannot survive a change of kind.
  if voices.has(id) and str(voice_kinds.get(id,""))!=kind:_remove_voice(id)
  var amps := maxf(0,float(result.get("i",{}).get(id,0)))
  levels[id]=clampf((amps*1000.-2.5)/2.5,0,1)*.12
  frequencies[id]=440.
  if kind in ["speaker","piezo"]:
   if not queues.has(id):_reset_waveform(id)
   var incoming: Array=result.get("audio",{}).get(id,[])
   if not incoming.is_empty() and float(incoming[-1][0])<float(last_times[id]):_reset_waveform(id)
   for sample in incoming:
    var time := float(sample[0]);var voltage := float(sample[1])
    if not is_finite(time) or not is_finite(voltage) or time<=float(last_times[id]):continue
    var dt := time-float(last_times[id])
    if float(last_times[id])>=0 and dt>0 and dt<.02:rates[id]=1./dt
    var x := clampf(voltage*.2,-.8,.8)
    # 20 Hz DC blocker, coefficient follows actual incoming sample interval.
    var alpha := exp(-TAU*20./float(rates[id]))
    var history: Vector2=filters[id];var y := alpha*(history.y+x-history.x)
    filters[id]=Vector2(x,y);queues[id].append(clampf(y,-.8,.8));last_times[id]=time
   if queues[id].size()>MAX_SAMPLES:
    queues[id]=queues[id].slice(queues[id].size()-400);cursors[id]=0.
  if not voices.has(id):
   var player := AudioStreamPlayer3D.new()
   player.bus = "Effects"
   if kind=="buzzer":player.stream=_buzzer_stream()
   else:
    var stream := AudioStreamGenerator.new();stream.mix_rate=OUTPUT_RATE;stream.buffer_length=.08;player.stream=stream
   player.volume_linear=0. if kind=="buzzer" else 1.
   player.unit_size=2;player.max_distance=18;player.max_db=0.
   add_child(player);player.play();voices[id]=player
   phases[id]=0.;envelopes[id]=0.;outputs[id]=0.;voice_kinds[id]=kind
  if kind=="buzzer":
   # Mixer-owned looping tone cannot underrun when rendering stalls.
   voices[id].volume_linear=float(levels[id])*.5
 for id in voices.keys():
  if not active.has(id):
   _remove_voice(id)
 # Prime immediately. Startup/render stalls otherwise leave an empty generator.
 _fill_buffers()

func _reset_waveform(id: String) -> void:
 queues[id]=[];cursors[id]=0.;last_times[id]=-1.;filters[id]=Vector2.ZERO;rates[id]=2000.

func _process(_delta: float) -> void:
 _fill_buffers()

func _fill_buffers() -> void:
 for id in voices:
  if not voices[id].stream is AudioStreamGenerator:continue
  var playback=voices[id].get_stream_playback()
  if playback==null:continue
  var count: int=mini(playback.get_frames_available(),4096)
  var frames := PackedVector2Array();frames.resize(count)
  for index in count:
   # 5 ms envelope avoids clicks when a powered active buzzer changes state.
   envelopes[id]=move_toward(float(envelopes[id]),float(levels.get(id,0)),.12/(OUTPUT_RATE*.005))
   var value := sin(float(phases[id])*TAU)*float(envelopes[id])
   if queues.has(id):
    var cursor: float=cursors[id];var start := int(cursor)
    if start+1<queues[id].size():
     value=lerpf(float(queues[id][start]),float(queues[id][start+1]),cursor-start)
     cursors[id]+=float(rates[id])/OUTPUT_RATE
    else:
     # Fade an underrun instead of holding DC or making a discontinuity.
     value=move_toward(float(outputs[id]),0.,.8/(OUTPUT_RATE*.005))
   outputs[id]=value
   # Fixed headroom for all eight voices; do not normalize by active count.
   frames[index]=Vector2(value,value)*(.1 if queues.has(id) else .5)
   phases[id]=fposmod(float(phases[id])+float(frequencies.get(id,440))/OUTPUT_RATE,1.)
  playback.push_buffer(frames)
  if queues.has(id):
   var consumed := mini(int(cursors[id]),maxi(0,queues[id].size()-1))
   if consumed>0:queues[id]=queues[id].slice(consumed);cursors[id]-=consumed

func _buzzer_stream() -> AudioStreamWAV:
 if active_tone!=null:return active_tone
 active_tone=AudioStreamWAV.new();active_tone.format=AudioStreamWAV.FORMAT_16_BITS
 active_tone.mix_rate=int(OUTPUT_RATE);active_tone.loop_mode=AudioStreamWAV.LOOP_FORWARD
 # Exactly 440 complete periods in one second: seamless integral loop.
 active_tone.loop_begin=0;active_tone.loop_end=int(OUTPUT_RATE)
 var data := PackedByteArray();data.resize(int(OUTPUT_RATE)*2)
 for i in int(OUTPUT_RATE):data.encode_s16(i*2,int(sin(TAU*440.*i/OUTPUT_RATE)*32767))
 active_tone.data=data;return active_tone




func _remove_voice(id: String) -> void:
 if voices.has(id):
  var player: AudioStreamPlayer3D=voices[id]
  player.stop();remove_child(player);player.queue_free()
 for state in [voices,phases,levels,frequencies,queues,cursors,last_times,filters,rates,envelopes,outputs,voice_kinds]:state.erase(id)
