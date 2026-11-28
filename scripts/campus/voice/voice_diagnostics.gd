extends Window
var game: Node
var readout: TextEdit
var clock:=0.0
func configure(owner: Node) -> void:
 game=owner;title="Voice diagnostics";size=Vector2i(850,650);min_size=Vector2i(540,400)
 readout=TextEdit.new();readout.editable=false;readout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(readout)
 close_requested.connect(queue_free)
 popup_centered();_refresh()
func _process(delta: float) -> void:
 clock+=delta
 if clock>=.5:clock=0.0;_refresh()
func _refresh() -> void:
 if not is_instance_valid(game) or readout==null:return
 var microphone:=get_tree().root.get_node_or_null("MicrophoneCapture")
 var data:={"microphone":microphone.diagnostic if is_instance_valid(microphone) else {"active":false},"device":AudioServer.input_device,"output":AudioServer.output_device,
  "echo_management":"Native acoustic echo cancellation is unavailable. Speaker protection gates open-mic NPC recognition during playback; headphones or push-to-talk allow interruption.",
  "speech_model":game.host_openai.tts_model,"recognition_model":game.host_openai.stt_model,
  "lifecycle":preload("res://scripts/campus/ai/openai_models.gd").lifecycle(game.host_openai.tts_model)}
 if is_instance_valid(game.faculty):
  data.conversation=game.faculty.natural_voice.diagnostic
  data.synthesis=game.faculty.speech_synth.diagnostics()
  data.playback={"channels":game.faculty.speech_player.active.keys(),"queued":game.faculty.speech_player.queued.keys(),"suspended":game.faculty.speech_player.suspended.keys(),"pending_network":game.faculty.pending_voice.size()}
  var character:=str(game.faculty.natural_voice.current.get("id",""))
  if not character.is_empty():
   var person: Dictionary=preload("res://scripts/campus/academics/class_character_profile.gd").teacher(character) if preload("res://scripts/campus/academics/faculty_roster.gd").has(character) else preload("res://scripts/campus/academics/classroom_students.gd").profile_for(character)
   if not person.is_empty():
    data.voice=preload("res://scripts/campus/academics/teacher_voice_profiles.gd").identity(person)
    data.emotion=game.faculty.character_mind.context(person,Time.get_ticks_msec())
 readout.text=JSON.stringify(data,"  ").left(16000)
