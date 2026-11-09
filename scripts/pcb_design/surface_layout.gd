extends RefCounted

const Geometry = preload("res://scripts/package_editor/package_geometry.gd")

static func visible(bp: Dictionary, id: String) -> bool:
	if bp.has("surface_layout"): return bp.surface_layout.has(id)
	return bp.get("package","IC") == "PCB" or id in bp.get("exposed",[])

static func extent(type: String, definitions: Dictionary, turns: int) -> Vector2i:
	var dimensions := Vector2i(3,2)
	match type:
		"spi_display","ssd1306","io_graphic": dimensions = Vector2i(8,4)
		"hd44780","hd44780_20x4": dimensions = Vector2i(12,5)
		"ili9341","xpt2046","io_keypad": dimensions = Vector2i(7,9)
		"io_slider","ws2812","io_bar","io_pixels": dimensions = Vector2i(8,3)
		"io_matrix","io_joystick","io_servo": dimensions = Vector2i(5,5)
		"io_selector","io_encoder","io_motor","io_vibration","io_bridge","io_relay": dimensions = Vector2i(4,3)
		"seven_segment": dimensions = Vector2i(4,4)
		"native_uno","native_pico","native_nano": dimensions = Vector2i(8,4)
		"button","toggle","pot10k","led","led_green","led_blue","led_yellow","buzzer","speaker": dimensions = Vector2i(2,2)
		"battery": dimensions = Vector2i(4,3)
	if type.begins_with("ic:"):
		var fp: Dictionary = definitions.get(type,{}).get("footprint",{})
		dimensions = Vector2i(clampi(int(fp.get("width",4)),2,39),clampi(int(fp.get("height",3)),2,39))
	return dimensions if posmod(turns,2) == 0 else Vector2i(dimensions.y,dimensions.x)

static func rect(record: Dictionary, type: String, definitions: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(int(record.x),int(record.y)),extent(type,definitions,int(record.turns)))

static func validate(bp: Dictionary, definitions: Dictionary) -> String:
	if not bp.has("surface_layout"): return ""
	if bp.get("package") != "PCB" or not bp.surface_layout is Dictionary or bp.surface_layout.size() > 48:
		return "Invalid PCB surface layout."
	var fp: Dictionary = bp.get("footprint",{})
	var width := int(bp.get("width_intervals",0))
	var length := int(bp.get("length_positions",0))
	var turns := int(bp.get("orientation_turns",0))
	if turns < 0 or turns > 3 or width < 1 or length < 2 or width > 39 or length > 40:
		return "Invalid PCB grid dimensions."
	var expected := Vector2i(width+1,length) if turns % 2 == 0 else Vector2i(length,width+1)
	if expected != Vector2i(int(fp.get("width",0)),int(fp.get("height",0))): return "PCB outline and dimensions disagree."
	var types := {}
	for part in bp.parts: types[part.id] = part.type
	var bounds: Array[Rect2i] = []
	var inside := Rect2i(1,1,width-1,length-2)
	for id in bp.surface_layout:
		var item: Variant = bp.surface_layout[id]
		if not types.has(id) or not item is Dictionary: return "A surface part is missing from the circuit."
		for key in ["x","y","turns"]:
			var value: Variant = item.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or int(value) != value or value < 0 or value > 40:
				return "Surface parts must align with the grid."
		if int(item.turns)>3: return "Invalid surface part rotation."
		var shape := rect(item,types[id],definitions)
		if not inside.encloses(shape): return "A surface component extends past the board clearance."
		for other in bounds:
			if other.intersects(shape): return "Surface components overlap."
		for pin in bp.pins:
			var point := Geometry.rotate(Geometry.position(pin)-offset(width,length,turns),-turns)
			if shape.has_point(point): return "A surface component overlaps an external pin."
		bounds.append(shape)
	return ""

static func offset(width: int, length: int, turns: int) -> Vector2i:
	match turns:
		1: return Vector2i(length-1,0)
		2: return Vector2i(width,length-1)
		3: return Vector2i(0,width)
	return Vector2i.ZERO

static func visual_point(bp: Dictionary, point: Vector2, view: Rect2, mounting_turns: int = 0) -> Vector2:
	var turns := int(bp.get("orientation_turns",0))
	var canonical_offset := offset(int(bp.get("width_intervals",1)),int(bp.get("length_positions",2)),turns)
	var local := point.rotated(turns*PI/2)+Vector2(canonical_offset)
	var size := Vector2(float(bp.footprint.width),float(bp.footprint.height))
	var normalized := (local+Vector2(.5,.5))/size
	var oriented := (normalized-Vector2(.5,.5)).rotated(mounting_turns*PI/2)+Vector2(.5,.5)
	return view.position+oriented*view.size

static func mounting_turn(part: Dictionary, board: Dictionary) -> int:
	return 0 if board.get("standalone",false) else posmod(roundi(float(part.get("surface_rotation",0.0))/(PI/2)),4)


static func view_rect(bp: Dictionary, record: Dictionary, type: String, definitions: Dictionary, view: Rect2, turns := 0) -> Rect2:
	var footprint := rect(record,type,definitions)
	var first := visual_point(bp,Vector2(footprint.position)-Vector2(.5,.5),view,turns)
	var last := visual_point(bp,Vector2(footprint.end)-Vector2(.5,.5),view,turns)
	return Rect2(first,last-first).abs()

static func part_color(type: String) -> Color:
	if type.begins_with("led"): return Color("a44638")
	if type.contains("display") or type in ["io_lcd","io_oled","io_tft","seven_segment"]: return Color("2d424e")
	if type in ["button","toggle","pot10k"]: return Color("aa713b")
	if type.begins_with("res") or type.begins_with("r_"): return Color("d2b77e")
	if type.begins_with("cap"): return Color("526e9c")
	return Color("333d47")
