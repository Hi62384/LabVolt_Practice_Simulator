extends RefCounted
const Model=preload("res://scripts/breadboard_model.gd")
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")

static func translated(board: Dictionary, ids: Array, dx: int, dy: int) -> Dictionary:
	var result: Dictionary=board.duplicate(true)
	for part in result.parts:
		if part.id not in ids:continue
		var keys: Array=["a","b"]
		for key in keys:
			var hole: String=str(part[key]);var x:=int(hole.substr(1))+dx;var y: int="PNABCDEFGHIJ".find(hole.left(1))+dy
			if x<1 or x>int(board.rows) or y<0 or y>=12:return {"error":"Move outside board"}
			part[key]="PNABCDEFGHIJ"[y]+str(x)
		if part.has("pins"):
			var pins: Array=[]
			for hole in part.pins:
				var x:=int(str(hole).substr(1))+dx;var y: int="PNABCDEFGHIJ".find(str(hole).left(1))+dy
				if x<1 or x>int(board.rows) or y<0 or y>=12:return {"error":"Move outside board"}
				pins.append("PNABCDEFGHIJ"[y]+str(x))
			part.pins=pins
	return {"board":result,"error":Model.validate(result,{},true)}

static func candidate(board: Dictionary, type_id: String, anchor: String, end: String, turns: int) -> Dictionary:
	var result: Dictionary=board.duplicate(true)
	var part: Dictionary={"id":"placement_preview","type":type_id,"a":anchor,"b":end,"pressed":false}
	var definition: Dictionary=board.get("definitions",{}).get(type_id,{})
	var catalog: Dictionary=Model.catalog(board)
	if not catalog.has(type_id):return {"error":"Unknown component"}
	if anchor=="" or end=="" or anchor==end:return {"error":"Choose two distinct mounting holes"}
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
		var pivot:=Vector2i(int(anchor.substr(1))-1,"PNABCDEFGHIJ".find(anchor.left(1)))
		var pins: Array=[]
		for hole in Model.pins(part):
			var point:=Vector2i(int(str(hole).substr(1))-1,"PNABCDEFGHIJ".find(str(hole).left(1)))-pivot
			for turn in posmod(turns,4):point=Vector2i(-point.y,point.x)
			point+=pivot
			if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=12:return {"error":"Rotated pins outside board"}
			pins.append("PNABCDEFGHIJ"[point.y]+str(point.x+1))
		part.a=pins[0];part.b=pins[-1]
		if part.has("pins"):part.pins=pins
		part.surface_rotation=posmod(turns,4)*PI/2
	result.parts.append(part)
	var error: String=Model.validate(result,{},true)
	return {"error":error,"board":result,"part":part}
