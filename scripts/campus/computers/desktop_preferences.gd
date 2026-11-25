extends RefCounted

const PATH := ".campus-os.json"
const APPS := ["Files","Text editor","Code editor","Calculator","Browser","Terminal","Settings","Recycle Bin"]
const WALLPAPERS := ["Campus waves","Dusk ridges","Polar night","Circuit grid"]
const MAX_IMAGE_BYTES := 36 * 1024

static func clean(value: Variant) -> Dictionary:
	if not value is Dictionary:return {}
	var style: Variant=value.get("style",0)
	var wallpaper: Variant=value.get("wallpaper",0)
	var volume: Variant=value.get("volume",35)
	var pins: Variant=value.get("pinned",[])
	var image: Variant=value.get("image","")
	if not (style is int or style is float) or not (wallpaper is int or wallpaper is float) or not (volume is int or volume is float) or not pins is Array or pins.size()>APPS.size() or not image is String or image.length()>MAX_IMAGE_BYTES*2:return {}
	var filtered:=Array()
	for pin in pins:
		if pin in APPS and pin not in filtered:filtered.append(pin)
	if not image.is_empty() and not valid_image(Marshalls.base64_to_raw(image)):return {}
	return {"style":clampi(int(style),0,2),"wallpaper":clampi(int(wallpaper),0,WALLPAPERS.size()),"volume":clampi(int(volume),0,100),"pinned":filtered,"image":image}

# Validate JPEG marker dimensions before decoding data from a mounted drive.
static func valid_image(bytes: PackedByteArray) -> bool:
	if bytes.size()<12 or bytes.size()>MAX_IMAGE_BYTES or bytes[0]!=255 or bytes[1]!=216:return false
	var pos:=2
	while pos+8<bytes.size() and bytes[pos]==255:
		var marker:=bytes[pos+1]
		var length:=bytes[pos+2]*256+bytes[pos+3]
		if length<2 or pos+length+2>bytes.size():return false
		if marker in [192,193,194]:
			var width:=bytes[pos+7]*256+bytes[pos+8]
			var height:=bytes[pos+5]*256+bytes[pos+6]
			return width>=1 and width<=1024 and height>=1 and height<=768
		pos+=length+2
	return false

static func read(drive: RefCounted) -> Dictionary:
	var bytes: PackedByteArray=drive.entries.get(PATH,{}).get("data",PackedByteArray())
	if bytes.is_empty() or bytes.size()>MAX_IMAGE_BYTES*2:return {}
	return clean(JSON.parse_string(bytes.get_string_from_utf8()))
