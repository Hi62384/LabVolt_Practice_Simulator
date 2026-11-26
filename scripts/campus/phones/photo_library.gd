extends RefCounted
## Each phone owns a local, quota-limited collection of JPEG images. This
## module only accepts in-game Image data and never accesses an OS camera.
const MAX_PHOTOS:=512
const MAX_PHOTO_BYTES:=8*1024*1024

static func _valid_id(value: String,length: int) -> bool:
	return value.length()==length and value==value.to_lower() and value.is_valid_hex_number()

static func directory(owner: String,phone: String) -> String:
	if not _valid_id(owner,48) or not _valid_id(phone,32):return ""
	return "user://phone_photos_%s_%s"%[owner,phone]

static func list(owner: String,phone: String) -> Dictionary:
	var base:=directory(owner,phone)
	if base.is_empty():return {"error":"Invalid phone identity"}
	if not DirAccess.dir_exists_absolute(base):return {"photos":[],"bytes":0}
	var dir:=DirAccess.open(base)
	if dir==null:return {"error":"Cannot open photos"}
	var photos:=[];var used:=0
	dir.list_dir_begin()
	var name:=dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".jpg") and _valid_id(name.trim_suffix(".jpg"),32):
			var file:=FileAccess.open(base+"/"+name,FileAccess.READ)
			if file==null:dir.list_dir_end();return {"error":"Cannot read photo"}
			var size:=file.get_length()
			if size<=0 or size>MAX_PHOTO_BYTES:dir.list_dir_end();return {"error":"Invalid photo data"}
			used+=size;photos.append({"id":name.trim_suffix(".jpg"),"bytes":size,"modified":FileAccess.get_modified_time(base+"/"+name)})
			if photos.size()>MAX_PHOTOS:dir.list_dir_end();return {"error":"Too many photos"}
		name=dir.get_next()
	dir.list_dir_end()
	photos.sort_custom(func(a,b):return a.id>b.id if a.modified==b.modified else a.modified>b.modified)
	return {"photos":photos,"bytes":used}

static func capture(owner: String,phone: String,image: Image,quota: int,jpeg_quality := .88) -> Dictionary:
	var base:=directory(owner,phone)
	if base.is_empty() or image==null or image.is_empty() or quota<=0:return {"error":"Invalid photo"}
	var state:=list(owner,phone)
	if state.has("error"):return state
	if state.photos.size()>=MAX_PHOTOS:return {"error":"Photo limit reached"}
	var copy:=image.duplicate() as Image
	if copy.get_width()>1920 or copy.get_height()>1080:
		var scale:=minf(1920.0/copy.get_width(),1080.0/copy.get_height())
		copy.resize(maxi(1,roundi(copy.get_width()*scale)),maxi(1,roundi(copy.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	copy.convert(Image.FORMAT_RGB8)
	var bytes:=copy.save_jpg_to_buffer(clampf(jpeg_quality,0.0,1.0))
	if bytes.is_empty() or bytes.size()>MAX_PHOTO_BYTES:return {"error":"Photo could not be encoded"}
	if int(state.bytes)+bytes.size()>quota:return {"error":"Phone storage is full"}
	var error:=DirAccess.make_dir_recursive_absolute(base)
	if error!=OK:return {"error":"Cannot create photo storage"}
	var id:=Crypto.new().generate_random_bytes(16).hex_encode()
	var target:=base+"/"+id+".jpg"
	if FileAccess.file_exists(target):return {"error":"Photo identity conflict"}
	var file:=FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null:return {"error":"Cannot save photo"}
	file.store_buffer(bytes);file.flush();error=file.get_error();file.close()
	if error!=OK or DirAccess.rename_absolute(target+".tmp",target)!=OK:return {"error":"Cannot save photo"}
	return {"id":id,"bytes":bytes.size()}

static func load_photo(owner: String,phone: String,id: String) -> Dictionary:
	var base:=directory(owner,phone)
	if base.is_empty() or not _valid_id(id,32):return {"error":"Invalid photo identity"}
	var file:=FileAccess.open(base+"/"+id+".jpg",FileAccess.READ)
	if file==null:return {"error":"Photo not found"}
	if file.get_length()<=0 or file.get_length()>MAX_PHOTO_BYTES:
		file.close()
		return {"error":"Invalid photo data"}
	var bytes:=file.get_buffer(file.get_length())
	file.close()
	var image:=Image.new()
	if image.load_jpg_from_buffer(bytes)!=OK or image.is_empty():return {"error":"Photo is damaged"}
	return {"image":image}

static func delete_photo(owner: String,phone: String,id: String) -> bool:
	var base:=directory(owner,phone)
	if base.is_empty() or not _valid_id(id,32):return false
	var target:=base+"/"+id+".jpg"
	return FileAccess.file_exists(target) and DirAccess.remove_absolute(target)==OK
