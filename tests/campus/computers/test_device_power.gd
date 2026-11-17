extends SceneTree
func _initialize() -> void:
	var device=preload("res://scripts/campus/computers/device_power.gd").new()
	var failures: Array[String]=[]
	if device.touch(0):failures.append("Unpowered device accepted activity")
	if not device.turn_on(1000):failures.append("Power on failed")
	device.drive.write_file("notes.txt","hello".to_utf8_buffer())
	if device.update(600999):failures.append("Device timed out early")
	device.touch(600999)
	if device.update(1200998):failures.append("Activity did not reset timeout")
	if not device.update(1200999):failures.append("Idle timeout failed")
	if device.powered or not device.drive.entries.is_empty():failures.append("Power off did not clear session")
	if not device.turn_on(1201000):failures.append("Restart failed")
	device.drive.write_file("again.txt",PackedByteArray())
	if not device.turn_off() or not device.drive.entries.is_empty():failures.append("Manual power off did not clear session")
	for failure in failures:push_error(failure)
	print("DEVICE_POWER ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
