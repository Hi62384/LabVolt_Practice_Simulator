extends SceneTree
const VoiceChat=preload("res://scripts/campus/voice/voice_chat.gd")
const Router=preload("res://scripts/campus/voice/npc_voice_router.gd")
func _initialize() -> void:
	assert(VoiceChat.meter_fill(0.)==0.)
	assert(VoiceChat.meter_fill(.005)<VoiceChat.meter_fill(.04))
	assert(VoiceChat.meter_fill(.04)<VoiceChat.meter_fill(.2))
	assert(VoiceChat.meter_fill(1.)==1.)
	assert(not Router.usable_input({"speech":false,"rms":0.,"peak":.5}))
	assert(Router.usable_input({"speech":false,"rms":.005,"peak":.02}))
	assert(Router.usable_input({"speech":true}))
	print("VOICE_METER_INPUT PASS")
	quit(0)
