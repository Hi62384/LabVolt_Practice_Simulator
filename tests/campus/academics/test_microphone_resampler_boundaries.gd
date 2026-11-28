extends SceneTree
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for rate: int in [8000,11025,16000,22050,44100,48000,96000]:
		var frames:=PackedVector2Array()
		for index in int(float(rate)*.12):
			var value:=.18*sin(float(index)*TAU*311./float(rate))+.11*sin(float(index)*TAU*1777./float(rate))
			frames.append(Vector2(value,value))
		var whole=Processor.new()
		var single: Dictionary=whole.Process(frames,float(rate),1.,false)
		var streamed=Processor.new()
		var fragmented:=PackedByteArray()
		var offset:=0
		var cycle:=0
		var sizes: Array[int]=[13,61,127,257,512]
		while offset<frames.size():
			var count:=mini(sizes[cycle%sizes.size()],frames.size()-offset)
			var part: Dictionary=streamed.Process(frames.slice(offset,offset+count),float(rate),1.,false)
			fragmented.append_array(part.get("pcm",PackedByteArray()))
			offset+=count;cycle+=1
		# Final interpolation can wait for one future sample. Compare all common
		# samples except the tail, not an implementation-specific flush policy.
		var compared:=mini(single.pcm.size(),fragmented.size())/2-2
		var max_difference:=0
		for index in maxi(0,compared):max_difference=maxi(max_difference,absi(int(single.pcm.decode_s16(index*2))-int(fragmented.decode_s16(index*2))))
		if max_difference>2:
			var message:="%d Hz fragmented capture differs from one continuous stream by %d PCM units"%[rate,max_difference]
			failures.append(message);push_error(message)
	print("MICROPHONE_RESAMPLER_BOUNDARIES ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
