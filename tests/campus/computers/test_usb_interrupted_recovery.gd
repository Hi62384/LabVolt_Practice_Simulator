extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void:
	var profile=Profile.new();profile.open("usb-interruption-fixture")
	profile.data.dollars=1000;profile.buy_usb(8)
	var id: String=profile.data.dorm.usb_drives.keys()[0]
	var owner: String=profile.data.dorm.owner
	var drive=Drive.new(8*1024*1024)
	drive.write_file("notes.txt","saved before interruption".to_utf8_buffer())
	var ok: bool=Archive.save(owner,id,"USB drive",8,drive)==OK
	if not ok:push_error("USB archive could not be saved before interruption")
	profile.data.dorm.carry_items.erase("usb:"+id)
	profile.data.dorm.usb_drives[id].location="connected"
	var profile_saved: bool=profile.save()==OK
	if not profile_saved:push_error("Connected USB profile could not be saved")
	ok=ok and profile_saved
	var reopened=Profile.new();reopened.open("usb-interruption-fixture")
	var recovered: bool=reopened.data.dorm.usb_drives[id].location=="lost" and "usb:"+id not in reopened.data.dorm.carry_items
	if not recovered:push_error("Connected USB did not move to lost and found")
	ok=ok and recovered
	var loaded: Dictionary=Archive.load(owner,id,8)
	var contents_preserved: bool=not loaded.has("error") and loaded.drive.entries["notes.txt"].data.get_string_from_utf8()=="saved before interruption"
	if not contents_preserved:push_error("USB archive contents were not preserved")
	ok=ok and contents_preserved
	# Never fabricate an empty replacement for an absent archive.
	var missing_profile=Profile.new();missing_profile.open("usb-missing-archive-fixture")
	missing_profile.data.dollars=1000;missing_profile.buy_usb(8)
	var missing_id: String=missing_profile.data.dorm.usb_drives.keys()[0]
	# Purchase creates an empty archive; remove only this isolated fixture's copy
	# to simulate a lost file rather than a normal interrupted connection.
	var missing_path: String=Archive.path(str(missing_profile.data.dorm.owner),missing_id)
	DirAccess.remove_absolute(missing_path)
	DirAccess.remove_absolute(missing_path+".bak")
	missing_profile.data.dorm.carry_items.erase("usb:"+missing_id)
	missing_profile.data.dorm.usb_drives[missing_id].location="connected"
	var missing_saved: bool=missing_profile.save()==OK
	if not missing_saved:push_error("Missing archive fixture profile could not be saved")
	ok=ok and missing_saved
	var missing_reopened=Profile.new();missing_reopened.open("usb-missing-archive-fixture")
	var missing_retained: bool=missing_reopened.data.dorm.usb_drives[missing_id].location=="connected"
	if not missing_retained:push_error("Missing USB archive incorrectly became lost")
	ok=ok and missing_retained
	print("USB_INTERRUPTED_RECOVERY ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
