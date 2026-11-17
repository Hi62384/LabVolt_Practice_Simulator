extends SceneTree
func _initialize() -> void:
 var acceptance=preload("res://scripts/firmware_toolchain/acceptance.gd")
 if not acceptance.verified():
  printerr("FIRMWARE_RECEIPT FAIL")
  quit(1)
  return
 print("FIRMWARE_RECEIPT PASS")
 quit()
