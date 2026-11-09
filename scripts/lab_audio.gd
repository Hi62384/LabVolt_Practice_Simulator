extends Node
var bank := {}
var voices: Array[AudioStreamPlayer] = []
var cursor := 0
func _ready() -> void:
	for kind in ["step","plug","unplug","pickup","return","drawer","switch","power","voltage","trip","ui","roll","paper","mark","bell","trash"]:
		bank[kind]=make_sound(kind)
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)

func play(kind: String) -> void:
	if DisplayServer.get_name()=="headless" or voices.is_empty():
		return
	var voice := voices[cursor%voices.size()]
	cursor+=1
	voice.stream=bank.get(kind,bank.ui)
	voice.bus = "Interface" if kind == "ui" else "Effects"
	voice.volume_db=-22 if kind!="step" else -30
	voice.pitch_scale=randf_range(.94,1.06)
	voice.play()

func make_sound(kind: String) -> AudioStreamWAV:
	var duration: float = {"step":.14,"plug":.10,"unplug":.15,"pickup":.28,"return":.22,"drawer":.48,"switch":.07,"power":.20,"voltage":.035,"trip":.45,"ui":.035,"roll":1.0,"paper":.25,"mark":.3,"bell":.8,"trash":.35}[kind]
	var samples := PackedByteArray()
	samples.resize(int(duration*22050)*2)
	var rng := RandomNumberGenerator.new()
	rng.seed=hash(kind)
	var low := 0.0
	for i in range(samples.size()/2):
		var t := float(i)/22050
		var n := rng.randf_range(-1,1)
		low=lerpf(low,n,.12)
		var env := exp(-t/(duration*.22))
		var value := 0.0
		match kind:
			"roll": value=low*.5+sin(TAU*47*t)*.025
			"paper","trash": value=(n*.25+low*.7)*sin(PI*t/duration)*(0.7+0.3*sin(TAU*23*t))
			"mark": value=(sin(TAU*880*t)+.4*sin(TAU*1320*t))*env*.4
			"bell": value=(sin(TAU*660*t)+.5*sin(TAU*990*t))*exp(-t*4)*.4
			"step": value=(low*.8+sin(TAU*78*t)*.35)*env
			"plug": value=(n*.5+sin(TAU*1400*t)*.35)*env + (n*.3*exp(-(t-.045)*130) if t>.045 else 0)
			"unplug": value=(low*.7+n*.22)*sin(PI*t/duration)
			"pickup","return": value=n*.45*(.4+.6*sin(TAU*31*t))*sin(PI*t/duration)
			"drawer": value=low*.9*sin(PI*t/duration)+(sin(TAU*100*t)*exp(-(t-.40)*70)*.6 if t>.40 else 0)
			"switch": value=(n*.65+sin(TAU*2100*t)*.2)*env
			"power": value=(low*.8+sin(TAU*140*t)*.6)*env
			"trip": value=sin(TAU*620*t)*.4 if fmod(t,.15)<.075 else 0
			_: value=n*.35*env
		samples.encode_s16(i*2,int(clampf(value,-1,1)*24000))
	var audio := AudioStreamWAV.new()
	audio.format=AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate=22050
	audio.data=samples
	if kind=="roll":
		audio.loop_mode=AudioStreamWAV.LOOP_FORWARD
		audio.loop_end=22050
	return audio
