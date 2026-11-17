extends RefCounted
## Per-device power lifecycle for public workstations and portable computers.
## Time comes from the authoritative monotonic clock, in milliseconds.
const IDLE_TIMEOUT_MS := 10 * 60 * 1000
var powered := false
var last_activity_ms := 0
var drive = preload("res://scripts/campus/computers/device_filesystem.gd").new()
var usb: Dictionary = {}
const UsbArchive=preload("res://scripts/campus/computers/usb_archive.gd")

func turn_on(now_ms: int) -> bool:
	if powered: return false
	powered = true
	last_activity_ms = now_ms
	return true

func touch(now_ms: int) -> bool:
	if not powered: return false
	last_activity_ms = maxi(last_activity_ms, now_ms)
	return true

func turn_off() -> bool:
	if not powered: return false
	powered = false
	if not usb.is_empty() and drive==usb.drive:
		drive=preload("res://scripts/campus/computers/device_filesystem.gd").new()
	else:drive.clear()
	return true

func update(now_ms: int) -> bool:
	if powered and now_ms - last_activity_ms >= IDLE_TIMEOUT_MS:
		turn_off()
		return true
	return false

## The workstation owns the connection state; the archive is always read and
## written by the client's storage layer. Missing or damaged archives are not
## replaced with empty drives.
func insert_local_usb(owner: String, id: String, capacity_mb: int) -> Dictionary:
	if not usb.is_empty():return {"error":"A USB drive is already connected"}
	var loaded: Dictionary=UsbArchive.load(owner,id,capacity_mb)
	if loaded.has("error"):return loaded
	usb={"owner":owner,"id":id,"capacity_mb":capacity_mb,"name":loaded.name,"drive":loaded.drive}
	return {"ok":true}

func save_local_usb() -> Error:
	if usb.is_empty():return ERR_UNCONFIGURED
	return UsbArchive.save(usb.owner,usb.id,usb.name,usb.capacity_mb,usb.drive)

func remove_local_usb() -> Dictionary:
	if powered:return {"error":"Turn off the computer before removing the USB drive"}
	if usb.is_empty():return {"error":"No USB drive connected"}
	var error:=save_local_usb()
	if error!=OK:return {"error":"USB data could not be saved","code":error}
	var result:={"ok":true,"owner":usb.owner,"id":usb.id,"name":usb.name,"capacity_mb":usb.capacity_mb}
	usb={}
	return result
