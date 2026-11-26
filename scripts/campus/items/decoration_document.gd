extends RefCounted

const LAYERS := 6
const PIXELS := 128
const MAX_IMAGE := 36*1024
const MAX_DOCUMENT := 84*1024
const MAX_IMPORT := 6*1024*1024
const OPTIONAL := ["width","height","lock_aspect","mesh_paint","projection"]
const TYPES := ["paint","image","text","shape"]
const SHAPES := ["Panel","Button","Stud","Trim"]
const BLENDS := ["Normal","Add","Multiply"]
static var validated_images := {}

static func layer(kind: String) -> Dictionary:
	return {"name":kind.capitalize(),"kind":kind,"visible":true,"locked":false,"data":"",
		"x":.5,"y":.5,"size":1.0 if kind=="paint" else .60,"angle":0.0,"opacity":1.0,
		"color":"ffffff" if kind in ["paint","image"] else "7fdfcb","metallic":0.0,"roughness":.55,"glow":0.0,"glow_color":"ffffff","blend":0,
		"crop_left":0.0,"crop_right":0.0,"crop_top":0.0,"crop_bottom":0.0,
		"width":1.0,"height":1.0,"lock_aspect":true}

static func clean(value: Variant) -> Variant:
	if not value is Array or value.size()>LAYERS:return null
	var design := []
	var encoded_size := 0
	for raw in value:
		if not raw is Dictionary or raw.get("kind","") not in TYPES:return null
		var item:=layer(raw.kind)
		for key in raw:
			if not item.has(key) and key not in OPTIONAL:return null
		for key in item:
			if key not in OPTIONAL and not raw.has(key):return null
		for key in ["width","height"]:
			var dimension: Variant=raw.get(key,1.0)
			if not (dimension is int or dimension is float) or not is_finite(dimension) or dimension<.25 or dimension>4.0:return null
		if not raw.get("lock_aspect",true) is bool:return null
		for key in ["name","data","color","glow_color"]:
			if not raw.get(key) is String:return null
		if raw.name.strip_edges().is_empty() or raw.name.length()>28:return null
		if raw.color.length()!=6 or not Color.html_is_valid(raw.color) or raw.glow_color.length()!=6 or not Color.html_is_valid(raw.glow_color):return null
		if not raw.get("visible") is bool or not raw.get("locked") is bool:return null
		for key in ["x","y","size","angle","opacity","metallic","roughness","glow","blend","crop_left","crop_right","crop_top","crop_bottom"]:
			var number: Variant=raw.get(key)
			if not (number is int or number is float) or not is_finite(number):return null
		if raw.x<0 or raw.x>1 or raw.y<0 or raw.y>1 or raw.size<.10 or raw.size>1.0 or absf(raw.angle)>180.0:return null
		if raw.opacity<0 or raw.opacity>1.0 or raw.metallic<0 or raw.metallic>1.0 or raw.roughness<0 or raw.roughness>1.0 or raw.glow<0 or raw.glow>2.0:return null
		if raw.blend!=floor(raw.blend) or int(raw.blend) not in range(BLENDS.size()):return null
		for key in ["crop_left","crop_right","crop_top","crop_bottom"]:
			if raw[key]<0.0 or raw[key]>.4:return null
		match raw.kind:
			"paint","image":
				encoded_size+=raw.data.length()
				if encoded_size>MAX_DOCUMENT:return null
				if not raw.data.is_empty() and not valid_image(raw.data):return null
			"text":
				if raw.data.length()>48 or raw.data.contains("\n") or raw.data.contains("\r"):return null
			"shape":
				if raw.data not in SHAPES:return null
		if raw.has("mesh_paint"):
			if raw.kind!="paint" or not raw.mesh_paint is Dictionary or raw.mesh_paint.size()>32:return null
			for id in raw.mesh_paint:
				var pixels: Variant=raw.mesh_paint[id]
				if not surface_id(id) or not pixels is String or pixels.is_empty():return null
				encoded_size+=pixels.length()
				if encoded_size>MAX_DOCUMENT or not valid_image(pixels):return null
		if raw.has("projection") and (raw.kind!="image" or not _valid_projection(raw.projection)):return null
		for key in raw:item[key]=raw[key]
		item.blend=int(raw.blend)
		design.append(item)
	return design

static func surface_id(id: Variant) -> bool:
	if not id is String or id.length()>32 or id.count(":")!=1:return false
	var segment: String=id.get_slice(":",0)
	var index: String=id.get_slice(":",1)
	return segment.is_valid_identifier() and index.is_valid_int() and int(index)>=0 and int(index)<128

