extends RefCounted
const Model=preload("res://scripts/breadboard_model.gd")
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")

static func translated(board: Dictionary, ids: Array, dx: int, dy: int) -> Dictionary:
	var result: Dictionary=board.duplicate(true)
	var rows := Model.hole_letters(board)
	for part in result.parts:
		if part.id not in ids:continue
		var keys: Array=["a","b"]
		for key in keys:
			var hole: String=str(part[key]);var x:=int(hole.substr(1))+dx;var y: int=rows.find(hole.left(1))+dy
			if x<1 or x>int(board.rows) or y<0 or y>=rows.length():return {"error":"Move outside board"}
			part[key]=rows[y]+str(x)
		if part.has("pins"):
			var pins: Array=[]
			for hole in part.pins:
				var x:=int(str(hole).substr(1))+dx;var y: int=rows.find(str(hole).left(1))+dy
				if x<1 or x>int(board.rows) or y<0 or y>=rows.length():return {"error":"Move outside board"}
				pins.append(rows[y]+str(x))
			part.pins=pins
	return {"board":result,"error":Model.validate(result,{},true)}

static func candidate(board: Dictionary, type_id: String, anchor: String, end: String, turns: int) -> Dictionary:
	var result: Dictionary=board.duplicate(true)
	var part: Dictionary={"id":"placement_preview","type":type_id,"a":anchor,"b":end,"pressed":false}
	var definition: Dictionary=board.get("definitions",{}).get(type_id,{})
	var catalog: Dictionary=Model.catalog(board)
	if not catalog.has(type_id):return {"error":"Unknown component"}
	if type_id=="solar_panel":
		return maker_candidate(board,catalog,{},true,type_id,"",anchor,turns)
	if anchor=="" or end=="" or anchor==end:return {"error":"Choose two distinct mounting holes"}
	if Geometry.bank_rows(anchor)==Geometry.LOWER_ROWS and uses_footprint(board,catalog,type_id):
		return maker_candidate(board,catalog,{},true,type_id,"",anchor,turns)
	if Geometry.explicit_pins(definition):
		part.pins=Geometry.holes_at(definition,anchor,int(board.rows))
		if part.pins.is_empty():return {"error":"Package does not fit here"}
		part.a=part.pins[0];part.b=part.pins[-1]
	elif catalog[type_id].pins.size()>2:
		part.pins=[]
		var count: int=catalog[type_id].pins.size()
		for pin in count:
			var base: String=anchor if pin<(count+1)/2 else end
			part.pins.append(base.left(1)+str(int(base.substr(1))+pin%((count+1)/2)))
	if turns!=0:
		var rows := Model.hole_letters(board)
		var pivot:=Model.grid(anchor)
		var pins: Array=[]
		for hole in Model.pins(part):
			var point:=Model.grid(str(hole))-pivot
			for turn in posmod(turns,4):point=Vector2i(-point.y,point.x)
			point+=pivot
			if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=rows.length():return {"error":"Rotated pins outside board"}
			pins.append(rows[point.y]+str(point.x+1))
		part.a=pins[0];part.b=pins[-1]
		if part.has("pins"):part.pins=pins
		part.surface_rotation=posmod(turns,4)*PI/2
	result.parts.append(part)
	var error: String=Model.validate(result,{},true)
	return {"error":error,"board":result,"part":part}

static func uses_footprint(board: Dictionary, catalog: Dictionary, type_id: String) -> bool:
	var count: int = catalog.get(type_id, {}).get("pins", []).size()
	return type_id=="solar_panel" or Geometry.explicit_pins(board.get("definitions", {}).get(type_id, {})) or count == 1 or count > 2

static func maker_candidate(board: Dictionary, catalog: Dictionary, stock: Dictionary, unlimited: bool, type_id: String, first: String, hover: String, turns: int) -> Dictionary:
	var entry: Dictionary = catalog.get(type_id,{})
	var count: int = entry.get("pins",[]).size()
	if count == 0 or Model.node(hover,int(board.rows)).is_empty(): return {"error":"Choose a valid mounting hole."}
	var part := {"id":"placement_preview","type":type_id,"a":first,"b":hover,"pressed":false}
	if not uses_footprint(board, catalog, type_id):
		if first.is_empty() or first == hover: return {"error":"Choose two distinct mounting holes."}
		if turns != 0:
			part.a = hover
			part.b = first
	else:
		var origin := Model.grid(hover)
		var package: Dictionary = board.get("definitions",{}).get(type_id,{})
		var explicit := Geometry.explicit_pins(package)
		var rows := Model.hole_letters(board) if type_id=="solar_panel" else Geometry.placement_rows(hover,not explicit or Geometry.mounting_rows(package)==Geometry.MOUNTING_ROWS)
		origin.y = rows.find(hover.left(1))
		if origin.y < 0: return {"error":"Use the terminal strip for this package."}
		var offsets: Array[Vector2i] = []
		if type_id=="solar_panel":
			offsets.assign([Vector2i.ZERO, Vector2i.RIGHT])
			part.solar_footprint=true
		elif explicit:
			var pin_one := Geometry.position(package.pins[0])
			for pin in package.pins: offsets.append(Geometry.position(pin)-pin_one)
		elif count == 3:
			for index in count: offsets.append(Vector2i(index,0))
		else:
			var half := ceili(count*.5)
			for index in count:
				offsets.append(Vector2i(index,0) if index < half else Vector2i(count-1-index,3))
		part.pins = []
		for offset in offsets:
			var point := origin + Geometry.rotate(offset,turns)
			if point.x < 0 or point.x >= int(board.rows) or point.y < 0 or point.y >= rows.length():
				return {"error":"The package extends past the board."}
			if rows[point.y] == "-":
				return {"error":"A pin falls into the center gap."}
			part.pins.append(rows[point.y]+str(point.x+1))
		part.a = part.pins[0]
		part.b = part.pins[-1]
		part.surface_rotation = posmod(turns,4)*PI*.5
	var candidate := board.duplicate(true)
	candidate.parts.append(part)
	return {"error":Model.validate(candidate,stock,unlimited),"part":part,"board":candidate}

