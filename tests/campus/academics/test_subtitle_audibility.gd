extends SceneTree
const Speech=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Mixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
func _initialize() -> void:
	assert(Mixer.distance_db(40.,4.,18.,0.)==-INF)
	assert(Mixer.distance_db(2.,4.,18.,0.)>Mixer.distance_db(12.,4.,18.,0.))
	assert(Mixer.distance_db(12.,8.,40.,0.)>Mixer.distance_db(12.,4.,18.,0.))
	assert(Speech.choose_subtitle({"teacher":-80.,"student":-23.},"")=="student")
	assert(Speech.choose_subtitle({"teacher":-20.,"student":-21.},"student")=="student")
	assert(Speech.choose_subtitle({"teacher":-12.,"student":-21.},"student")=="teacher")
	assert(Speech.choose_subtitle({"teacher":-70.,"student":-23.},"teacher")=="student")
	assert(Speech.choose_subtitle({"teacher":-70.,"student":-80.},"teacher")=="")
	print("SUBTITLE_AUDIBILITY PASS")
	quit(0)
