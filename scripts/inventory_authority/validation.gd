extends RefCounted
# Shape checks precede the existing typed circuit validators on untrusted RPC data.
static func count(value: Variant,limit: int=100000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=limit and float(value)==floor(float(value))
static func strings(value: Variant) -> bool:
	return value is Array and value.all(func(item):return item is String)
static func programs(value: Variant) -> bool:
	if not value is Dictionary:return false
	for program in value.values():
		if not program is Dictionary or not program.get("firmware","") is String or not preload("res://scripts/inventory_authority/firmware_schema.gd").part(program):return false
	return true
static func definitions(value: Variant) -> bool:
	if not value is Dictionary or value.size()>1000:return false
	for id in value:
		if not id is String:return false
		var bp=value[id]
		if bp is Dictionary and (not bp.get("component_runtime",{}) is Dictionary or not bp.get("component_runtime",{}).is_empty()):return false # Mutable memory belongs to owned instances.
		if not bp is Dictionary or not bp.get("parts") is Array or not bp.get("pins") is Array or not bp.get("wires") is Array:return false
		if not programs(bp.get("programs",{})):return false
		if not strings(bp.get("exposed",[])):return false
		for part in bp.parts:
			if not part is Dictionary or not part.get("type") is String or not part.get("id") is String:return false
			if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(part):return false
			if part.id.is_empty() or part.id.length()>64 or "/" in part.id:return false
			if not strings(part.get("nodes",[part.get("a",""),part.get("b","")])):return false
		if not preload("res://scripts/inventory_authority/io_control_schema.gd").valid(bp.get("io_controls",{}),bp.parts,value,""):return false
		for pin in bp.pins:
			if not pin is Dictionary or not pin.get("name") is String or not pin.get("node") is String:return false
		if bp.has("footprint"):
			if not bp.footprint is Dictionary or not count(bp.footprint.get("width"),80) or not count(bp.footprint.get("height"),80):return false
			if not bp.get("layout") is Dictionary or not count(bp.layout.get("rows"),40) or not bp.layout.get("parts") is Array or not bp.layout.get("wires") is Array:return false
			for part in bp.layout.parts:
				if not part is Dictionary or not strings(part.get("pins",[part.get("a"),part.get("b")])) or not preload("res://scripts/inventory_authority/firmware_schema.gd").part(part):return false
		if not package_metadata(bp):return false
	return true
static func package_metadata(bp: Dictionary) -> bool:
	if not bp.get("marking","") is String or bp.get("marking","").length()>80 or bp.get("orientation_marker","dot") not in ["dot","notch","triangle","none"]:return false
	var footprint: Dictionary=bp.get("footprint",{})
	for key in ["body_height_mm","thickness_mm"]:
		if footprint.has(key):
			var number=footprint[key]
			if not (number is int or number is float) or not is_finite(float(number)) or number<.1 or number>100:return false
	var ids := {};var positions := {};var positioned := 0
	for index in bp.pins.size():
		var pin: Dictionary=bp.pins[index];var id=pin.get("id","pin_"+str(index+1))
		if not id is String or id.is_empty() or id.length()>64 or ids.has(id):return false
		ids[id]=true
		if pin.get("role","unspecified") not in ["unspecified","input","output","bidirectional","power","ground","analog","clock","no_connect"] or pin.get("connector","male_header") not in ["male_header","female_header","through_hole","terminal_block","test_point"]:return false
		if pin.has("position"):
			positioned+=1
			if not pin.position is Dictionary or not count(pin.position.get("x"),79) or not count(pin.position.get("y"),79):return false
			var x := int(pin.position.x);var y := int(pin.position.y);var key := str(x)+":"+str(y)
			if x>=int(footprint.get("width",0)) or y>=int(footprint.get("height",0)) or positions.has(key):return false
			positions[key]=true
	return positioned==0 or positioned==bp.pins.size()
static func board(value: Variant) -> bool:
	if not value is Dictionary or not count(value.get("rows"),60) or not value.get("parts") is Array or not value.get("wires") is Array:return false
	if not preload("res://scripts/inventory_authority/component_persistence.gd").valid(value.get("component_runtime",{})) or not value.get("instance_ids",{}) is Dictionary:return false
	if value.get("instance_ids",{}).size()>48:return false
	var seen := {}
	for id in value.get("instance_ids",{}):
		var instance=value.instance_ids[id]
		if not id is String or not instance is String or instance.is_empty() or instance.length()>96 or seen.has(instance):return false
		seen[instance]=true
	if not definitions(value.get("definitions",{})) or not programs(value.get("programs",{})):return false
	if not strings(value.get("ports")):return false
	if not preload("res://scripts/inventory_authority/io_control_schema.gd").valid(value.get("io_controls",{}),value.parts,value.get("definitions",{})):return false
	for part in value.parts:
		if not part is Dictionary or not part.get("type") is String or not part.get("id") is String:return false
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(part):return false
		if part.id.is_empty() or part.id.length()>64 or "/" in part.id:return false
		if not strings(part.get("pins",[part.get("a"),part.get("b")])):return false
	return true