static func _valid_projection(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=4 or not surface_id(value.get("surface")):return false
	for field in ["center","normal","right"]:
		var coords: Variant=value.get(field)
		if not coords is Array or coords.size()!=3:return false
		for axis in coords:
			if not (axis is int or axis is float) or not is_finite(float(axis)) or absf(float(axis))>2.0:return false
	var normal:=vector(value.normal)
	var right:=vector(value.right)
	return absf(normal.length_squared()-1.0)<.01 and absf(right.length_squared()-1.0)<.01 and absf(normal.dot(right))<.01

static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

static func array(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

static func valid_image(data: String) -> bool:
	if data.length()>ceili(float(MAX_IMAGE)*4.0/3.0)+4:return false
	var hash:=data.sha256_text()
	if validated_images.has(hash):return true
	var bytes:=Marshalls.base64_to_raw(data)
	if bytes.size()>MAX_IMAGE or bytes.size()<33 or not _within(_png_size(bytes),PIXELS):return false
	if Marshalls.raw_to_base64(bytes)!=data:return false
	var image:=Image.new()
	if image.load_png_from_buffer(bytes)!=OK or not _within(image.get_size(),PIXELS):return false
	if validated_images.size()>=80:validated_images.erase(validated_images.keys()[0])
	validated_images[hash]=true
	return true

static func encode(image: Image) -> String:
	if image==null or image.is_empty():return ""
	var dimensions:=image.get_size()
	var scale:=float(PIXELS)/float(maxi(dimensions.x,dimensions.y))
	if scale<1.0:image.resize(maxi(1,roundi(dimensions.x*scale)),maxi(1,roundi(dimensions.y*scale)),Image.INTERPOLATE_LANCZOS)
	var bytes:=image.save_png_to_buffer()
	if bytes.size()>MAX_IMAGE:
		image.resize(maxi(1,roundi(image.get_width()*.63)),maxi(1,roundi(image.get_height()*.63)),Image.INTERPOLATE_LANCZOS)
		bytes=image.save_png_to_buffer()
	return Marshalls.raw_to_base64(bytes) if bytes.size()<=MAX_IMAGE else ""

static func decode(data: String) -> Image:
	if not valid_image(data):return null
	var image:=Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(data))!=OK or not _within(image.get_size(),PIXELS):return null
	return image

static func import_image(bytes: PackedByteArray, extension: String) -> Image:
	if bytes.size()<16 or bytes.size()>MAX_IMPORT:return null
	var dimensions := Vector2i.ZERO
	match extension:
		"png":dimensions=_png_size(bytes)
		"jpg","jpeg":dimensions=_jpg_size(bytes)
		"webp":dimensions=_webp_size(bytes)
	if not _within(dimensions,3072):return null
	var image:=Image.new()
	var error:=ERR_FILE_UNRECOGNIZED
	match extension:
		"png":error=image.load_png_from_buffer(bytes)
		"jpg","jpeg":error=image.load_jpg_from_buffer(bytes)
		"webp":error=image.load_webp_from_buffer(bytes)
	if error!=OK or not _within(image.get_size(),3072):return null
	image.convert(Image.FORMAT_RGBA8)
	return image

static func _within(size: Vector2i, max_side: int) -> bool:
	return size.x>0 and size.y>0 and size.x<=max_side and size.y<=max_side

static func _png_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size()<24 or not bytes.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]) or bytes.slice(12,16).get_string_from_ascii()!="IHDR":return Vector2i.ZERO
	var w:=bytes[16]*16777216+bytes[17]*65536+bytes[18]*256+bytes[19]
	var h:=bytes[20]*16777216+bytes[21]*65536+bytes[22]*256+bytes[23]
	return Vector2i(w,h) if w<=3072 and h<=3072 else Vector2i.ZERO

static func _jpg_size(bytes: PackedByteArray) -> Vector2i:
	if bytes[0]!=255 or bytes[1]!=216:return Vector2i.ZERO
	var offset:=2
	while offset+9<bytes.size() and bytes[offset]==255:
		var marker:=bytes[offset+1]
		var length:=bytes[offset+2]*256+bytes[offset+3]
		if length<2 or offset+2+length>bytes.size():return Vector2i.ZERO
		if marker in [192,193,194] and length>=8:
			return Vector2i(bytes[offset+7]*256+bytes[offset+8],bytes[offset+5]*256+bytes[offset+6])
		offset+=length+2
	return Vector2i.ZERO

static func _webp_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size()<30 or bytes.slice(0,4).get_string_from_ascii()!="RIFF" or bytes.slice(8,12).get_string_from_ascii()!="WEBP":return Vector2i.ZERO
	match bytes.slice(12,16).get_string_from_ascii():
		"VP8X":
			if bytes[20]&2:return Vector2i.ZERO
			return Vector2i(1+bytes[24]+bytes[25]*256+bytes[26]*65536,1+bytes[27]+bytes[28]*256+bytes[29]*65536)
		"VP8L":
			if bytes[20]!=47:return Vector2i.ZERO
			var bits:=bytes.decode_u32(21)
			return Vector2i(1+(bits&16383),1+((bits>>14)&16383))
		"VP8 ":
			if bytes.slice(23,26)!=PackedByteArray([157,1,42]):return Vector2i.ZERO
			return Vector2i(bytes.decode_u16(26)&16383,bytes.decode_u16(28)&16383)
	return Vector2i.ZERO
