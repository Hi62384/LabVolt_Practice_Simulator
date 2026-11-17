extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
const Audio=preload("res://scripts/circuit_audio.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var audio=Audio.new();root.add_child(audio)
 var board=Board.empty();board.parts=[{"id":"sound","type":"buzzer","a":"A1","b":"F1"}]
 audio.update_circuit(board,{"i":{"board/sound":.005}})
 if not audio.voices.has("board/sound") or audio.voice_kinds["board/sound"]!="buzzer" or float(audio.levels["board/sound"])<=0:
  push_error("Buzzer was not created");quit(1);return
 audio.update_circuit(board,{"i":{"board/sound":0.0}})
 if float(audio.levels["board/sound"])!=0.0:push_error("Cached buzzer did not update its level");quit(1);return
 board.parts[0].type="speaker"
 audio.update_circuit(board,{"i":{"board/sound":.005},"audio":{}})
 if audio.voice_kinds.get("board/sound")!="speaker":push_error("Voice did not follow changed component type");quit(1);return
 board.parts.clear();audio.update_circuit(board,{})
 if not audio.voices.is_empty():push_error("Removed audio component still has a voice");quit(1);return
 print("PASS: audio layout cache preserves levels, type replacement and removal");quit()
