extends AudioStreamPlayer
## A quiet, seamless air bed on the existing Master bus.
var _target_volume := -52.0
var _target_pitch := 0.8

func _ready() -> void:
	bus = "Ambience"
	var rate := 12000
	var count := 12000
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = rate
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = count
	var samples := PackedByteArray()
	samples.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 709
	# Whole cycles with fixed phases make the filtered air loop seamless.
	var phases := PackedFloat32Array()
	var cycles := [71, 93, 127, 193, 267, 351, 487, 637, 977, 1231, 1501, 1987]
	for _cycle in cycles:
		phases.append(random.randf_range(0.0, TAU))
	for i in count:
		var angle := TAU * float(i) / count
		var sample := 0.0
		for band in cycles.size():
			sample += sin(angle * cycles[band] + phases[band])
		samples.encode_s16(i * 2, int(sample * 1100.0))
	wave.data = samples
	stream = wave
	volume_db = -60.0
	play()

func set_outdoors(outdoors: bool) -> void:
	_target_volume = -48.0 if outdoors else -53.0
	_target_pitch = 1.15 if outdoors else 0.8

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-2.6 * delta)
	volume_db = lerpf(volume_db, _target_volume, blend)
	pitch_scale = lerpf(pitch_scale, _target_pitch, blend)
