extends SceneTree
const Power=preload("res://scripts/campus/computers/device_power.gd")
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void:
	var owner:="a".repeat(48);var id:="b".repeat(32)
	var initial=Drive.new(8*1024*1024)
	var ok: bool=Archive.save(owner,id,"Class notes",8,initial)==OK
	var device=Power.new()
	ok=ok and device.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and not device.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and device.turn_on(10)
	ok=ok and device.usb.drive.make_folder("Labs")
	ok=ok and device.usb.drive.write_file("Labs/notes.txt","Hello lab".to_utf8_buffer())
	ok=ok and device.save_local_usb()==OK
	ok=ok and device.remove_local_usb().has("error")
	ok=ok and device.turn_off()
	var removed: Dictionary=device.remove_local_usb()
	ok=ok and removed.get("id","")==id and removed.get("name","")=="Class notes"
	ok=ok and device.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and device.usb.drive.entries.get("Labs/notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="Hello lab"
	var missing=Power.new()
	ok=ok and missing.insert_local_usb(owner,"c".repeat(32),8).has("error")
	print("USB_WORKSTATION ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
