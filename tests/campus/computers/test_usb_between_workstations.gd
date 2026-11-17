extends SceneTree

const Power=preload("res://scripts/campus/computers/device_power.gd")
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")

func _initialize() -> void:
	var owner: String="a".repeat(48)
	var stranger: String="b".repeat(48)
	var id: String="c".repeat(32)
	var blank=Drive.new(8*1024*1024)
	var ok: bool=Archive.save(owner,id,"Course files",8,blank)==OK
	var first=Power.new()
	ok=ok and first.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and first.turn_on(100)
	ok=ok and first.usb.drive.make_folder("DGS266")
	ok=ok and first.usb.drive.write_file("DGS266/notes.txt","Saved in the commons".to_utf8_buffer())
	ok=ok and first.save_local_usb()==OK
	ok=ok and first.turn_off()
	ok=ok and first.remove_local_usb().get("ok",false)
	var second=Power.new()
	ok=ok and second.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and second.turn_on(200)
	ok=ok and second.usb.drive.entries.get("DGS266/notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="Saved in the commons"
	ok=ok and second.turn_off() and second.remove_local_usb().get("ok",false)
	var rejoined=Power.new()
	ok=ok and rejoined.insert_local_usb(owner,id,8).get("ok",false)
	ok=ok and rejoined.usb.drive.entries.get("DGS266/notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="Saved in the commons"
	ok=ok and Archive.load(stranger,id,8).has("error")
	print("USB_BETWEEN_WORKSTATIONS ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
