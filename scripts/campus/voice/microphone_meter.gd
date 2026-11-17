extends VBoxContainer
## Explicit opt-in meter; captured samples are neither saved nor sent.
var toggle: Button
var meter: ProgressBar
var note: Label
var player: AudioStreamPlayer
var capture: AudioEffectCapture
var bus_name: String=""
var running:=false
var sensitivity: Callable

func build(sensitivity_getter: Callable=Callable()) -> void:
 sensitivity=sensitivity_getter
 add_theme_constant_override("separation",6)
 var row:=HBoxContainer.new();add_child(row)
 toggle=Button.new();toggle.text="Start microphone test";toggle.pressed.connect(_toggle);row.add_child(toggle)
 meter=ProgressBar.new();meter.max_value=.25;meter.show_percentage=false;meter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;meter.custom_minimum_size.x=160;row.add_child(meter)
 note=Label.new();note.text="The microphone is off. The test runs only when started and does not save or send audio.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
 set_process(false)

func _toggle() -> void:
 if running:_stop();return
 bus_name="TeacherMicTest_%d"%get_instance_id()
 AudioServer.add_bus();var bus:=AudioServer.bus_count-1
 AudioServer.set_bus_name(bus,bus_name);AudioServer.set_bus_send(bus,"Master");AudioServer.set_bus_volume_db(bus,-80.0)
 capture=AudioEffectCapture.new();capture.buffer_length=.3;AudioServer.add_bus_effect(bus,capture)
 player=AudioStreamPlayer.new();player.bus=bus_name;player.stream=AudioStreamMicrophone.new();add_child(player)
 running=true;toggle.text="Stop microphone test";note.text="Microphone test is on. Speak normally to see the input level.";player.play();set_process(true)

func _process(_delta: float) -> void:
 if not running or capture==null:return
 var count:=mini(capture.get_frames_available(),int(AudioServer.get_mix_rate()*.1))
 if count<=0:return
 var input_level:=level(capture.get_buffer(count))
 meter.value=input_level
 var current: float=float(sensitivity.call()) if sensitivity.is_valid() else 1.0
 note.text="Input is above the teacher-hearing threshold." if above_threshold(input_level,current) else "Input is below the teacher-hearing threshold."

static func above_threshold(input_level: float,sensitivity_value: float) -> bool:
 if not is_finite(input_level) or not is_finite(sensitivity_value):return false
 return input_level*clampf(sensitivity_value,.5,2.0)>=preload("res://scripts/campus/voice/teacher_sound_activity.gd").QUIET_RMS

static func level(frames: PackedVector2Array) -> float:
 if frames.is_empty():return 0.0
 var sum:=0.0
 for frame in frames:
  var sample: float=(frame.x+frame.y)*.5
  if is_finite(sample):sum+=sample*sample
 return sqrt(sum/frames.size())

func _stop() -> void:
 set_process(false);running=false
 if is_instance_valid(player):player.stop();player.queue_free()
 player=null;capture=null
 if not bus_name.is_empty():
  var index:=AudioServer.get_bus_index(bus_name)
  if index>0:AudioServer.remove_bus(index)
 bus_name=""
 if is_instance_valid(toggle):toggle.text="Start microphone test"
 if is_instance_valid(meter):meter.value=0
 if is_instance_valid(note):note.text="The microphone is off. The test runs only when started and does not save or send audio."

func _exit_tree() -> void:_stop()
