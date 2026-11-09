extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var root_control := Control.new();root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(root_control)
 var scroll := ScrollContainer.new();root_control.add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var panel=load("res://scripts/firmware_backends/native_ide.gd").new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(panel)
 panel.build("uno",{"schema":1,"board":"uno","format":"intel_hex","image":FileAccess.get_file_as_string("res://assets/workers/firmware/uno-toggle.hex")},{"Blink.ino":"void setup() { pinMode(13, OUTPUT); }\nvoid loop() { digitalWrite(13, HIGH); delay(10); digitalWrite(13, LOW); delay(10); }"})
 for i in 5:await process_frame
 panel.validate_program();panel.set_snapshot({"status":"Not deployed","powered":false})
 await process_frame
 var output := OS.get_environment("LABVOLT_NATIVE_CAPTURE")
 if not output.is_empty():root.get_texture().get_image().save_png(output)
 print("PASS native programming screen rendered at ",root.size)
 panel.queue_free();root_control.queue_free();await process_frame;quit()
