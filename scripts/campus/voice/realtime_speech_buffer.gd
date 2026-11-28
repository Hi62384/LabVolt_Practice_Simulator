extends RefCounted
## One ordered mono 24-kHz PCM rendition. A bounded generator ring provides
## jitter tolerance while the retained PCM supplies mouth animation and timing.
const RATE:=24000
const INITIAL_FRAMES:=6000
const MAX_BYTES:=RATE*2*120
const Mixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
var pcm:=PackedByteArray()
var finished:=false
var received_at:=-1
var playback_at:=-1
var sent_frames:=0
var played_frames:=0
var capacity:=0
var underruns:=0
var drained_at:=-1
var last_packet_at:=-1
var initial_frames:=INITIAL_FRAMES
var max_packet_gap_ms:=0

func append(offset: int,chunk: PackedByteArray) -> bool:
	if finished or offset!=pcm.size() or chunk.is_empty() or chunk.size()%2!=0 or pcm.size()+chunk.size()>MAX_BYTES:return false
	var now:=Time.get_ticks_msec()
	if received_at<0:received_at=now
	if last_packet_at>=0:
		max_packet_gap_ms=maxi(max_packet_gap_ms,now-last_packet_at)
		if playback_at<0:initial_frames=clampi(maxi(INITIAL_FRAMES,int((max_packet_gap_ms+100)*RATE/1000.)),INITIAL_FRAMES,9600)
	last_packet_at=now
	pcm.append_array(chunk)
	return true

func ready() -> bool:return pcm.size()>=initial_frames*2 or (finished and not pcm.is_empty())

func create_stream() -> AudioStreamGenerator:
	var stream:=AudioStreamGenerator.new()
	stream.mix_rate=RATE
	stream.buffer_length=.4
	return stream

func pump(player: AudioStreamPlayer3D) -> bool:
	var playback:=player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback==null:return false
	var available_frames:=playback.get_frames_available()
	if capacity==0:capacity=available_frames
	played_frames=maxi(played_frames,sent_frames-maxi(0,capacity-available_frames))
	var count:=mini(available_frames,pcm.size()/2-sent_frames)
	if count>0:
		var bytes:=pcm.slice(sent_frames*2,(sent_frames+count)*2)
		var frames: PackedVector2Array
		var dsp:=Mixer.processor()
		if dsp!=null:frames=dsp.call("Pcm16ToFrames",bytes,false)
		else:
			frames.resize(count)
			for i in count:
				var sample:=float(bytes.decode_s16(i*2))/32768.
				frames[i]=Vector2(sample,sample)
		if frames.size()==count and playback.push_buffer(frames):
			sent_frames+=count
			if playback_at<0:playback_at=Time.get_ticks_msec()
	underruns=playback.get_skips()
	if finished and sent_frames==pcm.size()/2 and played_frames>=sent_frames:
		if drained_at<0:drained_at=Time.get_ticks_msec()
		return Time.get_ticks_msec()-drained_at>=maxi(40,int(AudioServer.get_output_latency()*1000.))
	drained_at=-1
	return false

func level() -> float:
	if playback_at<0 or played_frames>=sent_frames:return 0.
	var offset:=maxi(0,played_frames-240)*2
	var peak:=0.
	for at in range(offset,mini(pcm.size()-1,offset+960),16):
		peak=maxf(peak,absf(float(pcm.decode_s16(at))/32768.))
	return peak

func progress(estimated_seconds: float) -> float:
	var duration:=float(pcm.size())/(RATE*2) if finished else maxf(estimated_seconds,float(pcm.size())/(RATE*2))
	return clampf(float(played_frames)/RATE/maxf(.1,duration),0.,.9999)

func diagnostics() -> Dictionary:
	var audio_seconds:=float(pcm.size())/(RATE*2)
	var packet_span_ms:=last_packet_at-received_at if received_at>=0 and last_packet_at>received_at else -1
	return {"received_audio_seconds":audio_seconds,"first_to_last_packet_ms":packet_span_ms,"received_audio_seconds_per_second":audio_seconds*1000./packet_span_ms if packet_span_ms>0 else null,"received_bytes":pcm.size(),"frames_submitted":sent_frames,"estimated_frames_consumed":played_frames,"initial_buffer_target_ms":float(initial_frames)*1000./RATE,"first_packet_to_submission_ms":playback_at-received_at if playback_at>=0 and received_at>=0 else -1,"max_packet_gap_ms":max_packet_gap_ms,"generator_skip_count":underruns,"estimated_output_latency_ms":AudioServer.get_output_latency()*1000.,"generation_complete":finished}
