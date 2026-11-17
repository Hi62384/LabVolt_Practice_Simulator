extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void:
	var failures: Array[String]=[]
	var owner:="a".repeat(48);var first:="1".repeat(32);var second:="2".repeat(32)
	var drive=Drive.new(8*1024*1024)
	drive.make_folder("lab");drive.write_file("lab/data.bin",PackedByteArray([0,255,1,42]))
	if Archive.save(owner,first,"Lab notes",8,drive)!=OK:failures.append("First drive save failed")
	var other=Drive.new(32*1024*1024);other.write_file("other.txt","other".to_utf8_buffer())
	if Archive.save(owner,second,"Other",32,other)!=OK:failures.append("Second drive save failed")
	var loaded:=Archive.load(owner,first,8)
	if loaded.get("name","")!="Lab notes" or loaded.get("drive")==null:failures.append("First drive load failed")
	elif loaded.drive.entries.get("lab/data.bin",{}).get("data",PackedByteArray())!=PackedByteArray([0,255,1,42]):failures.append("Binary content changed")
	if Archive.load(owner,first,32).get("error","").is_empty():failures.append("Capacity mismatch accepted")
	if Archive.load("b".repeat(48),first,8).get("error","").is_empty():failures.append("Different owner accessed drive")
	if Archive.save(owner,first," ",8,drive)==OK:failures.append("Empty drive name accepted")
	if Archive.save(owner,first,"Bad\u007fName",8,drive)==OK:failures.append("Control character in drive name accepted")
	if Archive.save(owner,first,"Lab notes",8,null)==OK:failures.append("Missing drive accepted")
	if Archive.save(owner,"../escape","Bad",8,drive)==OK:failures.append("Invalid drive id accepted")
	drive.entries["missing/file"]={"type":"file","data":PackedByteArray()}
	if Archive.save(owner,first,"Lab notes",8,drive)==OK:failures.append("Orphaned file accepted")
	if Archive.load(owner,first,8).get("name","")!="Lab notes":failures.append("Rejected save damaged existing data")
	var recovery_id: String="3".repeat(32)
	var earlier=Drive.new(8*1024*1024);earlier.write_file("notes.txt","saved copy".to_utf8_buffer())
	var later=Drive.new(8*1024*1024);later.write_file("notes.txt","new copy".to_utf8_buffer())
	if Archive.save(owner,recovery_id,"Recovery",8,earlier)!=OK or Archive.save(owner,recovery_id,"Recovery",8,later)!=OK:failures.append("Recovery fixture save failed")
	else:
		var damaged:=FileAccess.open(Archive.path(owner,recovery_id),FileAccess.WRITE)
		if damaged==null:failures.append("Recovery fixture could not damage main archive")
		else:
			damaged.store_string("damaged archive");damaged.close()
			var recovered: Dictionary=Archive.load(owner,recovery_id,8)
			if not recovered.get("recovered",false) or recovered.get("drive")==null:failures.append("Valid backup was not recovered")
			elif recovered.drive.entries.get("notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="new copy":failures.append("Backup did not contain the latest valid save")
			if not Archive.load(owner,recovery_id,32).has("error"):failures.append("Backup bypassed capacity validation")
			if recovered.get("drive")!=null:
				recovered.drive.write_file("notes.txt","after recovery".to_utf8_buffer())
				if Archive.save(owner,recovery_id,"Recovery",8,recovered.drive)!=OK:failures.append("Save after recovery failed")
				else:
					var damaged_again:=FileAccess.open(Archive.path(owner,recovery_id),FileAccess.WRITE)
					if damaged_again==null:failures.append("Could not damage recovered main archive")
					else:
						damaged_again.store_string("damaged again");damaged_again.close()
						var second_recovery: Dictionary=Archive.load(owner,recovery_id,8)
						if not second_recovery.get("recovered",false) or second_recovery.get("drive")==null:failures.append("Recovery save overwrote valid backup")
						elif second_recovery.drive.entries.get("notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="after recovery":failures.append("Recovery save lost new content")
	var missing_id: String="4".repeat(32)
	if Archive.save(owner,missing_id,"Missing main",8,earlier)!=OK:failures.append("Missing-main fixture save failed")
	elif DirAccess.remove_absolute(Archive.path(owner,missing_id))!=OK:failures.append("Could not remove missing-main fixture")
	else:
		var missing_recovery: Dictionary=Archive.load(owner,missing_id,8)
		if not missing_recovery.get("recovered",false) or missing_recovery.get("drive")==null:failures.append("Missing main did not recover from backup")
	var corrupt_id: String="5".repeat(32)
	if Archive.save(owner,corrupt_id,"Corrupt pair",8,earlier)!=OK:failures.append("Corrupt-pair fixture save failed")
	else:
		for suffix in ["",".bak"]:
			var corrupt:=FileAccess.open(Archive.path(owner,corrupt_id)+suffix,FileAccess.WRITE)
			if corrupt==null:failures.append("Could not corrupt archive fixture")
			else:corrupt.store_string("invalid");corrupt.close()
		if not Archive.load(owner,corrupt_id,8).has("error"):failures.append("Corrupt main and backup were accepted")
	for message in failures:push_error(message)
	print("USB_ARCHIVE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
