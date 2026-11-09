extends RefCounted
## Optional physical schema. Legacy height is footprint length, never body height.
const MAX_PINS := 64
const MOUNTING_ROWS := "ABCDE-FGHIJ"
const LEGACY_ROWS := "PNABCDEFGHIJ"
const LOWER_ROWS := "WXKLMOQRSTUV"

static func mounting_rows(bp: Dictionary) -> String:
	return MOUNTING_ROWS if bp.get("pin_grid") == "terminal_pitch" else LEGACY_ROWS

static func bank_rows(hole: String) -> String:
	return LOWER_ROWS if not hole.is_empty() and hole.left(1) in LOWER_ROWS else LEGACY_ROWS

static func placement_rows(hole: String, terminal_pitch: bool) -> String:
	var bank := bank_rows(hole)
	return bank.substr(2,5)+"-"+bank.substr(7,5) if terminal_pitch else bank
const CONNECTORS := ["male_header","female_header","through_hole","terminal_block","test_point"]
const ROLES := ["unspecified","input","output","bidirectional","power","ground","analog","clock","no_connect"]
static func electrical_node(hole: String, rows: int) -> String:
	if hole.length()<2:return ""
	var row := int(hole.substr(1))
	if row<1 or row>rows:return ""
	var column := hole.left(1)
	var lower := LOWER_ROWS.find(column)
	if lower>=0:return "lower/"+electrical_node(LEGACY_ROWS[lower]+hole.substr(1),rows)
	if column in "YZ":return column+str(0 if row<=rows/2 else 1)
	if column in ["P","N"]:return column+str(0 if row<=rows/2 else 1)
	if column in "ABCDE":return "L"+str(row)
	if column in "FGHIJ":return "R"+str(row)
	return ""

static func position(pin: Dictionary) -> Vector2i:
	var p: Dictionary=pin.get("position",{})
	return Vector2i(int(p.get("x",0)),int(p.get("y",0)))
static func explicit_pins(bp: Dictionary) -> bool:
	return bp.get("pins",[]) is Array and not bp.get("pins",[]).is_empty() and bp.pins[0] is Dictionary and bp.pins[0].has("position")
static func validate(bp: Dictionary) -> String:
	var footprint: Dictionary=bp.get("footprint",{})
	if footprint.is_empty():return ""
	for key in ["width","height"]:
		var value=footprint.get(key,0)
		var minimum := 1 if mounting_rows(bp) == MOUNTING_ROWS else 2
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=int(value) or int(value)<minimum or int(value)>80:return "Invalid package grid dimensions"
	for key in ["body_height_mm","thickness_mm"]:
		if not footprint.has(key):continue
		var value=footprint[key]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<.1 or float(value)>100:return "Package height/thickness must be 0.1–100 mm"
	if not Color.html_is_valid(str(footprint.get("color",""))):return "Invalid package color"
	if str(bp.get("marking","")).length()>80 or str(bp.get("orientation_marker","dot")) not in ["dot","notch","triangle","none"]:return "Invalid package marking"
	var identities := {};var occupied := {};var has_positions := explicit_pins(bp)
	for index in bp.pins.size():
		var pin=bp.pins[index]
		if not pin is Dictionary:return "Invalid package pin"
		var id := str(pin.get("id","pin_%d"%(index+1)))
		if id.is_empty() or id.length()>64 or identities.has(id):return "Pins need unique stable IDs"
		identities[id]=true
		if str(pin.get("role","unspecified")) not in ROLES or str(pin.get("connector","male_header")) not in CONNECTORS:return "Invalid pin role or connector"
		if pin.has("position")!=has_positions:return "Assign physical positions to all pins or none"
		if not has_positions:continue
		if not pin.position is Dictionary:return "Invalid physical pin position"
		for axis in ["x","y"]:
			var v=pin.position.get(axis,-1)
			if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=int(v):return "Pins must align with the integer breadboard grid"
		var p := position(pin)
		if p.x<0 or p.y<0 or p.x>=int(footprint.width) or p.y>=int(footprint.height):return "Pin outside package footprint"
		if occupied.has(p):return "Physical pin positions overlap"
		occupied[p]=true
	return ""
static func rotate(p: Vector2i,turns: int) -> Vector2i:
	for i in posmod(turns,4):p=Vector2i(-p.y,p.x)
	return p
static func grid(hole: String) -> Vector2i:
	return Vector2i(int(hole.substr(1))-1,(LEGACY_ROWS+LOWER_ROWS).find(hole.left(1)))
static func placement(part: Dictionary,bp: Dictionary) -> Dictionary:
	var holes: Array=part.get("pins",[part.get("a",""),part.get("b","")])
	if holes.is_empty():return {"ok":false}
	var first := str(holes[0])
	var bank := bank_rows(first)
	for hole in holes:
		if bank_rows(str(hole)) != bank:return {"ok":false}
	if not explicit_pins(bp):
		var origin := Vector2i(1000,1000)
		for hole in holes:origin=origin.min(grid(str(hole)))
		return {"ok":true,"rect":Rect2i(origin,Vector2i(int(bp.footprint.width),int(bp.footprint.height)))}
	if holes.size()!=bp.pins.size():return {"ok":false}
	var terminal_pitch := mounting_rows(bp) == MOUNTING_ROWS
	var row_names := placement_rows(first,terminal_pitch)
	var bank_offset := LEGACY_ROWS.length() if bank == LOWER_ROWS else 0
	for turns in 4:
		var origin := mount_point(str(holes[0]),row_names)-rotate(position(bp.pins[0]),turns)
		var aligned := true
		for i in holes.size():
			var point := mount_point(str(holes[i]),row_names)
			if point.y < 0 or point != origin+rotate(position(bp.pins[i]),turns):aligned=false;break
		if not aligned:continue
		var low := Vector2i(1000,1000);var high := Vector2i(-1000,-1000)
		for corner in [Vector2i.ZERO,Vector2i(int(bp.footprint.width)-1,0),Vector2i(0,int(bp.footprint.height)-1),Vector2i(int(bp.footprint.width)-1,int(bp.footprint.height)-1)]:
			var p := origin+rotate(corner,turns);low=low.min(p);high=high.max(p)
		if terminal_pitch:
			if low.y < 0 or high.y >= row_names.length(): return {"ok":false}
			low.y = bank.find(row_names[low.y + 1] if row_names[low.y] == "-" else row_names[low.y])
			high.y = bank.find(row_names[high.y - 1] if row_names[high.y] == "-" else row_names[high.y])
		if low.y < 0 or high.y >= bank.length():return {"ok":false}
		low.y += bank_offset
		high.y += bank_offset
		return {"ok":true,"rect":Rect2i(low,high-low+Vector2i.ONE),"turns":turns}
	return {"ok":false}
static func mount_point(hole: String, row_names: String) -> Vector2i:
	return Vector2i(int(hole.substr(1))-1,row_names.find(hole.left(1)))

static func holes_at(bp: Dictionary,anchor: String,rows: int) -> Array:
	var result: Array=[]
	var row_names := placement_rows(anchor,mounting_rows(bp)==MOUNTING_ROWS)
	var origin := mount_point(anchor,row_names)-position(bp.pins[0])
	for pin in bp.pins:
		var p := origin+position(pin)
		if p.x<0 or p.x>=rows or p.y<0 or p.y>=row_names.length() or row_names[p.y]=="-":return []
		result.append(row_names[p.y]+str(p.x+1))
	return result
